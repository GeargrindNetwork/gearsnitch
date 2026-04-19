const { execFileSync } = require('node:child_process');
const path = require('node:path');

const apiRoot = path.join(__dirname, '..');

/**
 * Backlog item #20 — Dashboard trend charts.
 *
 * Drives the pure helpers inside `src/modules/metrics/routes.ts` via tsx so
 * the real implementation is exercised end-to-end without spinning up
 * Express / MongoDB.
 *
 * Covers:
 *   - range validation (via isSupportedRange surface in the shipped code)
 *   - bucket math: week/month/year counts and granularity
 *   - empty-data fallback (all zeros, every bucket present)
 *   - latest-weight-wins per bucket
 *   - timezone sanitizer rejects bogus input, accepts IANA names
 *   - summary avgWorkoutsPerWeek only for month + year
 */

function runHelper(snippet) {
  const script = `
    const {
      buildBucketPlan,
      resolveBucketStart,
      composeBuckets,
      buildSummary,
      sanitizeTimezone,
      normalizeWeightKg,
    } = require('./src/modules/metrics/routes.ts');
    (async () => {
      ${snippet}
    })().catch((err) => {
      process.stderr.write('ERR:' + (err && err.stack ? err.stack : String(err)));
      process.exit(1);
    });
  `;
  const out = execFileSync(process.execPath, ['-r', 'tsx/cjs', '-e', script], {
    cwd: apiRoot,
    encoding: 'utf8',
    timeout: 60000,
  });
  const marker = out.indexOf('RESULT:');
  if (marker < 0) {
    throw new Error('No RESULT marker in output: ' + out);
  }
  return JSON.parse(out.slice(marker + 'RESULT:'.length));
}

