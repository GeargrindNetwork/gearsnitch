const { execFileSync } = require('node:child_process');
const path = require('node:path');

/**
 * Runtime behavioural tests for the Stripe Checkout web subscription flow
 * (item #28). Exercises:
 *   - createSubscriptionCheckoutSession produces correct Stripe params (with the
 *     stripe SDK stubbed via a factory injected on the module-local Proxy).
 *   - PaymentService.handleWebhookEvent with `checkout.session.completed`
 *     creates the local Subscription row in subscription mode AND payment
 *     (lifetime) mode.
 *   - Duplicate event.id is idempotent — second delivery is a no-op.
 */

function runScenario(body) {
  const apiRoot = path.join(__dirname, '..');
  const script = `
    process.env.NODE_ENV = 'test';
    process.env.STRIPE_SECRET_KEY = 'sk_test_dummy';
    process.env.STRIPE_WEBHOOK_SECRET = 'whsec_dummy';
    process.env.STRIPE_PRICE_HUSTLE = 'price_hustle_test';
    process.env.STRIPE_PRICE_HWMF = 'price_hwmf_test';
    process.env.STRIPE_PRICE_BABY_MOMMA = 'price_baby_test';
    process.env.LOG_DIR = require('node:os').tmpdir();

    const mongoose = require('mongoose');
    const { MongoMemoryServer } = require('mongodb-memory-server');

    (async () => {
      const mongoServer = await MongoMemoryServer.create();
      await mongoose.connect(mongoServer.getUri(), {
        serverSelectionTimeoutMS: 15000,
      });

      try {
        ${body}
      } finally {
        await mongoose.disconnect();
        await mongoServer.stop();
      }
    })().catch((err) => {
      console.error(err && err.stack ? err.stack : err);
      process.exit(1);
    });
  `;

  return execFileSync(process.execPath, ['-r', 'tsx/cjs', '-e', script], {
    cwd: apiRoot,
    encoding: 'utf8',
    stdio: 'pipe',
  });
}

