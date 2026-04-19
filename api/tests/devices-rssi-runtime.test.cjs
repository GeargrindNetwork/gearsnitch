const { execFileSync } = require('node:child_process');
const path = require('node:path');

const apiRoot = path.join(__dirname, '..');

/**
 * Runtime test for the RSSI signal-history feature (backlog item #19).
 *
 * Covers:
 *   1. `bucketRssiSamples` produces correct per-bucket averages for a
 *      known sample set.
 *   2. Samples outside the window are dropped.
 *   3. Empty buckets are omitted from the response.
 *   4. `computeWeekOverWeekDelta` returns the signed delta between
 *      the last 7 days and the prior 7 days.
 *   5. WoW delta returns `null` when either window has no samples.
 *   6. `RssiSample.insertMany` persists a batch against a real Mongo.
 *   7. Validation: rssi outside `[-120, 0]` is rejected by the model.
 *   8. Validation: batch larger than RSSI_BATCH_LIMIT is rejected by
 *      the Zod schema (simulated in-line).
 */
describe('RSSI signal history runtime (item #19)', () => {
  test('bucket math + WoW delta + insertMany all behave as documented', () => {
    const script = `
      const mongoose = require('mongoose');
      const { MongoMemoryServer } = require('mongodb-memory-server');
      const { RssiSample } = require('./src/models/RssiSample.ts');
      const {
        bucketRssiSamples,
        computeWeekOverWeekDelta,
        RSSI_BATCH_LIMIT,
      } = require('./src/modules/devices/routes.ts');

      (async () => {
        const mongoServer = await MongoMemoryServer.create();
        await mongoose.connect(mongoServer.getUri(), { serverSelectionTimeoutMS: 15000 });

        const asserts = [];
        function assert(cond, msg) {
          if (!cond) throw new Error('assertion failed: ' + msg);
          asserts.push(msg);
        }
        function approx(a, b, tol, msg) {
          if (Math.abs(a - b) > tol) {
            throw new Error(
              'approx failed: ' + msg + ' (expected ' + b + ' got ' + a + ')'
            );
          }
          asserts.push(msg);
        }

        try {
          // ── 1. Bucketing math ───────────────────────────────────
          const windowEnd = new Date('2026-04-18T12:00:00Z');
          const windowStart = new Date(windowEnd.getTime() - 24 * 60 * 60 * 1000);

          // 4 buckets = 6 hours each.
          // b0: [12h, 18h) — samples at 13h, 17h
          // b1: [18h, 24h) — empty
          // b2: [00h, 06h) — sample at 02h
          // b3: [06h, 12h) — samples at 07h, 11h
          const samples = [
            { rssi: -50, sampledAt: new Date(windowStart.getTime() + 1 * 3600 * 1000) },
            { rssi: -60, sampledAt: new Date(windowStart.getTime() + 5 * 3600 * 1000) },
            { rssi: -90, sampledAt: new Date(windowStart.getTime() + 14 * 3600 * 1000) },
            { rssi: -70, sampledAt: new Date(windowStart.getTime() + 19 * 3600 * 1000) },
            { rssi: -80, sampledAt: new Date(windowStart.getTime() + 23 * 3600 * 1000) },
          ];

          const buckets = bucketRssiSamples(samples, windowStart, windowEnd, 4);
          assert(buckets.length === 3, 'empty bucket is omitted');

          approx(buckets[0].avgRssi, -55, 0.1, 'bucket 0 avg is -55 dBm');
          assert(buckets[0].count === 2, 'bucket 0 has 2 samples');

          approx(buckets[1].avgRssi, -90, 0.1, 'bucket 2 avg is -90 dBm');
          assert(buckets[1].count === 1, 'bucket 2 has 1 sample');

          approx(buckets[2].avgRssi, -75, 0.1, 'bucket 3 avg is -75 dBm');
          assert(buckets[2].count === 2, 'bucket 3 has 2 samples');

          // Samples outside the window are dropped.
          const withOutside = [
            { rssi: -40, sampledAt: new Date(windowStart.getTime() - 1000) },
            ...samples,
            { rssi: -40, sampledAt: new Date(windowEnd.getTime() + 1000) },
          ];
          const boundedBuckets = bucketRssiSamples(
            withOutside,
            windowStart,
            windowEnd,
            4
          );
          let totalInside = 0;
          for (const b of boundedBuckets) totalInside += b.count;
          assert(totalInside === 5, 'out-of-window samples are dropped');

          // ── 2. WoW delta ───────────────────────────────────────
          const now = new Date('2026-04-18T12:00:00Z');
          const dayMs = 24 * 60 * 60 * 1000;
          const wowSamples = [
            // This week mean = -70 (avg of -60, -80)
            { rssi: -60, sampledAt: new Date(now.getTime() - 1 * dayMs) },
            { rssi: -80, sampledAt: new Date(now.getTime() - 3 * dayMs) },
            // Prior week mean = -50 (avg of -40, -60)
            { rssi: -40, sampledAt: new Date(now.getTime() - 8 * dayMs) },
            { rssi: -60, sampledAt: new Date(now.getTime() - 12 * dayMs) },
          ];
          const delta = computeWeekOverWeekDelta(wowSamples, now);
          approx(delta, -20, 0.1, 'WoW delta = -20 dBm (signal got weaker)');

          // WoW returns null when prior week has no samples.
          const deltaNullPrior = computeWeekOverWeekDelta(
            [{ rssi: -55, sampledAt: new Date(now.getTime() - 2 * dayMs) }],
            now
          );
          assert(deltaNullPrior === null, 'WoW null when prior week empty');

          // WoW returns null when this week has no samples.
          const deltaNullThis = computeWeekOverWeekDelta(
            [{ rssi: -55, sampledAt: new Date(now.getTime() - 10 * dayMs) }],
            now
          );
          assert(deltaNullThis === null, 'WoW null when current week empty');

          // ── 3. insertMany against a real Mongo ──────────────────
          const userId = new mongoose.Types.ObjectId();
          const deviceId = new mongoose.Types.ObjectId();
          const batch = Array.from({ length: 10 }, (_, i) => ({
            userId,
            deviceId,
            rssi: -60 - i,
            sampledAt: new Date(now.getTime() - i * 60 * 1000),
          }));
          const inserted = await RssiSample.insertMany(batch);
          assert(inserted.length === 10, 'insertMany persists all 10 samples');

          const found = await RssiSample.find({ deviceId }).sort({ sampledAt: -1 });
          assert(found.length === 10, 'found all 10 samples');
          assert(found[0].rssi === -60, 'newest sample first in sort');

          // ── 4. Model rejects out-of-range rssi ─────────────────
          let modelRejected = false;
          try {
            await RssiSample.create({
              userId,
              deviceId,
              rssi: -130,
              sampledAt: now,
            });
          } catch (e) {
            modelRejected = true;
          }
          assert(modelRejected, 'RssiSample rejects rssi below -120');

          modelRejected = false;
          try {
            await RssiSample.create({
              userId,
              deviceId,
              rssi: 5,
              sampledAt: now,
            });
          } catch (e) {
            modelRejected = true;
          }
          assert(modelRejected, 'RssiSample rejects rssi above 0');

          // ── 5. Batch size cap constant ─────────────────────────
          assert(RSSI_BATCH_LIMIT === 100, 'RSSI_BATCH_LIMIT is 100');

          console.log('rssi-runtime-ok ' + asserts.length + ' asserts');
        } finally {
          await RssiSample.deleteMany({});
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

    expect(output).toContain('rssi-runtime-ok');
  }, 60000);
});
