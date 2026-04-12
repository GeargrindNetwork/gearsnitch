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

  test('subscription formatting and Apple validation accept all supported product identifiers', () => {
    expect(subscriptionService).toContain('const APPLE_PRODUCT_CONFIG: Record<string, AppleProductConfig> = {');
    expect(subscriptionService).toContain("'com.geargrind.gearsnitch.monthly'");
    expect(subscriptionService).toContain("'com.gearsnitch.app.monthly'");
    expect(subscriptionService).toContain("'com.geargrind.gearsnitch.annual'");
    expect(subscriptionService).toContain("'com.gearsnitch.app.annual'");
    expect(subscriptionService).toContain("'com.geargrind.gearsnitch.lifetime'");
    expect(subscriptionService).toContain("'com.gearsnitch.app.lifetime'");
    expect(userRoutes).toContain('getSubscriptionPlanFromProductId(productId)');
  });
});
