const fs = require('node:fs');
const path = require('node:path');

const apiRoot = path.join(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

/**
 * Backlog item #20 — /metrics/trends contract.
 *
 * Static regression sweep so future refactors can't accidentally delete the
 * route, change the auth posture, or strip the aggregation model imports.
 */
describe('metrics trends contract (item #20)', () => {
  const metricsRoutes = read('src/modules/metrics/routes.ts');
  const routesIndex = read('src/routes/index.ts');

  test('metrics module is mounted on the v1 router', () => {
    expect(routesIndex).toContain("import metricsRoutes from '../modules/metrics/routes.js';");
    expect(routesIndex).toContain("router.use('/metrics', metricsRoutes);");
  });

  test('trends route is authenticated and aggregates Workout/Run/Meal/HealthMetric', () => {
    expect(metricsRoutes).toContain("router.get('/trends', isAuthenticated");
    expect(metricsRoutes).toContain("import { Workout } from '../../models/Workout.js';");
    expect(metricsRoutes).toContain("import { Run } from '../../models/Run.js';");
    expect(metricsRoutes).toContain("import { Meal } from '../../models/Meal.js';");
    expect(metricsRoutes).toContain("import { HealthMetric } from '../../models/HealthMetric.js';");
  });

  test('range validator rejects anything outside week/month/year', () => {
    expect(metricsRoutes).toContain("SUPPORTED_RANGES");
    expect(metricsRoutes).toContain("'week'");
    expect(metricsRoutes).toContain("'month'");
    expect(metricsRoutes).toContain("'year'");
    expect(metricsRoutes).toContain('range must be one of');
  });

  test('pure helpers are exported for unit testing', () => {
    expect(metricsRoutes).toContain('export function buildBucketPlan');
    expect(metricsRoutes).toContain('export function resolveBucketStart');
    expect(metricsRoutes).toContain('export function composeBuckets');
    expect(metricsRoutes).toContain('export function buildSummary');
    expect(metricsRoutes).toContain('export function sanitizeTimezone');
    expect(metricsRoutes).toContain('export function normalizeWeightKg');
  });
});
