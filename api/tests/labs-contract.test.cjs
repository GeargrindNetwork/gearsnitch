const fs = require('node:fs');
const path = require('node:path');

const apiRoot = path.join(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

describe('labs module contract', () => {
  const labsRoutes = read('src/modules/labs/routes.ts');
  const routeIndex = read('src/routes/index.ts');

  test('labs routes are registered in the route index', () => {
    expect(routeIndex).toContain("import labsRoutes from '../modules/labs/routes.js'");
    expect(routeIndex).toContain("router.use('/labs', labsRoutes)");
  });

  test('labs module exposes product and schedule endpoints', () => {
    expect(labsRoutes).toContain("router.get('/product', isAuthenticated");
    expect(labsRoutes).toContain("router.post('/schedule', isAuthenticated");
  });

  test('labs module validates schedule body with zod schema', () => {
    expect(labsRoutes).toContain('scheduleLabSchema');
    expect(labsRoutes).toContain('validateBody(scheduleLabSchema)');
  });

  test('bloodwork product has correct id and price', () => {
    expect(labsRoutes).toContain("id: 'com.gearsnitch.app.bloodwork'");
    expect(labsRoutes).toContain('price: 69.99');
  });

  test('schedule handler validates productId', () => {
    expect(labsRoutes).toContain('BLOODWORK_PRODUCT.id');
    expect(labsRoutes).toContain('Invalid product');
  });

  test('schedule handler returns confirmed appointment', () => {
    expect(labsRoutes).toContain('appointmentId');
    expect(labsRoutes).toContain("status: 'confirmed'");
  });

  test('labs module requires authentication on all routes', () => {
    expect(labsRoutes).toContain("import { isAuthenticated");
    const routeLines = labsRoutes.split('\n').filter(line => line.match(/router\.(get|post)\(/));
    routeLines.forEach(line => {
      expect(line).toContain('isAuthenticated');
    });
  });
});
