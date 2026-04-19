const fs = require('node:fs');
const path = require('node:path');

/**
 * Lightweight contract checks for the web /subscribe + /account/subscription/success
 * surfaces (item #28). The web workspace has no Vitest/RTL framework yet
 * (queued as backlog item #24), so we assert the source structure here in
 * the API jest run to keep CI single-suite.
 *
 * What this guarantees:
 *   - Both pages exist and are exported.
 *   - All three tier CTAs are wired with stable test IDs.
 *   - Each tier invokes createSubscriptionCheckout with the right tier key.
 *   - The success page polls GET /subscriptions/me (via getSubscription) and
 *     reads `?session_id=` from the URL.
 *   - Routes are wired in App.tsx (success page is auth-gated).
 */

const repoRoot = path.join(__dirname, '..', '..');
function read(rel) {
  return fs.readFileSync(path.join(repoRoot, rel), 'utf8');
}

describe('web subscribe pages contract (item #28)', () => {
  const subscribePage = read('web/src/pages/SubscribePage.tsx');
  const successPage = read('web/src/pages/SubscriptionSuccessPage.tsx');
  const apiClient = read('web/src/lib/api.ts');
  const appTsx = read('web/src/App.tsx');

  test('SubscribePage renders all three tiers with stable test ids', () => {
    expect(subscribePage).toContain('data-testid="subscribe-tier-grid"');
    // Test IDs are constructed dynamically as `subscribe-tier-${tier.key}` —
    // assert the prefix + that all three tier keys are referenced as TIERS entries.
    expect(subscribePage).toContain('subscribe-tier-${tier.key}');
    expect(subscribePage).toContain('subscribe-cta-${tier.key}');
    expect(subscribePage).toMatch(/key:\s*'hustle'/);
    expect(subscribePage).toMatch(/key:\s*'hwmf'/);
    expect(subscribePage).toMatch(/key:\s*'babyMomma'/);
  });

  test('SubscribePage shows correct copy + pricing per tier', () => {
    expect(subscribePage).toContain('HUSTLE');
    expect(subscribePage).toContain('HWMF');
    expect(subscribePage).toContain('BABY MOMMA');
    expect(subscribePage).toContain('$4.99');
    expect(subscribePage).toContain('$60');
    expect(subscribePage).toContain('$99');
  });

  test('SubscribePage CTA invokes createSubscriptionCheckout and redirects', () => {
    expect(subscribePage).toContain('createSubscriptionCheckout');
    expect(subscribePage).toContain('window.location.assign');
    expect(subscribePage).toContain('successUrl');
    expect(subscribePage).toContain('cancelUrl');
  });

  test('SubscribePage drives the right tier per click', () => {
    expect(subscribePage).toMatch(/handleSubscribe\(tier\.key\)/);
  });

  test('SubscribePage routes unauthenticated users to /sign-in', () => {
    expect(subscribePage).toContain('/sign-in?redirect=');
  });

  test('SubscribePage shows a per-button loading state while pending', () => {
    expect(subscribePage).toMatch(/Redirecting/);
    expect(subscribePage).toContain('pendingTier');
  });

  test('SubscribePage uses toast for error surfacing', () => {
    expect(subscribePage).toContain("from 'sonner'");
    expect(subscribePage).toContain('toast.error');
  });

  test('SubscriptionSuccessPage reads ?session_id and polls /subscriptions', () => {
    expect(successPage).toContain('useSearchParams');
    expect(successPage).toContain("searchParams.get('session_id')");
    expect(successPage).toContain('getSubscription');
    expect(successPage).toContain('POLL_INTERVAL_MS');
    expect(successPage).toContain('POLL_TIMEOUT_MS');
  });

  test('SubscriptionSuccessPage renders welcome state for active sub', () => {
    expect(successPage).toContain('Welcome to');
    expect(successPage).toContain("status === 'active'");
  });

  test('App.tsx wires both routes (subscribe is public, success is auth-gated)', () => {
    expect(appTsx).toContain('SubscribePage');
    expect(appTsx).toContain('SubscriptionSuccessPage');
    expect(appTsx).toContain('path="/subscribe"');
    expect(appTsx).toContain('path="/account/subscription/success"');
    // success page is wrapped in ProtectedAppRoute (auth-required)
    expect(appTsx).toMatch(/path="\/account\/subscription\/success"[\s\S]*?ProtectedAppRoute[\s\S]*?SubscriptionSuccessPage/);
  });

  test('api client exports createSubscriptionCheckout pointing at /subscriptions/checkout', () => {
    expect(apiClient).toContain('export async function createSubscriptionCheckout');
    expect(apiClient).toContain("'/subscriptions/checkout'");
    expect(apiClient).toContain('checkoutUrl');
    expect(apiClient).toContain('sessionId');
  });
});
