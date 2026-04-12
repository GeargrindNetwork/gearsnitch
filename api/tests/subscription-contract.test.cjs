const fs = require('node:fs');
const path = require('node:path');

const apiRoot = path.join(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

describe('subscription contract regression sweep', () => {
  const subscriptionRoutes = read('src/modules/subscriptions/routes.ts');
  const subscriptionService = read('src/modules/subscriptions/subscriptionService.ts');
  const userRoutes = read('src/modules/users/routes.ts');

  test('subscription status is available on both canonical and legacy client paths', () => {
    expect(subscriptionRoutes).toContain("router.get('/', isAuthenticated, respondWithCurrentSubscription);");
    expect(subscriptionRoutes).toContain("router.get('/me', isAuthenticated, respondWithCurrentSubscription);");
  });

  test('annual plan formatting and Apple validation accept both known product identifiers', () => {
    expect(subscriptionService).toContain('const ANNUAL_PRODUCT_IDS = new Set([');
    expect(subscriptionService).toContain("'com.geargrind.gearsnitch.annual'");
    expect(subscriptionService).toContain("'com.gearsnitch.app.annual'");
    expect(userRoutes).toContain("productId === 'com.geargrind.gearsnitch.annual'");
    expect(userRoutes).toContain("productId === 'com.gearsnitch.app.annual'");
  });
});
