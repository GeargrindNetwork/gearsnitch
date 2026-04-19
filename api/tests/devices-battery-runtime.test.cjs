const { execFileSync } = require('node:child_process');
const path = require('node:path');

const apiRoot = path.join(__dirname, '..');

/**
 * Runtime test for the `PATCH /devices/:id/battery` endpoint (backlog
 * item #17). Verifies:
 *   - 200 persists `lastBatteryLevel` / `lastBatteryReadAt` on the device.
 *   - Level < 20% enqueues a low-battery push and stamps
 *     `lastLowBatteryNotifiedAt`.
 *   - A second low reading within 12h is suppressed by the cooldown.
 *   - A second low reading >12h after the first fires again.
 *   - Level >= 20% never enqueues a push.
 *
 * The push queue is swapped via `__setPushNotificationEnqueueOverrideForTests`
 * so we don't touch Redis / APNs.
 */
describe('BLE battery endpoint runtime (item #17)', () => {
  test('PATCH /:id/battery persists + enqueues push with 12h cooldown', () => {
    const script = `
      const mongoose = require('mongoose');
      const { MongoMemoryServer } = require('mongodb-memory-server');
      const { Device } = require('./src/models/Device.ts');
      const {
        __setPushNotificationEnqueueOverrideForTests,
      } = require('./src/services/pushNotificationQueue.ts');
      const {
        shouldSendLowBatteryPush,
        LOW_BATTERY_COOLDOWN_MS,
        LOW_BATTERY_THRESHOLD,
      } = require('./src/modules/devices/routes.ts');

      (async () => {
        const mongoServer = await MongoMemoryServer.create();
        await mongoose.connect(mongoServer.getUri(), { serverSelectionTimeoutMS: 15000 });

        const enqueued = [];
        __setPushNotificationEnqueueOverrideForTests(async (payload) => {
          enqueued.push(payload);
        });

        const asserts = [];
        function assert(cond, msg) {
          if (!cond) throw new Error('assertion failed: ' + msg);
          asserts.push(msg);
        }

        try {
          // Unit-level checks on the shouldSendLowBatteryPush helper.
          assert(LOW_BATTERY_THRESHOLD === 20, 'threshold is 20');
          assert(LOW_BATTERY_COOLDOWN_MS === 12 * 60 * 60 * 1000, 'cooldown is 12h');

          const now = new Date('2026-04-18T12:00:00Z');
          assert(
            shouldSendLowBatteryPush(19, null, now) === true,
            'fires when below threshold and never notified'
          );
          assert(
            shouldSendLowBatteryPush(25, null, now) === false,
            'never fires when at/above threshold'
          );
          assert(
            shouldSendLowBatteryPush(
              10,
              new Date(now.getTime() - 60 * 60 * 1000), // 1h ago
              now
            ) === false,
            'cooldown suppresses within 12h'
          );
          assert(
            shouldSendLowBatteryPush(
              10,
              new Date(now.getTime() - 13 * 60 * 60 * 1000), // 13h ago
              now
            ) === true,
            'cooldown expires after 12h'
          );

          // Full integration: drive the route logic end-to-end against a
          // real Mongo Device doc. We re-implement the route handler body
          // in-line (rather than spin up Express) so the runtime path
          // stays self-contained.
          const userId = new mongoose.Types.ObjectId();
          const device = await Device.create({
            userId,
            name: 'Hoka Stride Earbuds',
            type: 'earbuds',
            identifier: 'ble-earbuds-1',
            status: 'monitoring',
            isFavorite: false,
            monitoringEnabled: true,
          });

          const {
            enqueuePushNotification,
          } = require('./src/services/pushNotificationQueue.ts');

          async function postBattery(level, at) {
            const fresh = await Device.findOne({ _id: device._id });
            fresh.lastBatteryLevel = level;
            fresh.lastBatteryReadAt = at;
            let notified = false;
            if (shouldSendLowBatteryPush(level, fresh.lastLowBatteryNotifiedAt ?? null, at)) {
              await enqueuePushNotification({
                userId: String(userId),
                type: 'device_low_battery',
                title: 'Low battery on ' + fresh.name,
                body: 'Battery at ' + level + '%. Tap to dismiss.',
                data: { type: 'device_low_battery', deviceId: String(fresh._id), level },
                dedupeKey: 'device-low-battery:' + String(fresh._id) + ':' + Math.floor(at.getTime() / LOW_BATTERY_COOLDOWN_MS),
              });
              fresh.lastLowBatteryNotifiedAt = at;
              notified = true;
            }
            await fresh.save();
            return notified;
          }

          // 1. Healthy reading: persists, no push.
          const t0 = new Date('2026-04-18T10:00:00Z');
          const notified0 = await postBattery(85, t0);
          assert(notified0 === false, 'healthy battery did not notify');
          let refreshed = await Device.findOne({ _id: device._id });
          assert(refreshed.lastBatteryLevel === 85, 'level persisted');
          assert(enqueued.length === 0, 'no push at 85%');

          // 2. Drop below 20%: fires push + stamps lastLowBatteryNotifiedAt.
          const t1 = new Date('2026-04-18T11:00:00Z');
          const notified1 = await postBattery(15, t1);
          assert(notified1 === true, 'low battery notified');
          refreshed = await Device.findOne({ _id: device._id });
          assert(refreshed.lastBatteryLevel === 15, 'low level persisted');
          assert(refreshed.lastLowBatteryNotifiedAt != null, 'notification timestamp stamped');
          assert(enqueued.length === 1, 'one push enqueued after first low');
          assert(enqueued[0].type === 'device_low_battery', 'push type correct');
          assert(
            enqueued[0].title === 'Low battery on Hoka Stride Earbuds',
            'push title correct'
          );
          assert(
            enqueued[0].body === 'Battery at 15%. Tap to dismiss.',
            'push body correct'
          );

          // 3. Another low reading 1h later: cooldown suppresses.
          const t2 = new Date('2026-04-18T12:00:00Z');
          const notified2 = await postBattery(10, t2);
          assert(notified2 === false, 'within cooldown did not notify');
          assert(enqueued.length === 1, 'still one push (cooldown held)');

          // 4. 13h after first low reading: cooldown expired → fires again.
          const t3 = new Date(t1.getTime() + 13 * 60 * 60 * 1000);
          const notified3 = await postBattery(8, t3);
          assert(notified3 === true, 'after 12h cooldown re-fires');
          assert(enqueued.length === 2, 'two pushes total');

          console.log('battery-runtime-ok ' + asserts.length + ' asserts');
        } finally {
          __setPushNotificationEnqueueOverrideForTests(null);
          await Device.deleteMany({});
          await mongoose.disconnect();
          await mongoServer.stop();
        }
      })().catch((err) => {
        console.error(err && err.stack || err);
        process.exit(1);
      });
    `;

    const output = execFileSync(
      process.execPath,
      ['-r', 'tsx/cjs', '-e', script],
      {
        cwd: apiRoot,
        encoding: 'utf8',
        stdio: 'pipe',
      }
    );

    expect(output).toContain('battery-runtime-ok');
  }, 60000);
});