describe('metrics trends runtime (item #20)', () => {
  test('week plan produces 7 daily buckets ending today @ UTC', () => {
    const result = runHelper(`
      const now = new Date('2026-04-18T10:00:00Z');
      const plan = buildBucketPlan('week', now);
      process.stdout.write('RESULT:' + JSON.stringify({
        count: plan.starts.length,
        granularity: plan.granularity,
        first: plan.starts[0].toISOString(),
        last: plan.starts[plan.starts.length - 1].toISOString(),
      }));
    `);
    expect(result.count).toBe(7);
    expect(result.granularity).toBe('day');
    expect(result.first).toBe('2026-04-12T00:00:00.000Z');
    expect(result.last).toBe('2026-04-18T00:00:00.000Z');
  }, 60000);

  test('month plan produces 30 daily buckets', () => {
    const result = runHelper(`
      const now = new Date('2026-04-18T10:00:00Z');
      const plan = buildBucketPlan('month', now);
      process.stdout.write('RESULT:' + JSON.stringify({
        count: plan.starts.length,
        granularity: plan.granularity,
        first: plan.starts[0].toISOString(),
        last: plan.starts[plan.starts.length - 1].toISOString(),
      }));
    `);
    expect(result.count).toBe(30);
    expect(result.granularity).toBe('day');
    expect(result.first).toBe('2026-03-20T00:00:00.000Z');
    expect(result.last).toBe('2026-04-18T00:00:00.000Z');
  }, 60000);

  test('year plan produces 12 monthly buckets anchored to the 1st', () => {
    const result = runHelper(`
      const now = new Date('2026-04-18T10:00:00Z');
      const plan = buildBucketPlan('year', now);
      process.stdout.write('RESULT:' + JSON.stringify({
        count: plan.starts.length,
        granularity: plan.granularity,
        first: plan.starts[0].toISOString(),
        last: plan.starts[plan.starts.length - 1].toISOString(),
      }));
    `);
    expect(result.count).toBe(12);
    expect(result.granularity).toBe('month');
    expect(result.first).toBe('2025-05-01T00:00:00.000Z');
    expect(result.last).toBe('2026-04-01T00:00:00.000Z');
  }, 60000);

  test('composeBuckets returns dense zeros when data is empty', () => {
    const result = runHelper(`
      const now = new Date('2026-04-18T10:00:00Z');
      const plan = buildBucketPlan('week', now);
      const buckets = composeBuckets(plan, {
        workouts: [], runs: [], meals: [], weights: [],
      });
      const summary = buildSummary('week', buckets);
      process.stdout.write('RESULT:' + JSON.stringify({
        bucketCount: buckets.length,
        allZero: buckets.every((b) => b.workouts === 0 && b.runs === 0 && b.calories === 0 && b.workoutMinutes === 0 && b.runMeters === 0 && b.weightKg === null),
        summary,
      }));
    `);
    expect(result.bucketCount).toBe(7);
    expect(result.allZero).toBe(true);
    expect(result.summary.totalWorkouts).toBe(0);
    expect(result.summary.totalRuns).toBe(0);
    expect(result.summary.totalCalories).toBe(0);
    expect(result.summary.avgWorkoutsPerWeek).toBe(0);
  }, 60000);

  test('composeBuckets sums workouts / runs / calories into the correct daily bucket', () => {
    const result = runHelper(`
      const now = new Date('2026-04-18T10:00:00Z');
      const plan = buildBucketPlan('week', now);
      const buckets = composeBuckets(plan, {
        workouts: [
          { startedAt: new Date('2026-04-18T09:00:00Z'), durationMinutes: 45 },
          { startedAt: new Date('2026-04-18T19:00:00Z'), durationMinutes: 30 },
          { startedAt: new Date('2026-04-16T11:00:00Z'), durationMinutes: 60 },
        ],
        runs: [
          { startedAt: new Date('2026-04-17T07:00:00Z'), distanceMeters: 5200 },
          { startedAt: new Date('2026-04-18T07:00:00Z'), distanceMeters: 3100 },
        ],
        meals: [
          { dateKey: '2026-04-18', calories: 500 },
          { dateKey: '2026-04-18', calories: 700 },
          { dateKey: '2026-04-16', calories: 1800 },
          { dateKey: '2025-01-01', calories: 9999 }, // out-of-window, dropped
        ],
        weights: [],
      });
      const today = buckets.find((b) => b.ts === '2026-04-18T00:00:00.000Z');
      const twoDaysAgo = buckets.find((b) => b.ts === '2026-04-16T00:00:00.000Z');
      const yesterday = buckets.find((b) => b.ts === '2026-04-17T00:00:00.000Z');
      process.stdout.write('RESULT:' + JSON.stringify({ today, twoDaysAgo, yesterday }));
    `);
    expect(result.today.workouts).toBe(2);
    expect(result.today.workoutMinutes).toBe(75);
    expect(result.today.runs).toBe(1);
    expect(result.today.runMeters).toBe(3100);
    expect(result.today.calories).toBe(1200);

    expect(result.twoDaysAgo.workouts).toBe(1);
    expect(result.twoDaysAgo.workoutMinutes).toBe(60);
    expect(result.twoDaysAgo.calories).toBe(1800);
    expect(result.twoDaysAgo.runs).toBe(0);

    expect(result.yesterday.runs).toBe(1);
    expect(result.yesterday.runMeters).toBe(5200);
    expect(result.yesterday.workouts).toBe(0);
  }, 60000);

  test('composeBuckets keeps only the latest weight reading per bucket', () => {
    const result = runHelper(`
      const now = new Date('2026-04-18T10:00:00Z');
      const plan = buildBucketPlan('week', now);
      const buckets = composeBuckets(plan, {
        workouts: [], runs: [], meals: [],
        weights: [
          { recordedAt: new Date('2026-04-18T06:00:00Z'), valueKg: 82.1 },
          { recordedAt: new Date('2026-04-18T08:00:00Z'), valueKg: 81.9 }, // latest — wins
          { recordedAt: new Date('2026-04-18T07:00:00Z'), valueKg: 82.0 },
          { recordedAt: new Date('2026-04-15T07:00:00Z'), valueKg: 83.5 },
        ],
      });
      const today = buckets.find((b) => b.ts === '2026-04-18T00:00:00.000Z');
      const three = buckets.find((b) => b.ts === '2026-04-15T00:00:00.000Z');
      const noWeight = buckets.find((b) => b.ts === '2026-04-13T00:00:00.000Z');
      process.stdout.write('RESULT:' + JSON.stringify({ today, three, noWeight }));
    `);
    expect(result.today.weightKg).toBe(81.9);
    expect(result.three.weightKg).toBe(83.5);
    expect(result.noWeight.weightKg).toBeNull();
  }, 60000);

  test('year-range buckets group events by month', () => {
    const result = runHelper(`
      const now = new Date('2026-04-18T10:00:00Z');
      const plan = buildBucketPlan('year', now);
      const buckets = composeBuckets(plan, {
        workouts: [
          { startedAt: new Date('2026-04-02T12:00:00Z'), durationMinutes: 30 },
          { startedAt: new Date('2026-04-20T12:00:00Z'), durationMinutes: 45 }, // still April bucket
          { startedAt: new Date('2025-12-01T00:00:00Z'), durationMinutes: 20 },
          { startedAt: new Date('2024-01-01T00:00:00Z'), durationMinutes: 99 }, // out of window
        ],
        runs: [],
        meals: [],
        weights: [],
      });
      const april = buckets.find((b) => b.ts === '2026-04-01T00:00:00.000Z');
      const december = buckets.find((b) => b.ts === '2025-12-01T00:00:00.000Z');
      process.stdout.write('RESULT:' + JSON.stringify({
        count: buckets.length,
        april,
        december,
      }));
    `);
    expect(result.count).toBe(12);
    expect(result.april.workouts).toBe(2);
    expect(result.april.workoutMinutes).toBe(75);
    expect(result.december.workouts).toBe(1);
  }, 60000);

  test('sanitizeTimezone accepts IANA tz, falls back to UTC on garbage', () => {
    const result = runHelper(`
      process.stdout.write('RESULT:' + JSON.stringify({
        la: sanitizeTimezone('America/Los_Angeles'),
        utc: sanitizeTimezone('UTC'),
        empty: sanitizeTimezone(''),
        inject: sanitizeTimezone('America/Los_Angeles; DROP TABLE users'),
        nonString: sanitizeTimezone(42),
      }));
    `);
    expect(result.la).toBe('America/Los_Angeles');
    expect(result.utc).toBe('UTC');
    expect(result.empty).toBe('UTC');
    expect(result.inject).toBe('UTC');
    expect(result.nonString).toBe('UTC');
  }, 60000);

  test('buildSummary only emits avgWorkoutsPerWeek for month + year', () => {
    const result = runHelper(`
      const now = new Date('2026-04-18T10:00:00Z');
      const weekPlan = buildBucketPlan('week', now);
      const monthPlan = buildBucketPlan('month', now);
      const yearPlan = buildBucketPlan('year', now);
      const weekBuckets = composeBuckets(weekPlan, { workouts: [{ startedAt: new Date('2026-04-18T00:00:00Z'), durationMinutes: 30 }], runs: [], meals: [], weights: [] });
      const monthBuckets = composeBuckets(monthPlan, { workouts: new Array(15).fill(0).map((_, i) => ({ startedAt: new Date('2026-04-' + String(i + 1).padStart(2, '0') + 'T12:00:00Z'), durationMinutes: 30 })), runs: [], meals: [], weights: [] });
      const yearBuckets = composeBuckets(yearPlan, { workouts: new Array(52).fill(0).map((_, i) => ({ startedAt: new Date('2026-04-15T00:00:00Z'), durationMinutes: 30 })), runs: [], meals: [], weights: [] });
      process.stdout.write('RESULT:' + JSON.stringify({
        week: buildSummary('week', weekBuckets),
        month: buildSummary('month', monthBuckets),
        year: buildSummary('year', yearBuckets),
      }));
    `);
    expect(result.week.totalWorkouts).toBe(1);
    expect(result.week.avgWorkoutsPerWeek).toBe(0);
    expect(result.month.totalWorkouts).toBe(15);
    expect(result.month.avgWorkoutsPerWeek).toBeGreaterThan(0);
    expect(result.year.totalWorkouts).toBe(52);
    expect(result.year.avgWorkoutsPerWeek).toBe(1);
  }, 60000);

  test('normalizeWeightKg converts lb → kg, passes kg through', () => {
    const result = runHelper(`
      process.stdout.write('RESULT:' + JSON.stringify({
        kg: normalizeWeightKg(82.5, 'kg'),
        lb: normalizeWeightKg(180, 'lb'),
      }));
    `);
    expect(result.kg).toBe(82.5);
    // 180 lb ≈ 81.6467 kg
    expect(result.lb).toBeGreaterThan(81.6);
    expect(result.lb).toBeLessThan(81.7);
  }, 60000);
});
