const fs = require('node:fs');
const path = require('node:path');

const apiRoot = path.join(__dirname, '..');
const repoRoot = path.join(apiRoot, '..');

function readFromApi(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

function readFromRepo(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

describe('integration gap closure regression sweep', () => {
  const alertRoutes = readFromApi('src/modules/alerts/routes.ts');
  const referralRoutes = readFromApi('src/modules/referrals/routes.ts');
  const userRoutes = readFromApi('src/modules/users/routes.ts');
  const supportRoutes = readFromApi('src/modules/support/routes.ts');
  const paymentRoutes = readFromApi('src/modules/store/paymentRoutes.ts');
  const storeRoutes = readFromApi('src/modules/store/routes.ts');
  const paymentService = readFromApi('src/services/PaymentService.ts');
  const webStorePage = readFromRepo('web/src/pages/StorePage.tsx');
  const webStripeCheckout = readFromRepo('web/src/components/checkout/StripeCheckout.tsx');
  const applePayManager = readFromRepo('client-ios/GearSnitch/Core/Payments/ApplePayManager.swift');
  const bleManager = readFromRepo('client-ios/GearSnitch/Core/BLE/BLEManager.swift');
  const workerAlertFanout = readFromRepo('worker/src/jobs/alertFanout.ts');

  test('alerts routes expose real list, disconnect, and acknowledge handlers', () => {
    expect(alertRoutes).toContain("router.get('/', isAuthenticated");
    expect(alertRoutes).toContain("router.post('/device-disconnected'");
    expect(alertRoutes).toContain("router.post('/:id/acknowledge'");
    expect(alertRoutes).toContain('Alert.create(');
    expect(alertRoutes).not.toContain('StatusCodes.NOT_IMPLEMENTED');
  });

  test('referrals routes expose live me and qr contracts', () => {
    expect(referralRoutes).toContain('ensureReferralCode(');
    expect(referralRoutes).toContain("router.get('/me'");
    expect(referralRoutes).toContain("router.get('/qr'");
    expect(referralRoutes).toContain('Referral.create(');
    expect(referralRoutes).not.toContain('StatusCodes.NOT_IMPLEMENTED');
  });

  test('users routes persist deletion requests and revoke sessions', () => {
    expect(userRoutes).toContain("router.delete('/me'");
    expect(userRoutes).toContain("user.status = 'deletion_requested'");
    expect(userRoutes).toContain('AuthService.logoutAll(');
  });

  test('support routes persist tickets instead of faking submission', () => {
    expect(supportRoutes).toContain("router.post('/tickets'");
    expect(supportRoutes).toContain('SupportTicket.create(');
    expect(supportRoutes).toContain("router.get('/tickets/:id'");
    expect(supportRoutes).not.toContain('StatusCodes.NOT_IMPLEMENTED');
  });

  test('store routes and payment service are cart-backed and finalizable', () => {
    expect(storeRoutes).toContain('successResponse(res, cart, StatusCodes.CREATED);');
    expect(paymentRoutes).toContain('const CreateIntentSchema');
    expect(paymentRoutes).toContain('const FinalizePaymentSchema');
    expect(paymentRoutes).toContain("'/finalize',");
    expect(paymentService).toContain('upsertPendingOrderFromCart');
    expect(paymentService).toContain('finalizeCardPayment(');
    expect(paymentService).toContain("paymentIntent.metadata.userId !== userIdOverride");
  });

  test('web store and checkout use live catalog, cart, and payment endpoints', () => {
    expect(webStorePage).toContain("api.get<StoreProduct[]>('/store/products')");
    expect(webStorePage).toContain("api.post<StoreCart>('/store/cart'");
    expect(webStorePage).toContain('<StripeCheckout');
    expect(webStripeCheckout).toContain("'/store/payments/create-intent'");
    expect(webStripeCheckout).toContain("'/store/payments/finalize'");
    expect(webStripeCheckout).toContain('cartId');
  });

  test('iOS Apple Pay and BLE timeout paths call the real helpers', () => {
    expect(applePayManager).toContain('paymentService.createPaymentIntent(');
    expect(applePayManager).toContain('pendingPaymentIntentId');
    expect(applePayManager).not.toContain('paymentIntentId: ""');
    expect(bleManager).toContain('triggerDisconnectHaptic()');
    expect(bleManager).toContain('postDisconnectAlert(for: device)');
    expect(bleManager).toContain('AppConfig.bleServiceUUIDs');
  });

  test('worker alert fanout treats device_disconnected like a first-class disconnect alert', () => {
    expect(workerAlertFanout).toContain("case 'device_disconnected':");
    expect(workerAlertFanout).toContain("type === 'disconnect_warning' || type === 'device_disconnected'");
  });
});
