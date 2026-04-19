const fs = require('node:fs');
const path = require('node:path');

const apiRoot = path.join(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

/**
 * Item #27 — workout/run completion summary push.
 *
 * Source-level contract: the trigger lives in the API workout/run complete
 * endpoints, uses the existing PR #48 enqueue helper, gracefully no-ops on
 * the documented skip cases, and never fails the user's completion request
 * if push enqueue blows up. The runtime test in
 * `workout-summary-push-runtime.test.cjs` exercises the actual enqueue
 * payload against an in-memory Mongo.
 */

describe('workout summary push contract (item #27)', () => {
  const userModel = read('src/models/User.ts');
  const userRoutes = read('src/modules/users/routes.ts');
  const workoutRoutes = read('src/modules/workouts/routes.ts');
  const runRoutes = read('src/modules/runs/routes.ts');

  test('User.preferences gains the workoutSummaryPushDisabled opt-out', () => {
    expect(userModel).toContain('workoutSummaryPushDisabled');
    // Default false ⇒ push is ON for all existing users on first deploy.
    expect(userModel).toMatch(
      /workoutSummaryPushDisabled:\s*\{[^}]*default:\s*false/,
    );
  });

  test('PATCH /users/me accepts the new top-level boolean preference', () => {
    expect(userRoutes).toContain('workoutSummaryPushDisabled: z.boolean().optional()');
    expect(userRoutes).toContain('workoutSummaryPushDisabled:');
  });

  test('PATCH /users/me preserves existing structured prefs on partial update', () => {
    // The merge needs to fall back to the existing value when the body
    // omits the field, otherwise a single-field PATCH would clobber it.
    expect(userRoutes).toContain('existingPreferences.workoutSummaryPushDisabled');
  });

  test('workout complete endpoint enqueues a workout_summary push', () => {
    expect(workoutRoutes).toContain("from '../../services/pushNotificationQueue.js'");
    expect(workoutRoutes).toContain('enqueuePushNotification');
    expect(workoutRoutes).toContain("type: 'workout_summary'");
    expect(workoutRoutes).toContain("'Nice work!'");
    expect(workoutRoutes).toContain('dedupeKey: `workout-summary:');
  });

  test('workout complete endpoint only fires on the first completion', () => {
    expect(workoutRoutes).toContain('wasAlreadyCompleted');
  });

  test('workout summary skip cases match the spec', () => {
    expect(workoutRoutes).toContain("return 'push_disabled'");
    expect(workoutRoutes).toContain("return 'workout_summary_disabled'");
    expect(workoutRoutes).toContain("return 'manual_or_backfill'");
    expect(workoutRoutes).toContain("return 'too_short'");
    expect(workoutRoutes).toContain("return 'no_metrics'");
  });

  test('workout push enqueue is best-effort (catches and logs, never throws)', () => {
    expect(workoutRoutes).toContain('Workout summary push enqueue failed (non-fatal)');
  });

  test('run complete endpoint enqueues a run_summary push', () => {
    expect(runRoutes).toContain("from '../../services/pushNotificationQueue.js'");
    expect(runRoutes).toContain('enqueuePushNotification');
    expect(runRoutes).toContain("type: 'run_summary'");
    expect(runRoutes).toContain("'Run complete!'");
    expect(runRoutes).toContain('dedupeKey: `run-summary:');
  });

  test('run summary skip cases match the spec', () => {
    expect(runRoutes).toContain("return 'push_disabled'");
    expect(runRoutes).toContain("return 'workout_summary_disabled'");
    expect(runRoutes).toContain("return 'manual_or_backfill'");
    expect(runRoutes).toContain("return 'too_short'");
    expect(runRoutes).toContain("return 'no_metrics'");
  });

  test('run push enqueue is best-effort', () => {
    expect(runRoutes).toContain('Run summary push enqueue failed (non-fatal)');
  });

  test('routes do not modify the worker, the queue helper, or the APNs sender', () => {
    // Sanity guard rail — the spec is explicit that this PR uses the
    // existing wires as-is. If a future edit accidentally imports from
    // worker/ this test will still pass (TS path), but the alarm bells
    // here keep us honest about what the routes touch.
    expect(workoutRoutes).not.toContain('worker/');
    expect(workoutRoutes).not.toContain('apnsClient');
    expect(runRoutes).not.toContain('worker/');
    expect(runRoutes).not.toContain('apnsClient');
  });
});
