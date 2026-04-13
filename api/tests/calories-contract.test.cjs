const fs = require('node:fs');
const path = require('node:path');

const apiRoot = path.join(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

describe('calories contract regression sweep', () => {
  const caloriesRoutes = read('src/modules/calories/routes.ts');

  test('calories module exposes live summary, meal, water, and delete handlers', () => {
    expect(caloriesRoutes).toContain("import { Meal } from '../../models/Meal.js';");
    expect(caloriesRoutes).toContain("import { WaterLog } from '../../models/WaterLog.js';");
    expect(caloriesRoutes).toContain("import { NutritionGoal } from '../../models/NutritionGoal.js';");
    expect(caloriesRoutes).toContain("router.get('/daily', isAuthenticated");
    expect(caloriesRoutes).toContain("router.post('/meals', isAuthenticated");
    expect(caloriesRoutes).toContain("router.post('/water', isAuthenticated");
    expect(caloriesRoutes).toContain("router.delete('/:id', isAuthenticated");
    expect(caloriesRoutes).toContain('Meal.create({');
    expect(caloriesRoutes).toContain('WaterLog.create({');
    expect(caloriesRoutes).toContain('NutritionGoal.findOne({ userId: userObjectId }).lean()');
    expect(caloriesRoutes).toContain('Meal.findOneAndDelete({');
    expect(caloriesRoutes).not.toContain('not yet implemented');
  });
});
