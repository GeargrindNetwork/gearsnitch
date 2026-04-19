const { execFileSync } = require('node:child_process');
const path = require('node:path');

/**
 * Backlog item #39 — achievement badge rule tests.
 *
 * Drives the pure evaluators from `modules/achievements/service.ts` via tsx
 * (same pattern as the workout/run push runtime tests in item #27) so the
 * real TypeScript implementations are exercised — no module mocking.
 *
 * Covers the full catalog:
 *   first_run, first_workout, first_device_paired, first_purchase,
 *   streak_7d, streak_30d, hundred_sessions, hundred_miles
 */

const apiRoot = path.join(__dirname, '..');

function runHelper(snippet) {
  const script = `
    const {
      evaluateBadgeRule,
      progressFor,
      computeCurrentStreakDays,
      BADGE_CATALOG,
      BADGE_IDS,
    } = require('./src/modules/achievements/service.ts');
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

const ZERO_STATS = {
  runCount: 0,
  workoutCount: 0,
  deviceCount: 0,
  subscriptionChargeCount: 0,
  totalRunMeters: 0,
  currentStreakDays: 0,
};

function fixtureBody(statsOverrides, badgeId) {
  return `
    const stats = Object.assign(${JSON.stringify(ZERO_STATS)}, ${JSON.stringify(statsOverrides)});
    const earned = evaluateBadgeRule(${JSON.stringify(badgeId)}, stats);
    const progress = progressFor(${JSON.stringify(badgeId)}, stats);
    process.stdout.write('RESULT:' + JSON.stringify({ earned, progress }));
  `;
}

describe('achievement badge rules (item #39)', () => {
  test('catalog exposes all 8 expected badges', () => {
    const result = runHelper(`
      process.stdout.write('RESULT:' + JSON.stringify({
        ids: BADGE_IDS,
        titles: BADGE_CATALOG.map((b) => b.id + ':' + b.title),
        count: BADGE_CATALOG.length,
      }));
    `);
    expect(result.count).toBe(8);
    expect(result.ids).toEqual(expect.arrayContaining([
      'first_run',
      'first_workout',
      'first_device_paired',
      'first_purchase',
      'streak_7d',
      'streak_30d',
      'hundred_sessions',
      'hundred_miles',
    ]));
  }, 60000);

  test('first_run — awarded on first completed run', () => {
    const zero = runHelper(fixtureBody({}, 'first_run'));
    expect(zero.earned).toBe(false);
    expect(zero.progress).toEqual({ current: 0, target: 1, label: '0/1 run' });

    const one = runHelper(fixtureBody({ runCount: 1 }, 'first_run'));
    expect(one.earned).toBe(true);
    expect(one.progress).toEqual({ current: 1, target: 1, label: '1/1 run' });
  }, 60000);

  test('first_workout — awarded on first completed workout', () => {
    const zero = runHelper(fixtureBody({}, 'first_workout'));
    expect(zero.earned).toBe(false);

    const one = runHelper(fixtureBody({ workoutCount: 1 }, 'first_workout'));
    expect(one.earned).toBe(true);
  }, 60000);

  test('first_device_paired — awarded as soon as deviceCount >= 1', () => {
    const zero = runHelper(fixtureBody({}, 'first_device_paired'));
    expect(zero.earned).toBe(false);
    const one = runHelper(fixtureBody({ deviceCount: 1 }, 'first_device_paired'));
    expect(one.earned).toBe(true);
  }, 60000);

  test('first_purchase — awarded as soon as subscriptionChargeCount >= 1', () => {
    const zero = runHelper(fixtureBody({}, 'first_purchase'));
    expect(zero.earned).toBe(false);
    const one = runHelper(fixtureBody({ subscriptionChargeCount: 1 }, 'first_purchase'));
    expect(one.earned).toBe(true);
  }, 60000);

  test('streak_7d — requires 7 consecutive days', () => {
    const six = runHelper(fixtureBody({ currentStreakDays: 6 }, 'streak_7d'));
    expect(six.earned).toBe(false);
    expect(six.progress).toEqual({ current: 6, target: 7, label: '6/7 day streak' });

    const seven = runHelper(fixtureBody({ currentStreakDays: 7 }, 'streak_7d'));
    expect(seven.earned).toBe(true);

    const twenty = runHelper(fixtureBody({ currentStreakDays: 20 }, 'streak_7d'));
    expect(twenty.earned).toBe(true);
    expect(twenty.progress.current).toBe(7); // clamped
  }, 60000);

  test('streak_30d — requires 30 consecutive days', () => {
    const twentyNine = runHelper(fixtureBody({ currentStreakDays: 29 }, 'streak_30d'));
    expect(twentyNine.earned).toBe(false);

    const thirty = runHelper(fixtureBody({ currentStreakDays: 30 }, 'streak_30d'));
    expect(thirty.earned).toBe(true);
  }, 60000);

  test('hundred_sessions — requires 100 workouts', () => {
    const ninetyNine = runHelper(fixtureBody({ workoutCount: 99 }, 'hundred_sessions'));
    expect(ninetyNine.earned).toBe(false);
    expect(ninetyNine.progress).toEqual({ current: 99, target: 100, label: '99/100 sessions' });

    const hundred = runHelper(fixtureBody({ workoutCount: 100 }, 'hundred_sessions'));
    expect(hundred.earned).toBe(true);
  }, 60000);

  test('hundred_miles — requires 100 miles of running (converted from meters)', () => {
    // 100 miles = 160934.4m
    const short = runHelper(fixtureBody({ totalRunMeters: 160_000 }, 'hundred_miles'));
    expect(short.earned).toBe(false);

    const exact = runHelper(fixtureBody({ totalRunMeters: 160_935 }, 'hundred_miles'));
    expect(exact.earned).toBe(true);

    // 50 mi * 1609.344 = 80467.2 m — add a hair to clear the floor() boundary.
    const progress = runHelper(fixtureBody({ totalRunMeters: 80_468 }, 'hundred_miles'));
    expect(progress.progress.current).toBe(50);
    expect(progress.progress.target).toBe(100);
  }, 60000);

  test('computeCurrentStreakDays — empty list returns 0', () => {
    const result = runHelper(`
      const streak = computeCurrentStreakDays([]);
      process.stdout.write('RESULT:' + JSON.stringify({ streak }));
    `);
    expect(result.streak).toBe(0);
  }, 60000);

  test('computeCurrentStreakDays — handles today + yesterday + day before', () => {
    const result = runHelper(`
      const today = new Date('2025-05-10T14:00:00Z');
      const d0 = new Date('2025-05-10T10:00:00Z');
      const d1 = new Date('2025-05-09T10:00:00Z');
      const d2 = new Date('2025-05-08T10:00:00Z');
      const streak = computeCurrentStreakDays([d0, d1, d2], today);
      process.stdout.write('RESULT:' + JSON.stringify({ streak }));
    `);
    expect(result.streak).toBe(3);
  }, 60000);

  test('computeCurrentStreakDays — gap breaks the streak', () => {
    const result = runHelper(`
      const today = new Date('2025-05-10T14:00:00Z');
      const d0 = new Date('2025-05-10T10:00:00Z');
      const d1 = new Date('2025-05-08T10:00:00Z'); // skip 2025-05-09
      const streak = computeCurrentStreakDays([d0, d1], today);
      process.stdout.write('RESULT:' + JSON.stringify({ streak }));
    `);
    expect(result.streak).toBe(1);
  }, 60000);

  test('computeCurrentStreakDays — yesterday-only still counts (streak alive)', () => {
    const result = runHelper(`
      const today = new Date('2025-05-10T14:00:00Z');
      const d1 = new Date('2025-05-09T10:00:00Z');
      const d2 = new Date('2025-05-08T10:00:00Z');
      const streak = computeCurrentStreakDays([d1, d2], today);
      process.stdout.write('RESULT:' + JSON.stringify({ streak }));
    `);
    expect(result.streak).toBe(2);
  }, 60000);

  test('computeCurrentStreakDays — activity >1 day ago returns 0', () => {
    const result = runHelper(`
      const today = new Date('2025-05-10T14:00:00Z');
      const d1 = new Date('2025-05-07T10:00:00Z');
      const d2 = new Date('2025-05-06T10:00:00Z');
      const streak = computeCurrentStreakDays([d1, d2], today);
      process.stdout.write('RESULT:' + JSON.stringify({ streak }));
    `);
    expect(result.streak).toBe(0);
  }, 60000);

  test('computeCurrentStreakDays — duplicate same-day activities collapse', () => {
    const result = runHelper(`
      const today = new Date('2025-05-10T14:00:00Z');
      const a = new Date('2025-05-10T08:00:00Z');
      const b = new Date('2025-05-10T12:00:00Z');
      const c = new Date('2025-05-10T18:00:00Z');
      const streak = computeCurrentStreakDays([a, b, c], today);
      process.stdout.write('RESULT:' + JSON.stringify({ streak }));
    `);
    expect(result.streak).toBe(1);
  }, 60000);
});