describe('Stripe Checkout web subscription flow', () => {
  test('createSubscriptionCheckoutSession passes correct params to Stripe (subscription mode)', () => {
    const output = runScenario(`
      // Stub Stripe before requiring the service so the Proxy points at our fake.
      const Module = require('module');
      const origResolve = Module._resolveFilename;
      const origLoad = Module._load;
      const captured = [];
      const fakeStripe = function () {
        return {
          checkout: {
            sessions: {
              create: async (params) => {
                captured.push(params);
                return { id: 'cs_test_123', url: 'https://checkout.stripe.com/c/cs_test_123' };
              },
            },
          },
        };
      };
      Module._load = function (request, parent, isMain) {
        if (request === 'stripe') return fakeStripe;
        return origLoad.apply(this, arguments);
      };

      const { createSubscriptionCheckoutSession } =
        require('./src/modules/subscriptions/checkoutService.ts');
      const { User } = require('./src/models/User.ts');

      const user = await User.create({
        email: 'sub@example.com',
        emailHash: 'hash-sub',
        displayName: 'Sub Tester',
      });

      const result = await createSubscriptionCheckoutSession({
        userId: user._id.toString(),
        tier: 'hustle',
        successUrl: 'https://gearsnitch.com/account/subscription/success',
        cancelUrl: 'https://gearsnitch.com/subscribe',
      });

      if (result.checkoutUrl !== 'https://checkout.stripe.com/c/cs_test_123') {
        throw new Error('checkoutUrl mismatch: ' + result.checkoutUrl);
      }
      if (result.sessionId !== 'cs_test_123') throw new Error('sessionId mismatch');

      const params = captured[0];
      if (!params) throw new Error('no checkout params captured');
      if (params.mode !== 'subscription') throw new Error('mode should be subscription, got ' + params.mode);
      if (params.line_items[0].price !== 'price_hustle_test') throw new Error('price mismatch');
      if (params.client_reference_id !== user._id.toString()) throw new Error('client_reference_id mismatch');
      if (!params.success_url.includes('{CHECKOUT_SESSION_ID}')) throw new Error('success_url missing session placeholder');
      if (params.metadata.tier !== 'hustle') throw new Error('metadata.tier mismatch');
      if (params.metadata.userId !== user._id.toString()) throw new Error('metadata.userId mismatch');
      if (params.subscription_data.trial_period_days !== 7) throw new Error('trial_period_days should be 7');
      if (params.allow_promotion_codes !== true) throw new Error('allow_promotion_codes should be true');
      if (params.customer_email !== 'sub@example.com') throw new Error('customer_email should be set when no stripeCustomerId');

      console.log('checkout-session-created-ok');
    `);
    expect(output).toContain('checkout-session-created-ok');
  }, 60000);

  test('createSubscriptionCheckoutSession uses lifetime (payment) mode for babyMomma', () => {
    const output = runScenario(`
      const Module = require('module');
      const origLoad = Module._load;
      const captured = [];
      Module._load = function (request) {
        if (request === 'stripe') {
          return function () {
            return {
              checkout: {
                sessions: {
                  create: async (params) => {
                    captured.push(params);
                    return { id: 'cs_life', url: 'https://stripe/cs_life' };
                  },
                },
              },
            };
          };
        }
        return origLoad.apply(this, arguments);
      };

      const { createSubscriptionCheckoutSession } =
        require('./src/modules/subscriptions/checkoutService.ts');
      const { User } = require('./src/models/User.ts');

      const user = await User.create({
        email: 'life@example.com',
        emailHash: 'hash-life',
        displayName: 'Life Tester',
        stripeCustomerId: 'cus_life_existing',
      });

      await createSubscriptionCheckoutSession({
        userId: user._id.toString(),
        tier: 'babyMomma',
        successUrl: 'https://gearsnitch.com/account/subscription/success',
        cancelUrl: 'https://gearsnitch.com/subscribe',
      });

      const params = captured[0];
      if (params.mode !== 'payment') throw new Error('mode should be payment for lifetime');
      if (params.line_items[0].price !== 'price_baby_test') throw new Error('price mismatch');
      if (params.subscription_data) throw new Error('subscription_data should be absent for payment mode');
      if (params.customer !== 'cus_life_existing') throw new Error('should reuse stripeCustomerId');
      if (params.customer_email) throw new Error('customer_email should NOT be set when customer is provided');

      console.log('checkout-lifetime-ok');
    `);
    expect(output).toContain('checkout-lifetime-ok');
  }, 60000);

  test('checkout.session.completed (subscription mode) upserts an active Subscription', () => {
    const output = runScenario(`
      const { PaymentService } = require('./src/services/PaymentService.ts');
      const { Subscription } = require('./src/models/Subscription.ts');
      const { User } = require('./src/models/User.ts');

      const user = await User.create({
        email: 'check@example.com',
        emailHash: 'hash-check',
        displayName: 'Check',
      });

      const service = new PaymentService();
      await service.handleWebhookEvent({
        id: 'evt_cs_complete_1',
        type: 'checkout.session.completed',
        data: {
          object: {
            id: 'cs_complete_1',
            client_reference_id: user._id.toString(),
            customer: 'cus_check_1',
            subscription: 'sub_check_1',
            metadata: { tier: 'hustle', userId: user._id.toString() },
          },
        },
      });

      const sub = await Subscription.findOne({ stripeSubscriptionId: 'sub_check_1' }).lean();
      if (!sub) throw new Error('Subscription not created via checkout.session.completed');
      if (sub.status !== 'active') throw new Error('status should be active, got ' + sub.status);
      if (sub.provider !== 'stripe') throw new Error('provider should be stripe');
      if (sub.userId.toString() !== user._id.toString()) throw new Error('userId mismatch');
      if (sub.stripeCustomerId !== 'cus_check_1') throw new Error('stripeCustomerId mismatch');

      const refreshedUser = await User.findById(user._id).lean();
      if (refreshedUser.stripeCustomerId !== 'cus_check_1') {
        throw new Error('user.stripeCustomerId should be persisted');
      }

      console.log('checkout-subscription-completed-ok');
    `);
    expect(output).toContain('checkout-subscription-completed-ok');
  }, 60000);

  test('checkout.session.completed (payment mode / lifetime) upserts an active Subscription', () => {
    const output = runScenario(`
      const { PaymentService } = require('./src/services/PaymentService.ts');
      const { Subscription } = require('./src/models/Subscription.ts');
      const { User } = require('./src/models/User.ts');

      const user = await User.create({
        email: 'lifeact@example.com',
        emailHash: 'hash-lifeact',
        displayName: 'Lifeact',
      });

      const service = new PaymentService();
      await service.handleWebhookEvent({
        id: 'evt_cs_lifetime_1',
        type: 'checkout.session.completed',
        data: {
          object: {
            id: 'cs_lifetime_1',
            client_reference_id: user._id.toString(),
            customer: 'cus_lifeact_1',
            payment_intent: 'pi_lifeact_1',
            metadata: { tier: 'babyMomma', userId: user._id.toString() },
          },
        },
      });

      const sub = await Subscription.findOne({ providerOriginalTransactionId: 'pi_lifeact_1' }).lean();
      if (!sub) throw new Error('Lifetime subscription not created');
      if (sub.status !== 'active') throw new Error('status should be active');
      if (sub.autoRenew !== false) throw new Error('autoRenew should be false for lifetime');
      if (sub.expiryDate.getUTCFullYear() < 2099) throw new Error('expiryDate should be far-future, got ' + sub.expiryDate.toISOString());

      console.log('checkout-lifetime-completed-ok');
    `);
    expect(output).toContain('checkout-lifetime-completed-ok');
  }, 60000);

  test('duplicate checkout.session.completed delivery is idempotent', () => {
    const output = runScenario(`
      const { PaymentService } = require('./src/services/PaymentService.ts');
      const { Subscription } = require('./src/models/Subscription.ts');
      const { ProcessedWebhookEvent } = require('./src/models/ProcessedWebhookEvent.ts');
      const { User } = require('./src/models/User.ts');

      const user = await User.create({
        email: 'dup@example.com',
        emailHash: 'hash-dup',
        displayName: 'Dup',
      });

      const baseEvent = {
        id: 'evt_cs_dup_1',
        type: 'checkout.session.completed',
        data: {
          object: {
            id: 'cs_dup_1',
            client_reference_id: user._id.toString(),
            customer: 'cus_dup',
            subscription: 'sub_dup_1',
            metadata: { tier: 'hwmf', userId: user._id.toString() },
          },
        },
      };

      const service = new PaymentService();
      await service.handleWebhookEvent(baseEvent);
      // Second delivery — should be a no-op (idempotent).
      await service.handleWebhookEvent(JSON.parse(JSON.stringify(baseEvent)));

      const subs = await Subscription.find({ stripeSubscriptionId: 'sub_dup_1' }).lean();
      if (subs.length !== 1) throw new Error('expected exactly 1 subscription row, got ' + subs.length);

      const eventCount = await ProcessedWebhookEvent.countDocuments({ eventId: 'evt_cs_dup_1' });
      if (eventCount !== 1) throw new Error('ProcessedWebhookEvent should track exactly 1 row');

      console.log('checkout-idempotent-ok');
    `);
    expect(output).toContain('checkout-idempotent-ok');
  }, 60000);
});
