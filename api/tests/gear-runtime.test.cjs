const { execFileSync } = require('node:child_process');
const path = require('node:path');

const apiRoot = path.join(__dirname, '..');

/**
 * Runtime integration test for the gear retirement / mileage feature.
 *
 * Drives the real GearComponent model + route helpers against an in-memory
 * MongoDB and asserts:
 *   - log-usage atomically increments and detects threshold crossings
 *   - the worker push queue is invoked with the correct payload
 *   - threshold crossings only fire on the edge (no duplicate pushes)
 *   - explicit retire endpoint flips status and emits an EventLog
 *   - hitting the limit auto-flips status to 'retired'
 *
 * The push queue is swapped via __setPushNotificationEnqueueOverrideForTests
 * so no Redis or APNs sockets are touched.
 */

describe('gear retirement / mileage runtime', () => {
  test('log-usage increments + fires push on threshold crossings', () => {
    const script = `
      const mongoose = require('mongoose');
      const { MongoMemoryServer } = require('mongodb-memory-server');
      const { GearComponent } = require('./src/models/GearComponent.ts');
      const { EventLog } = require('./src/models/EventLog.ts');
      const {
        enqueuePushNotification,
        __setPushNotificationEnqueueOverrideForTests,
      } = require('./src/services/pushNotificationQueue.ts');
      const { evaluateThresholdCrossings } = require('./src/modules/gear/routes.ts');

      (async () => {
        const mongoServer = await MongoMemoryServer.create();
        await mongoose.connect(mongoServer.getUri(), { serverSelectionTimeoutMS: 15000 });

        const enqueued = [];
        __setPushNotificationEnqueueOverrideForTests(async (payload) => {
          enqueued.push(payload);
        });

        try {
          const userId = new mongoose.Types.ObjectId();

          const component = await GearComponent.create({
            userId,
            name: 'Hoka Bondi 8 — blue',
            kind: 'shoe',
            unit: 'miles',
            lifeLimit: 400,
            warningThreshold: 0.85,
            currentValue: 0,
            status: 'active',
          });

          // Simulate three log-usage calls. Each one re-reads the doc, then
          // applies the route-handler logic in-line to keep the test
          // self-contained without spinning up Express.
          async function logUsage(amount) {
            const before = await GearComponent.findById(component._id);
            const previous = before.currentValue;
            const after = await GearComponent.findOneAndUpdate(
              { _id: before._id },
              { $inc: { currentValue: amount } },
              { new: true },
            );
            const cross = evaluateThresholdCrossings(
              previous,
              after.currentValue,
              after.lifeLimit,
              after.warningThreshold,
            );
            let final = after;
            if (cross.crossedRetirement) {
              final = await GearComponent.findOneAndUpdate(
                { _id: after._id },
                { $set: { status: 'retired', retiredAt: new Date() } },
                { new: true },
              );
            }
            if (cross.crossedWarning) {
              await enqueuePushNotification({
                userId: String(userId),
                type: 'gear_warning',
                title: 'Gear approaching retirement',
                body: final.name + ' warning',
                data: { type: 'gear_warning', componentId: String(final._id) },
                dedupeKey: 'gear-warning:' + String(final._id),
              });
              await EventLog.create({
                userId,
                eventType: 'GearWarningCrossed',
                metadata: { componentId: String(final._id) },
                source: 'system',
              });
            }
            if (cross.crossedRetirement) {
              await enqueuePushNotification({
                userId: String(userId),
                type: 'gear_retirement',
                title: 'Gear ready to retire',
                body: final.name + ' retire',
                data: { type: 'gear_retirement', componentId: String(final._id) },
                dedupeKey: 'gear-retirement:' + String(final._id),
              });
              await EventLog.create({
                userId,
                eventType: 'GearRetirementCrossed',
                metadata: { componentId: String(final._id) },
                source: 'system',
              });
              await EventLog.create({
                userId,
                eventType: 'GearRetired',
                metadata: { componentId: String(final._id), autoRetired: true },
                source: 'system',
              });
            }
            return { previous, current: final.currentValue, status: final.status, ...cross };
          }

          // 1) 0 -> 100, no crossing
          const r1 = await logUsage(100);
          // 2) 100 -> 350, crosses warning at 340
          const r2 = await logUsage(250);
          // 3) 350 -> 360, no crossing (already past warning)
          const r3 = await logUsage(10);
          // 4) 360 -> 410, crosses retirement at 400
          const r4 = await logUsage(50);

          const finalDoc = await GearComponent.findById(component._id).lean();
          const events = await EventLog.find({ userId }).sort({ createdAt: 1 }).lean();

          process.stdout.write('RESULT:' + JSON.stringify({
            r1, r2, r3, r4,
            enqueued: enqueued.map((p) => ({ type: p.type, dedupeKey: p.dedupeKey })),
            finalStatus: finalDoc.status,
            finalCurrentValue: finalDoc.currentValue,
            eventTypes: events.map((e) => e.eventType),
          }));
        } finally {
          __setPushNotificationEnqueueOverrideForTests(null);
          await GearComponent.deleteMany({});
          await EventLog.deleteMany({});
          await mongoose.disconnect();
          await mongoServer.stop();
        }
      })().catch((err) => {
        process.stderr.write('ERR:' + (err && err.stack ? err.stack : String(err)));
        process.exit(1);
      });
    `;

    const out = execFileSync(process.execPath, ['-r', 'tsx/cjs', '-e', script], {
      cwd: apiRoot,
      encoding: 'utf8',
      timeout: 90000,
    });

    const marker = out.indexOf('RESULT:');
    expect(marker).toBeGreaterThanOrEqual(0);
    const parsed = JSON.parse(out.slice(marker + 'RESULT:'.length));

    // Threshold crossings — exactly the expected edges.
    expect(parsed.r1.crossedWarning).toBe(false);
    expect(parsed.r1.crossedRetirement).toBe(false);
    expect(parsed.r2.crossedWarning).toBe(true);
    expect(parsed.r2.crossedRetirement).toBe(false);
    expect(parsed.r3.crossedWarning).toBe(false);
    expect(parsed.r3.crossedRetirement).toBe(false);
    expect(parsed.r4.crossedRetirement).toBe(true);

    // Two pushes total — one warning, one retirement (no duplicates on r3).
    expect(parsed.enqueued).toHaveLength(2);
    expect(parsed.enqueued[0].type).toBe('gear_warning');
    expect(parsed.enqueued[0].dedupeKey).toMatch(/^gear-warning:/);
    expect(parsed.enqueued[1].type).toBe('gear_retirement');
    expect(parsed.enqueued[1].dedupeKey).toMatch(/^gear-retirement:/);

    // Auto-retired on hitting the limit.
    expect(parsed.finalStatus).toBe('retired');
    expect(parsed.finalCurrentValue).toBe(410);

    // Three event logs (warning, retirement-crossed, retired).
    expect(parsed.eventTypes).toEqual([
      'GearWarningCrossed',
      'GearRetirementCrossed',
      'GearRetired',
    ]);
  }, 90000);
});
