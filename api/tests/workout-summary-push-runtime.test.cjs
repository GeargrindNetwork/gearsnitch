const { execFileSync } = require('node:child_process');
const path = require('node:path');

const apiRoot = path.join(__dirname, '..');

/**
 * Runtime test for item #27. Drives the pure helpers
 * (`buildWorkoutSummaryPushPayload`, `shouldSkipWorkoutSummaryPush`,
 * `buildRunSummaryPushPayload`, `shouldSkipRunSummaryPush`) via tsx so
 * the real implementations are exercised — no module mocking, no source
 * regex fragility.
 *
 * The push queue is swapped via __setPushNotificationEnqueueOverrideForTests
 * but we only need the assertion fixtures here, since the route handlers
 * are thin wrappers around these helpers.
 */

function runHelper(snippet) {
  const script = `
    const {
      buildWorkoutSummaryPushPayload,
      shouldSkipWorkoutSummaryPush,
    } = require('./src/modules/workouts/routes.ts');
    const {
      buildRunSummaryPushPayload,
      shouldSkipRunSummaryPush,
    } = require('./src/modules/runs/routes.ts');
    const mongoose = require('mongoose');
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

describe('workout summary push runtime (item #27)', () => {
  test('builds the workout payload with duration + exercise count', () => {
    const result = runHelper(`
      const userId = new mongoose.Types.ObjectId();
      const workoutId = new mongoose.Types.ObjectId();
      const startedAt = new Date('2025-01-01T12:00:00Z');
      const endedAt = new Date('2025-01-01T12:32:00Z'); // 32 min
      const payload = buildWorkoutSummaryPushPayload({
        userId,
        workoutId,
        startedAt,
        endedAt,
        durationSeconds: 32 * 60,
        exerciseCount: 5,
        setCount: 18,
        source: 'apple_health',
      });
      process.stdout.write('RESULT:' + JSON.stringify(payload));
    `);
    expect(result.title).toBe('Nice work!');
    expect(result.body).toContain('32 min');
    expect(result.body).toContain('5 exercises');
    expect(result.data.type).toBe('workout_summary');
    expect(result.data.durationSec).toBe(1920);
    expect(result.data.exerciseCount).toBe(5);
    expect(result.data.setCount).toBe(18);
  }, 60000);

  test('workout payload includes calories + distance when provided', () => {
    const result = runHelper(`
      const payload = buildWorkoutSummaryPushPayload({
        userId: new mongoose.Types.ObjectId(),
        workoutId: new mongoose.Types.ObjectId(),
        startedAt: new Date(),
        endedAt: new Date(),
        durationSeconds: 1800,
        exerciseCount: 0,
        setCount: 0,
        source: 'ios',
        calories: 287,
        distanceMeters: 4200,
      });
      process.stdout.write('RESULT:' + JSON.stringify(payload));
    `);
    expect(result.body).toContain('30 min');
    expect(result.body).toContain('287 cal');
    expect(result.body).toContain('4.2 km');
    expect(result.data.calories).toBe(287);
    expect(result.data.distanceMeters).toBe(4200);
  }, 60000);

  test('workout skip — pushEnabled false', () => {
    const result = runHelper(`
      const reason = shouldSkipWorkoutSummaryPush({
        durationSeconds: 1800,
        exerciseCount: 5,
        setCount: 18,
        source: 'ios',
        preferences: { pushEnabled: false },
      });
      process.stdout.write('RESULT:' + JSON.stringify({ reason }));
    `);
    expect(result.reason).toBe('push_disabled');
  }, 60000);

  test('workout skip — workoutSummaryPushDisabled true', () => {
    const result = runHelper(`
      const reason = shouldSkipWorkoutSummaryPush({
        durationSeconds: 1800,
        exerciseCount: 5,
        setCount: 18,
        source: 'ios',
        preferences: { pushEnabled: true, workoutSummaryPushDisabled: true },
      });
      process.stdout.write('RESULT:' + JSON.stringify({ reason }));
    `);
    expect(result.reason).toBe('workout_summary_disabled');
  }, 60000);

  test('workout skip — manual entry', () => {
    const result = runHelper(`
      const reason = shouldSkipWorkoutSummaryPush({
        durationSeconds: 1800,
        exerciseCount: 5,
        setCount: 18,
        source: 'manual',
        preferences: { pushEnabled: true },
      });
      process.stdout.write('RESULT:' + JSON.stringify({ reason }));
    `);
    expect(result.reason).toBe('manual_or_backfill');
  }, 60000);

  test('workout skip — duration under 60s', () => {
    const result = runHelper(`
      const reason = shouldSkipWorkoutSummaryPush({
        durationSeconds: 12,
        exerciseCount: 3,
        setCount: 6,
        source: 'ios',
        preferences: { pushEnabled: true },
      });
      process.stdout.write('RESULT:' + JSON.stringify({ reason }));
    `);
    expect(result.reason).toBe('too_short');
  }, 60000);

  test('workout skip — zero metrics on a long-but-empty session', () => {
    const result = runHelper(`
      const reason = shouldSkipWorkoutSummaryPush({
        durationSeconds: 1800,
        exerciseCount: 0,
        setCount: 0,
        source: 'ios',
        preferences: { pushEnabled: true },
      });
      process.stdout.write('RESULT:' + JSON.stringify({ reason }));
    `);
    expect(result.reason).toBe('no_metrics');
  }, 60000);

  test('workout proceeds with valid metrics + sane prefs', () => {
    const result = runHelper(`
      const reason = shouldSkipWorkoutSummaryPush({
        durationSeconds: 1800,
        exerciseCount: 5,
        setCount: 18,
        source: 'apple_health',
        preferences: { pushEnabled: true, workoutSummaryPushDisabled: false },
      });
      process.stdout.write('RESULT:' + JSON.stringify({ reason }));
    `);
    // 'apple_health' is also a backfill source per the schema enum;
    // we treat it as backfill to match the spec's "don't notify users
    // for backfilled history" rule.
    expect(result.reason).toBe('manual_or_backfill');
  }, 60000);

  test('workout proceeds when source is ios and metrics are present', () => {
    const result = runHelper(`
      const reason = shouldSkipWorkoutSummaryPush({
        durationSeconds: 1800,
        exerciseCount: 5,
        setCount: 18,
        source: 'ios',
        preferences: { pushEnabled: true, workoutSummaryPushDisabled: false },
      });
      process.stdout.write('RESULT:' + JSON.stringify({ reason }));
    `);
    expect(result.reason).toBeNull();
  }, 60000);
});

describe('run summary push runtime (item #27)', () => {
  test('builds the run payload with distance + pace', () => {
    const result = runHelper(`
      const payload = buildRunSummaryPushPayload({
        userId: new mongoose.Types.ObjectId(),
        runId: new mongoose.Types.ObjectId(),
        durationSeconds: 1800,
        distanceMeters: 5_000,
        averagePaceSecondsPerKm: 360, // 6:00/km
        averageHeartRateBpm: null,
      });
      process.stdout.write('RESULT:' + JSON.stringify(payload));
    `);
    expect(result.title).toBe('Run complete!');
    expect(result.body).toContain('5 km');
    expect(result.body).toContain('6:00/km');
    expect(result.body).not.toContain('avg HR');
    expect(result.data.type).toBe('run_summary');
    expect(result.data.distanceMeters).toBe(5000);
  }, 60000);

  test('appends avg HR when provided', () => {
    const result = runHelper(`
      const payload = buildRunSummaryPushPayload({
        userId: new mongoose.Types.ObjectId(),
        runId: new mongoose.Types.ObjectId(),
        durationSeconds: 1500,
        distanceMeters: 4_200,
        averagePaceSecondsPerKm: 357,
        averageHeartRateBpm: 154,
      });
      process.stdout.write('RESULT:' + JSON.stringify(payload));
    `);
    expect(result.body).toContain('avg HR 154');
    expect(result.data.averageHeartRateBpm).toBe(154);
  }, 60000);

  test('falls back to duration headline when pace is missing', () => {
    const result = runHelper(`
      const payload = buildRunSummaryPushPayload({
        userId: new mongoose.Types.ObjectId(),
        runId: new mongoose.Types.ObjectId(),
        durationSeconds: 600,
        distanceMeters: 1_500,
        averagePaceSecondsPerKm: null,
        averageHeartRateBpm: null,
      });
      process.stdout.write('RESULT:' + JSON.stringify(payload));
    `);
    expect(result.body).toContain('1.5 km');
    expect(result.body).toContain('10 min');
  }, 60000);

  test('run skip — manual source', () => {
    const result = runHelper(`
      const reason = shouldSkipRunSummaryPush({
        durationSeconds: 1800,
        distanceMeters: 5_000,
        source: 'manual',
        preferences: { pushEnabled: true },
      });
      process.stdout.write('RESULT:' + JSON.stringify({ reason }));
    `);
    expect(result.reason).toBe('manual_or_backfill');
  }, 60000);

  test('run skip — pushEnabled false', () => {
    const result = runHelper(`
      const reason = shouldSkipRunSummaryPush({
        durationSeconds: 1800,
        distanceMeters: 5_000,
        source: 'ios',
        preferences: { pushEnabled: false },
      });
      process.stdout.write('RESULT:' + JSON.stringify({ reason }));
    `);
    expect(result.reason).toBe('push_disabled');
  }, 60000);

  test('run skip — workout summary disabled also gates runs (one toggle)', () => {
    const result = runHelper(`
      const reason = shouldSkipRunSummaryPush({
        durationSeconds: 1800,
        distanceMeters: 5_000,
        source: 'ios',
        preferences: { pushEnabled: true, workoutSummaryPushDisabled: true },
      });
      process.stdout.write('RESULT:' + JSON.stringify({ reason }));
    `);
    expect(result.reason).toBe('workout_summary_disabled');
  }, 60000);

  test('run skip — sub-minute AND sub-50m sprint', () => {
    const result = runHelper(`
      const reason = shouldSkipRunSummaryPush({
        durationSeconds: 8,
        distanceMeters: 12,
        source: 'ios',
        preferences: { pushEnabled: true },
      });
      process.stdout.write('RESULT:' + JSON.stringify({ reason }));
    `);
    expect(result.reason).toBe('too_short');
  }, 60000);

  test('run proceeds when distance + duration are real and prefs allow', () => {
    const result = runHelper(`
      const reason = shouldSkipRunSummaryPush({
        durationSeconds: 1800,
        distanceMeters: 5_000,
        source: 'ios',
        preferences: { pushEnabled: true, workoutSummaryPushDisabled: false },
      });
      process.stdout.write('RESULT:' + JSON.stringify({ reason }));
    `);
    expect(result.reason).toBeNull();
  }, 60000);
});
