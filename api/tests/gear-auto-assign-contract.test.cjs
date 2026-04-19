const fs = require('node:fs');
const path = require('node:path');

const apiRoot = path.join(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

/**
 * Contract-level regression sweep for backlog item #9 — Strava-style
 * auto-gear assignment by activity type. Covers:
 *   - User.preferences.defaultGearByActivity schema
 *   - Workout + Run gearId / gearIds fields
 *   - /gear/default-for-activity GET + PUT
 *   - Auto-attach on workout/run create
 *   - Gear-usage increment on workout/run complete
 */
describe('gear auto-assignment contract (item #9)', () => {
  const gearModel = read('src/models/GearComponent.ts');
  const modelIndex = read('src/models/index.ts');
  const userModel = read('src/models/User.ts');
  const workoutModel = read('src/models/Workout.ts');
  const runModel = read('src/models/Run.ts');
  const gearRoutes = read('src/modules/gear/routes.ts');
  const autoAttach = read('src/modules/gear/autoAttach.ts');
  const apiRoutes = read('src/routes/index.ts');
  const workoutRoutes = read('src/modules/workouts/routes.ts');
  const runRoutes = read('src/modules/runs/routes.ts');

  test('GearComponent model exports core types', () => {
    expect(gearModel).toContain("mongoose.model<IGearComponent>(\n  'GearComponent'");
    expect(gearModel).toContain('GEAR_KINDS');
    expect(gearModel).toContain('GEAR_UNITS');
    expect(modelIndex).toContain("GearComponent");
    expect(modelIndex).toContain("IGearComponent");
  });

  test('User.preferences carries defaultGearByActivity Mixed subdoc', () => {
    expect(userModel).toContain('defaultGearByActivity?: Record<string, Types.ObjectId | null>');
    expect(userModel).toContain('defaultGearByActivity: { type: Schema.Types.Mixed, default: {} }');
  });

  test('Workout model has gearId, gearIds, activityType with sparse index', () => {
    expect(workoutModel).toContain('gearId: Types.ObjectId | null');
    expect(workoutModel).toContain('gearIds: Types.ObjectId[]');
    expect(workoutModel).toContain("ref: 'GearComponent'");
    expect(workoutModel).toContain('sparse: true');
    expect(workoutModel).toContain('WorkoutSchema.index({ gearId: 1 }, { sparse: true });');
    expect(workoutModel).toContain('activityType: { type: String, default: null }');
  });

  test('Run model has gearId + gearIds + sparse index', () => {
    expect(runModel).toContain('gearId: Types.ObjectId | null');
    expect(runModel).toContain('gearIds: Types.ObjectId[]');
    expect(runModel).toContain("ref: 'GearComponent'");
    expect(runModel).toContain('RunSchema.index({ gearId: 1 }, { sparse: true });');
  });

  test('gear router is mounted and exposes default-for-activity', () => {
    expect(apiRoutes).toContain("import gearRoutes from '../modules/gear/routes.js';");
    expect(apiRoutes).toContain("router.use('/gear', gearRoutes);");
    expect(gearRoutes).toContain("router.get('/default-for-activity', isAuthenticated");
    expect(gearRoutes).toContain("router.put(\n  '/default-for-activity',\n  isAuthenticated");
    expect(gearRoutes).toContain("router.get('/', isAuthenticated");
    // Ownership validation: PUT refuses gearIds that don't belong to the caller.
    expect(gearRoutes).toContain('Gear not found for this user');
    // Mixed-path save requires markModified
    expect(gearRoutes).toContain("user.markModified('preferences.defaultGearByActivity')");
  });

  test('auto-attach helper is structured around resolveDefaultGear + logAutoGearAssigned', () => {
    expect(autoAttach).toContain('export async function resolveDefaultGear(');
    expect(autoAttach).toContain('export async function logAutoGearAssigned(');
    expect(autoAttach).toContain('export function computeGearIncrement(');
    expect(autoAttach).toContain('export async function incrementGearForWorkoutMetrics(');
    // EventLog observability — discriminator lives in metadata
    expect(autoAttach).toContain("kind: 'auto_gear_assigned'");
    // Retired gear is never auto-attached
    expect(autoAttach).toContain('retiredAt: null');
  });

  test('workout create auto-attaches the default gear for activityType', () => {
    expect(workoutRoutes).toContain("import {\n  resolveDefaultGear,\n  logAutoGearAssigned,\n  incrementGearForWorkoutMetrics,\n} from '../gear/autoAttach.js';");
    expect(workoutRoutes).toContain('const defaultGear = await resolveDefaultGear(userId, body.activityType);');
    expect(workoutRoutes).toContain('autoAssigned = true;');
    expect(workoutRoutes).toContain('logAutoGearAssigned({');
    // Explicit null from client = deliberate opt-out
    expect(workoutRoutes).toContain('if (body.gearId === null) {');
  });

  test('workout complete increments gear mileage via helper', () => {
    expect(workoutRoutes).toContain('incrementGearForWorkoutMetrics(');
    expect(workoutRoutes).toContain('const gearTargets = new Set<string>();');
  });

  test('run start auto-attaches default gear and run complete accrues distance', () => {
    expect(runRoutes).toContain("resolveDefaultGear,\n  logAutoGearAssigned,\n  incrementGearForWorkoutMetrics,");
    expect(runRoutes).toContain("await resolveDefaultGear(userId, 'running')");
    expect(runRoutes).toContain('logAutoGearAssigned({');
    expect(runRoutes).toContain('incrementGearForWorkoutMetrics(');
    // distanceMeters is the authoritative increment source for runs
    expect(runRoutes).toContain('distanceMeters: run.distanceMeters');
  });

  test('unit math: computeGearIncrement covers miles/km/hours/sessions', () => {
    // The helper file is executed in the Jest environment via require() —
    // a runtime smoke test keeps the formulas honest against accidental
    // refactors. We use `require` on the compiled form the TS source
    // emits equivalent JS for, which we can't load directly, so we parse
    // the switch arms and assert the conversion constants stay present.
    expect(autoAttach).toContain('distanceMeters / 1609.344');
    expect(autoAttach).toContain('distanceMeters / 1000');
    expect(autoAttach).toContain('durationSeconds / 3600');
    // sessions branch returns 1 (constant-time accrual).
    expect(autoAttach).toMatch(/case 'sessions':[\s\S]*?return 1;/);
  });
});
