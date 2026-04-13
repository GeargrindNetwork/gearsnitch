const fs = require('node:fs');
const path = require('node:path');

const apiRoot = path.join(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

describe('mobile health and calories contract regressions', () => {
  const apiRoutes = read('src/routes/index.ts');
  const caloriesRoutes = read('src/modules/calories/routes.ts');
  const healthRoutes = read('src/modules/health/routes.ts');

  test('calories routes expose live daily summary, meal logging, and water logging handlers', () => {
    expect(caloriesRoutes).toContain("router.get('/daily'");
    expect(caloriesRoutes).toContain("router.post('/meals'");
    expect(caloriesRoutes).toContain("router.post('/water'");
    expect(caloriesRoutes).toContain('NutritionGoal.findOne({ userId })');
    expect(caloriesRoutes).toContain('Meal.find({ userId, date })');
    expect(caloriesRoutes).toContain('WaterLog.find({ userId, date })');
    expect(caloriesRoutes).not.toContain('not yet implemented');
  });

  test('health routes expose live sync handlers for both legacy and current client paths', () => {
    expect(apiRoutes).toContain("router.use('/health-data', healthRoutes);");
    expect(apiRoutes).toContain("router.use('/health', healthRoutes);");
    expect(healthRoutes).toContain("router.post('/sync'");
    expect(healthRoutes).toContain("router.post('/apple/sync'");
    expect(healthRoutes).toContain('HealthMetric.insertMany(');
    expect(healthRoutes).toContain("router.get('/metrics'");
    expect(healthRoutes).not.toContain('not yet implemented');
  });
});
