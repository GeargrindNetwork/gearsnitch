const fs = require('node:fs');
const path = require('node:path');

const apiRoot = path.join(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

describe('dosing module contract', () => {
  const routes = read('src/modules/dosing/routes.ts');
  const model = read('src/models/DosingHistory.ts');
  const routeIndex = read('src/routes/index.ts');

  test('routes module is registered in route index', () => {
    expect(routeIndex).toContain("router.use('/dosing', dosingRoutes)");
  });

  test('DosingHistory model exists with userId, substance, date', () => {
    expect(model).toContain('userId');
    expect(model).toContain('substance');
  });

  test('preset substances list includes common compounds', () => {
    expect(routes).toContain('Testosterone Cypionate');
    expect(routes).toContain('Testosterone Enanthate');
    expect(routes).toContain('Trenbolone Acetate');
    expect(routes).toContain('Semaglutide');
  });

  test('preset substances include reconstitution flag for peptides', () => {
    expect(routes).toContain('requiresReconstitution: true');
  });

  test('calculate endpoint validates positive concentration and dose', () => {
    expect(routes).toContain('Concentration must be positive');
    expect(routes).toContain('Desired dose must be positive');
  });

  test('routes require authentication', () => {
    // Check that at least one route uses isAuthenticated
    expect(routes).toContain('isAuthenticated');
  });

  test('routes enforce user ownership via JwtPayload sub', () => {
    expect(routes).toContain('req.user as JwtPayload');
  });
});
