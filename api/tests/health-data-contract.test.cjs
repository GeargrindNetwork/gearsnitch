const fs = require('node:fs');
const path = require('node:path');

const apiRoot = path.join(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

describe('health-data contract regression sweep', () => {
  const apiRoutes = read('src/routes/index.ts');
  const healthRoutes = read('src/modules/health/routes.ts');

  test('health routes are mounted for both legacy health-data and active iOS health paths', () => {
    expect(apiRoutes).toContain("router.use('/health', healthRoutes);");
    expect(apiRoutes).toContain("router.use('/health-data', healthRoutes);");
  });

  test('health module exposes live sync, metrics, and history handlers', () => {
    expect(healthRoutes).toContain("import { HealthMetric } from '../../models/HealthMetric.js';");
    expect(healthRoutes).toContain("router.post('/sync', isAuthenticated");
    expect(healthRoutes).toContain("router.post('/apple/sync', isAuthenticated");
    expect(healthRoutes).toContain("router.get('/metrics', isAuthenticated");
    expect(healthRoutes).toContain("router.get('/history', isAuthenticated");
    expect(healthRoutes).toContain('HealthMetric.bulkWrite(');
    expect(healthRoutes).toContain('HealthMetric.aggregate([');
    expect(healthRoutes).toContain('HealthMetric.find(filter)');
    expect(healthRoutes).not.toContain('not yet implemented');
  });
});
