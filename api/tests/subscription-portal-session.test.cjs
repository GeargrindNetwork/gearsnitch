const fs = require('node:fs');
const path = require('node:path');

const apiRoot = path.join(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

describe('POST /subscriptions/portal-session contract', () => {
  const routes = read('src/modules/subscriptions/routes.ts');
  const paymentService = read('src/services/PaymentService.ts');

  test('endpoint is registered at POST /portal-session', () => {
    expect(routes).toMatch(/router\.post\(\s*['"]\/portal-session['"]/);
  });

  test('endpoint is auth-guarded (isAuthenticated) so unauthenticated callers get 401', () => {
    // isAuthenticated is the shared middleware that emits 401 on missing/invalid JWT.
    expect(routes).toMatch(
      /router\.post\(\s*['"]\/portal-session['"]\s*,\s*isAuthenticated\s*,/,
    );
  });

  test('endpoint resolves Stripe customer via getOrCreateStripeCustomer fallback (no duplicate model logic)', () => {
    // Happy-path Stripe session creation MUST go through the PaymentService
    // helpers so all Stripe SDK access is centralized. No raw `new StripeLib`
    // should appear in the subscription routes file.
    expect(routes).toContain('paymentService.findStripeCustomerByEmail');
    expect(routes).toContain('paymentService.getOrCreateStripeCustomer');
    expect(routes).toContain('paymentService.createBillingPortalSession');
    expect(routes).not.toMatch(/new\s+StripeLib\s*\(/);
    // The raw `require('stripe')(...)` construction must not be used at module
    // scope — all Stripe SDK calls must funnel through PaymentService. A
    // commented-out TODO reference inside the legacy POST / handler is fine.
    const uncommented = routes
      .split('\n')
      .filter((line) => !line.trim().startsWith('//'))
      .join('\n');
    expect(uncommented).not.toMatch(/require\(\s*['"]stripe['"]\s*\)/);
  });

  test('happy path returns Stripe session URL to the client (200)', () => {
    // The route must forward the Billing Portal URL back as `{ url }` so the
    // web client can `window.location.href = url` to redirect into Stripe.
    expect(routes).toMatch(
      /successResponse\(\s*res\s*,\s*\{\s*url:\s*session\.url\s*\}\s*\)/,
    );
  });

  test('404 when user has neither a Stripe customer nor an active Stripe subscription', () => {
    expect(routes).toContain('StatusCodes.NOT_FOUND');
    expect(routes).toMatch(/Subscribe via iOS first/);
    // The existence gate must check BOTH (OR short-circuit allows legit
    // Stripe customers in; rejects only when both miss).
    expect(routes).toMatch(/!existingCustomerId\s*&&\s*!hasActiveStripeSub/);
  });

  test('Apple-platform subscriptions are not considered "Stripe history"', () => {
    // If the user's only sub is Apple-provider, the route must still 404.
    expect(routes).toMatch(/provider\s*!==\s*['"]apple['"]/);
  });

  test('default return_url points to /account on gearsnitch.com', () => {
    expect(routes).toContain("'https://gearsnitch.com/account'");
  });

  test('returnUrl from body is respected when provided as a string', () => {
    expect(routes).toMatch(/returnUrl\s*&&\s*typeof\s+returnUrl\s*===\s*['"]string['"]/);
  });

  test('PaymentService exposes a billing portal helper that wraps stripe.billingPortal.sessions.create', () => {
    expect(paymentService).toContain('createBillingPortalSession');
    expect(paymentService).toContain('stripe.billingPortal.sessions.create');
    expect(paymentService).toContain('return_url: returnUrl');
  });

  test('PaymentService exposes a lookup-only helper (no accidental customer creation for 404 path)', () => {
    expect(paymentService).toContain('findStripeCustomerByEmail');
    // The lookup-only helper must NOT call customers.create — that is what
    // lets the 404 branch stay truthful when no Stripe history exists.
    const lookupFnMatch = paymentService.match(
      /async\s+findStripeCustomerByEmail[\s\S]*?\n  \}/,
    );
    expect(lookupFnMatch).not.toBeNull();
    expect(lookupFnMatch[0]).not.toContain('customers.create');
  });

  test('hard constraint: DELETE /subscriptions is unchanged (A1 scope stays put)', () => {
    expect(routes).toContain("router.delete('/', isAuthenticated");
    expect(routes).toContain('No active subscription to cancel');
  });

  test('hard constraint: POST /subscriptions/validate-apple is unchanged (A2 scope stays put)', () => {
    expect(routes).toContain("router.post('/validate-apple', isAuthenticated");
    expect(routes).toContain('jwsRepresentation is required');
  });
});
