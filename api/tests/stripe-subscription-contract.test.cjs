const fs = require('node:fs');
const path = require('node:path');

const apiRoot = path.join(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

describe('stripe subscription contract', () => {
  const routes = read('src/modules/subscriptions/routes.ts');

  test('POST /subscriptions endpoint exists and is authenticated', () => {
    expect(routes).toContain("router.post('/', isAuthenticated");
  });

  test('PATCH /subscriptions endpoint exists for tier upgrade', () => {
    expect(routes).toContain("router.patch('/', isAuthenticated");
  });

  test('DELETE /subscriptions endpoint exists for cancellation', () => {
    expect(routes).toContain("router.delete('/', isAuthenticated");
  });

  test('all 501 stubs have been removed', () => {
    expect(routes).not.toContain('not yet implemented');
  });

  test('Stripe price map includes all three tiers', () => {
    expect(routes).toContain("hustle:");
    expect(routes).toContain("hwmf:");
    expect(routes).toContain("babyMomma:");
  });

  test('HUSTLE tier is monthly at $4.99', () => {
    expect(routes).toMatch(/hustle:.*tier:\s*'monthly'.*price:\s*499/s);
  });

  test('HWMF tier is annual at $60', () => {
    expect(routes).toMatch(/hwmf:.*tier:\s*'annual'.*price:\s*6000/s);
  });

  test('BABY MOMMA tier is lifetime at $99', () => {
    expect(routes).toMatch(/babyMomma:.*tier:\s*'lifetime'.*price:\s*9900/s);
  });

  test('POST validates tier against price map', () => {
    // Validation now goes through the type-safe `isWebSubscriptionTier` guard
    // (see checkoutService.ts) — STRIPE_PRICE_MAP remains as the human-facing
    // tier-name reference but is no longer the validator key.
    expect(routes).toMatch(/isWebSubscriptionTier|STRIPE_PRICE_MAP\[tier\]/);
    expect(routes).toContain('Invalid tier');
  });

  test('PATCH requires existing active subscription to upgrade', () => {
    expect(routes).toContain('No active subscription to upgrade');
  });

  test('DELETE requires existing active subscription to cancel', () => {
    expect(routes).toContain('No active subscription to cancel');
  });
});
