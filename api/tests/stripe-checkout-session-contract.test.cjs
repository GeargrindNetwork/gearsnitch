const fs = require('node:fs');
const path = require('node:path');

/**
 * Contract checks for the real Stripe Checkout Session integration (item #28).
 *
 * Mirrors the lightweight regression-sweep style used by
 * `subscription-contract.test.cjs` — verifies the source contains the
 * expected wiring without spinning up the full server. The behavioural
 * runtime tests live in `stripe-checkout-session-runtime.test.cjs`.
 */

const apiRoot = path.join(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

describe('stripe checkout session contract', () => {
  const routes = read('src/modules/subscriptions/routes.ts');
  const checkoutService = read('src/modules/subscriptions/checkoutService.ts');
  const dispatcher = read('src/modules/subscriptions/stripeSubscriptionWebhookService.ts');
  const app = read('src/app.ts');
  const config = read('src/config/index.ts');

  test('placeholder TODOs at the old POST/PATCH stub are gone', () => {
    expect(routes).not.toContain('Replace with actual Stripe Checkout session creation');
    expect(routes).not.toContain('Stripe Checkout integration pending');
    expect(routes).not.toContain('Stripe upgrade integration pending');
  });

  test('POST /subscriptions/checkout endpoint is mounted and authenticated', () => {
    expect(routes).toContain("router.post('/checkout', isAuthenticated, createCheckoutHandler)");
  });

  test('POST /subscriptions backward-compat alias still mounts the same handler', () => {
    expect(routes).toContain("router.post('/', isAuthenticated, createCheckoutHandler)");
  });

  test('PATCH /subscriptions reuses createSubscriptionCheckoutSession (real Stripe)', () => {
    expect(routes).toContain("router.patch('/', isAuthenticated");
    expect(routes).toContain('createSubscriptionCheckoutSession');
  });

  test('checkout handler validates tier against price map', () => {
    expect(routes).toContain('isWebSubscriptionTier');
    expect(routes).toContain('Invalid tier');
  });

  test('checkout handler requires successUrl and cancelUrl', () => {
    expect(routes).toContain('successUrl is required');
    expect(routes).toContain('cancelUrl is required');
  });

  test('checkoutService creates Stripe Checkout sessions with required fields', () => {
    expect(checkoutService).toContain('stripe.checkout.sessions.create');
    expect(checkoutService).toContain('client_reference_id: user._id.toString()');
    expect(checkoutService).toContain("metadata: {");
    expect(checkoutService).toContain('allow_promotion_codes: true');
  });

  test('checkoutService picks subscription mode for monthly+annual, payment for lifetime', () => {
    expect(checkoutService).toMatch(/hustle:[\s\S]*?mode:\s*'subscription'/);
    expect(checkoutService).toMatch(/hwmf:[\s\S]*?mode:\s*'subscription'/);
    expect(checkoutService).toMatch(/babyMomma:[\s\S]*?mode:\s*'payment'/);
  });

  test('subscription_data.trial_period_days is 7 for recurring tiers', () => {
    expect(checkoutService).toContain('trial_period_days: 7');
  });

  test('checkoutService injects {CHECKOUT_SESSION_ID} placeholder into success_url', () => {
    expect(checkoutService).toContain('{CHECKOUT_SESSION_ID}');
  });

  test('checkoutService prefers existing user.stripeCustomerId, falls back to customer_email', () => {
    expect(checkoutService).toContain('user.stripeCustomerId');
    expect(checkoutService).toMatch(/customer_email\s*=\s*user\.email|customer_email:\s*user\.email/);
  });

  test('webhook dispatcher handles checkout.session.completed', () => {
    expect(dispatcher).toContain("'checkout.session.completed'");
    expect(dispatcher).toContain('handleCheckoutSessionCompleted');
  });

  test('checkout.session.completed handler persists Subscription with correct provider', () => {
    expect(checkoutService).toContain("provider: 'stripe'");
    expect(checkoutService).toContain("status: 'active'");
    expect(checkoutService).toContain('handleCheckoutSessionCompleted');
  });

  test('checkout.session.completed handler persists stripeCustomerId on User', () => {
    expect(checkoutService).toContain('stripeCustomerId: customerId');
    expect(checkoutService).toContain('User.findByIdAndUpdate');
  });

  test('lifetime (payment-mode) branch uses far-future expiryDate sentinel', () => {
    expect(checkoutService).toContain('2099-12-31T23:59:59Z');
  });

  test('subscription-side webhook endpoint is mounted at /subscriptions/stripe/webhook', () => {
    expect(routes).toContain("router.post('/stripe/webhook'");
    expect(routes).toContain('paymentService.constructWebhookEvent');
  });

  test('app.ts mounts raw body parser for the new subscription webhook', () => {
    expect(app).toContain('/subscriptions/stripe/webhook');
    expect(app).toContain("express.raw({ type: 'application/json' })");
  });

  test('config exposes per-tier Stripe Price ID env vars', () => {
    expect(config).toContain('STRIPE_PRICE_HUSTLE');
    expect(config).toContain('STRIPE_PRICE_HWMF');
    expect(config).toContain('STRIPE_PRICE_BABY_MOMMA');
  });

  test('App Store policy guard: iOS client has no link to /subscribe', () => {
    // Search the iOS source tree for any /subscribe URL — App Store 3.1.1
    // forbids the binary from advertising external payment paths.
    function walk(dir) {
      const out = [];
      const entries = fs.readdirSync(dir, { withFileTypes: true });
      for (const entry of entries) {
        if (entry.name === 'build' || entry.name === 'DerivedData' || entry.name === 'Pods') continue;
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) {
          out.push(...walk(full));
        } else if (entry.isFile() && /\.(swift|m|mm|h|plist|json)$/.test(entry.name)) {
          out.push(full);
        }
      }
      return out;
    }
    const iosRoot = path.join(apiRoot, '..', 'client-ios');
    if (!fs.existsSync(iosRoot)) {
      return; // iOS sources not present in this checkout — skip.
    }
    const offenders = [];
    for (const file of walk(iosRoot)) {
      const body = fs.readFileSync(file, 'utf8');
      if (/gearsnitch\.com\/subscribe|"\/subscribe"|`\/subscribe`/.test(body)) {
        offenders.push(file);
      }
    }
    expect(offenders).toEqual([]);
  });
});
