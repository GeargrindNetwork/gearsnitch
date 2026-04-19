const { execFileSync } = require('node:child_process');
const path = require('node:path');

/**
 * Runtime test for the Stripe subscription webhook pipeline.
 *
 * Exercises PaymentService.handleWebhookEvent against mongodb-memory-server
 * with synthetic Stripe.Event payloads (no real Stripe API / signature calls).
 * Each scenario asserts the resulting Mongo state transition.
 */

function runScenario(body) {
  const apiRoot = path.join(__dirname, '..');
  const script = `
    process.env.NODE_ENV = 'test';
    process.env.STRIPE_SECRET_KEY = 'sk_test_dummy';
    process.env.STRIPE_WEBHOOK_SECRET = 'whsec_dummy';
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

describe('Stripe subscription webhook pipeline', () => {
  test('customer.subscription.created upserts an active Mongo Subscription', () => {
    const output = runScenario(`
      const { PaymentService } = require('./src/services/PaymentService.ts');
      const { Subscription } = require('./src/models/Subscription.ts');
      const { User } = require('./src/models/User.ts');

      const user = await User.create({
        email: 'alice@example.com',
        emailHash: 'hash-alice',
        displayName: 'Alice',
        stripeCustomerId: 'cus_test_alice',
      });

      const service = new PaymentService();
      const event = {
        id: 'evt_created_1',
        type: 'customer.subscription.created',
        data: {
          object: {
            id: 'sub_alice_1',
            customer: 'cus_test_alice',
            status: 'active',
            cancel_at_period_end: false,
            start_date: 1700000000,
            current_period_start: 1700000000,
            current_period_end: 1702592000,
            metadata: {},
            items: {
              data: [{ price: { id: 'price_hustle', product: 'prod_hustle' } }],
            },
          },
        },
      };

      await service.handleWebhookEvent(event);

      const sub = await Subscription.findOne({ stripeSubscriptionId: 'sub_alice_1' }).lean();
      if (!sub) throw new Error('Subscription not created');
      if (sub.status !== 'active') throw new Error('status should be active, got ' + sub.status);
      if (sub.provider !== 'stripe') throw new Error('provider should be stripe');
      if (sub.autoRenew !== true) throw new Error('autoRenew should be true');
      if (sub.userId.toString() !== user._id.toString()) throw new Error('userId mismatch');
      if (sub.productId !== 'prod_hustle') throw new Error('productId should be prod_hustle, got ' + sub.productId);
      if (sub.expiryDate.getTime() !== 1702592000 * 1000) throw new Error('expiryDate mismatch');

      console.log('created-ok');
    `);
    expect(output).toContain('created-ok');
  }, 60000);

  test('customer.subscription.updated with cancel_at_period_end flips autoRenew to false', () => {
    const output = runScenario(`
      const { PaymentService } = require('./src/services/PaymentService.ts');
      const { Subscription } = require('./src/models/Subscription.ts');
      const { User } = require('./src/models/User.ts');

      const user = await User.create({
        email: 'bob@example.com',
        emailHash: 'hash-bob',
        displayName: 'Bob',
        stripeCustomerId: 'cus_test_bob',
      });

      await Subscription.create({
        userId: user._id,
        provider: 'stripe',
        providerOriginalTransactionId: 'sub_bob_1',
        stripeSubscriptionId: 'sub_bob_1',
        stripeCustomerId: 'cus_test_bob',
        productId: 'prod_hustle',
        status: 'active',
        autoRenew: true,
        purchaseDate: new Date(1700000000 * 1000),
        expiryDate: new Date(1702592000 * 1000),
        lastValidatedAt: new Date(),
      });

      const service = new PaymentService();
      const event = {
        id: 'evt_upd_1',
        type: 'customer.subscription.updated',
        data: {
          object: {
            id: 'sub_bob_1',
            customer: 'cus_test_bob',
            status: 'active',
            cancel_at_period_end: true,
            current_period_start: 1700000000,
            current_period_end: 1702592000,
            metadata: {},
            items: { data: [{ price: { id: 'price_hustle', product: 'prod_hustle' } }] },
          },
        },
      };

      await service.handleWebhookEvent(event);

      const sub = await Subscription.findOne({ stripeSubscriptionId: 'sub_bob_1' }).lean();
      if (!sub) throw new Error('Subscription missing');
      if (sub.autoRenew !== false) throw new Error('autoRenew should be false after cancel_at_period_end');
      if (sub.status !== 'active') throw new Error('status should still be active, got ' + sub.status);

      console.log('updated-cancel-at-period-end-ok');
    `);
    expect(output).toContain('updated-cancel-at-period-end-ok');
  }, 60000);

  test('customer.subscription.updated active -> past_due transitions status', () => {
    const output = runScenario(`
      const { PaymentService } = require('./src/services/PaymentService.ts');
      const { Subscription } = require('./src/models/Subscription.ts');
      const { User } = require('./src/models/User.ts');

      const user = await User.create({
        email: 'carol@example.com',
        emailHash: 'hash-carol',
        displayName: 'Carol',
        stripeCustomerId: 'cus_test_carol',
      });

      await Subscription.create({
        userId: user._id,
        provider: 'stripe',
        providerOriginalTransactionId: 'sub_carol_1',
        stripeSubscriptionId: 'sub_carol_1',
        stripeCustomerId: 'cus_test_carol',
        productId: 'prod_hustle',
        status: 'active',
        autoRenew: true,
        purchaseDate: new Date(1700000000 * 1000),
        expiryDate: new Date(1702592000 * 1000),
        lastValidatedAt: new Date(),
      });

      const service = new PaymentService();
      await service.handleWebhookEvent({
        id: 'evt_pastdue_1',
        type: 'customer.subscription.updated',
        data: {
          object: {
            id: 'sub_carol_1',
            customer: 'cus_test_carol',
            status: 'past_due',
            cancel_at_period_end: false,
            current_period_start: 1700000000,
            current_period_end: 1702592000,
            metadata: {},
            items: { data: [{ price: { id: 'price_hustle', product: 'prod_hustle' } }] },
          },
        },
      });

      const sub = await Subscription.findOne({ stripeSubscriptionId: 'sub_carol_1' }).lean();
      if (sub.status !== 'past_due') throw new Error('status should be past_due, got ' + sub.status);

      console.log('updated-past-due-ok');
    `);
    expect(output).toContain('updated-past-due-ok');
  }, 60000);

  test('customer.subscription.deleted finalises status=cancelled + cancelledAt', () => {
    const output = runScenario(`
      const { PaymentService } = require('./src/services/PaymentService.ts');
      const { Subscription } = require('./src/models/Subscription.ts');
      const { User } = require('./src/models/User.ts');

      const user = await User.create({
        email: 'dave@example.com',
        emailHash: 'hash-dave',
        displayName: 'Dave',
        stripeCustomerId: 'cus_test_dave',
      });

      await Subscription.create({
        userId: user._id,
        provider: 'stripe',
        providerOriginalTransactionId: 'sub_dave_1',
        stripeSubscriptionId: 'sub_dave_1',
        stripeCustomerId: 'cus_test_dave',
        productId: 'prod_hustle',
        status: 'active',
        autoRenew: true,
        purchaseDate: new Date(1700000000 * 1000),
        expiryDate: new Date(1702592000 * 1000),
        lastValidatedAt: new Date(),
      });

      const service = new PaymentService();
      await service.handleWebhookEvent({
        id: 'evt_del_1',
        type: 'customer.subscription.deleted',
        data: {
          object: {
            id: 'sub_dave_1',
            customer: 'cus_test_dave',
            status: 'canceled',
            cancel_at_period_end: false,
            metadata: {},
            items: { data: [{ price: { id: 'price_hustle', product: 'prod_hustle' } }] },
          },
        },
      });

      const sub = await Subscription.findOne({ stripeSubscriptionId: 'sub_dave_1' }).lean();
      if (sub.status !== 'cancelled') throw new Error('status should be cancelled');
      if (sub.autoRenew !== false) throw new Error('autoRenew should be false');
      if (!sub.cancelledAt) throw new Error('cancelledAt should be set');

      console.log('deleted-ok');
    `);
    expect(output).toContain('deleted-ok');
  }, 60000);

  test('invoice.paid bumps expiryDate to new period_end', () => {
    const output = runScenario(`
      const { PaymentService } = require('./src/services/PaymentService.ts');
      const { Subscription } = require('./src/models/Subscription.ts');
      const { User } = require('./src/models/User.ts');

      const user = await User.create({
        email: 'erin@example.com',
        emailHash: 'hash-erin',
        displayName: 'Erin',
        stripeCustomerId: 'cus_test_erin',
      });

      await Subscription.create({
        userId: user._id,
        provider: 'stripe',
        providerOriginalTransactionId: 'sub_erin_1',
        stripeSubscriptionId: 'sub_erin_1',
        productId: 'prod_hustle',
        status: 'past_due',
        autoRenew: true,
        purchaseDate: new Date(1700000000 * 1000),
        expiryDate: new Date(1702592000 * 1000),
        lastValidatedAt: new Date(),
      });

      const service = new PaymentService();
      const newPeriodEnd = 1705184000; // later than the stored expiry
      await service.handleWebhookEvent({
        id: 'evt_inv_paid_1',
        type: 'invoice.paid',
        data: {
          object: {
            id: 'in_1',
            subscription: 'sub_erin_1',
            customer: 'cus_test_erin',
            period_start: 1702592000,
            period_end: newPeriodEnd,
            lines: {
              data: [{ period: { start: 1702592000, end: newPeriodEnd } }],
            },
          },
        },
      });

      const sub = await Subscription.findOne({ stripeSubscriptionId: 'sub_erin_1' }).lean();
      if (sub.status !== 'active') throw new Error('status should be active after invoice.paid, got ' + sub.status);
      if (sub.expiryDate.getTime() !== newPeriodEnd * 1000) {
        throw new Error('expiryDate should bump to new period_end, got ' + sub.expiryDate.toISOString());
      }

      console.log('invoice-paid-ok');
    `);
    expect(output).toContain('invoice-paid-ok');
  }, 60000);

  test('invoice.payment_succeeded aliases invoice.paid behavior', () => {
    const output = runScenario(`
      const { PaymentService } = require('./src/services/PaymentService.ts');
      const { Subscription } = require('./src/models/Subscription.ts');
      const { User } = require('./src/models/User.ts');

      const user = await User.create({
        email: 'frank@example.com',
        emailHash: 'hash-frank',
        displayName: 'Frank',
        stripeCustomerId: 'cus_test_frank',
      });

      await Subscription.create({
        userId: user._id,
        provider: 'stripe',
        providerOriginalTransactionId: 'sub_frank_1',
        stripeSubscriptionId: 'sub_frank_1',
        productId: 'prod_hustle',
        status: 'active',
        autoRenew: true,
        purchaseDate: new Date(1700000000 * 1000),
        expiryDate: new Date(1702592000 * 1000),
        lastValidatedAt: new Date(),
      });

      const service = new PaymentService();
      const newPeriodEnd = 1705184000;
      await service.handleWebhookEvent({
        id: 'evt_inv_succ_1',
        type: 'invoice.payment_succeeded',
        data: {
          object: {
            id: 'in_f1',
            subscription: 'sub_frank_1',
            customer: 'cus_test_frank',
            period_start: 1702592000,
            period_end: newPeriodEnd,
            lines: { data: [{ period: { start: 1702592000, end: newPeriodEnd } }] },
          },
        },
      });

      const sub = await Subscription.findOne({ stripeSubscriptionId: 'sub_frank_1' }).lean();
      if (sub.expiryDate.getTime() !== newPeriodEnd * 1000) {
        throw new Error('expiryDate should bump on payment_succeeded');
      }

      console.log('invoice-succeeded-ok');
    `);
    expect(output).toContain('invoice-succeeded-ok');
  }, 60000);

  test('invoice.payment_failed sets status=past_due', () => {
    const output = runScenario(`
      const { PaymentService } = require('./src/services/PaymentService.ts');
      const { Subscription } = require('./src/models/Subscription.ts');
      const { User } = require('./src/models/User.ts');

      const user = await User.create({
        email: 'gina@example.com',
        emailHash: 'hash-gina',
        displayName: 'Gina',
        stripeCustomerId: 'cus_test_gina',
      });

      await Subscription.create({
        userId: user._id,
        provider: 'stripe',
        providerOriginalTransactionId: 'sub_gina_1',
        stripeSubscriptionId: 'sub_gina_1',
        productId: 'prod_hustle',
        status: 'active',
        autoRenew: true,
        purchaseDate: new Date(1700000000 * 1000),
        expiryDate: new Date(1702592000 * 1000),
        lastValidatedAt: new Date(),
      });

      const service = new PaymentService();
      await service.handleWebhookEvent({
        id: 'evt_inv_fail_1',
        type: 'invoice.payment_failed',
        data: {
          object: {
            id: 'in_g1',
            subscription: 'sub_gina_1',
            customer: 'cus_test_gina',
            period_end: 1702592000,
            lines: { data: [] },
          },
        },
      });

      const sub = await Subscription.findOne({ stripeSubscriptionId: 'sub_gina_1' }).lean();
      if (sub.status !== 'past_due') throw new Error('status should be past_due, got ' + sub.status);

      console.log('invoice-failed-ok');
    `);
    expect(output).toContain('invoice-failed-ok');
  }, 60000);

  test('duplicate event.id is idempotent — state does not regress', () => {
    const output = runScenario(`
      const { PaymentService } = require('./src/services/PaymentService.ts');
      const { Subscription } = require('./src/models/Subscription.ts');
      const { ProcessedWebhookEvent } = require('./src/models/ProcessedWebhookEvent.ts');
      const { User } = require('./src/models/User.ts');

      const user = await User.create({
        email: 'henry@example.com',
        emailHash: 'hash-henry',
        displayName: 'Henry',
        stripeCustomerId: 'cus_test_henry',
      });

      const service = new PaymentService();

      const baseEvent = {
        id: 'evt_dup_1',
        type: 'customer.subscription.created',
        data: {
          object: {
            id: 'sub_henry_1',
            customer: 'cus_test_henry',
            status: 'active',
            cancel_at_period_end: false,
            start_date: 1700000000,
            current_period_start: 1700000000,
            current_period_end: 1702592000,
            metadata: {},
            items: { data: [{ price: { id: 'price_hustle', product: 'prod_hustle' } }] },
          },
        },
      };

      await service.handleWebhookEvent(baseEvent);

      // Mutate the event so the second delivery would re-upsert with different data IF processed.
      const duplicate = JSON.parse(JSON.stringify(baseEvent));
      duplicate.data.object.status = 'canceled';
      duplicate.data.object.cancel_at_period_end = true;
      await service.handleWebhookEvent(duplicate);

      const sub = await Subscription.findOne({ stripeSubscriptionId: 'sub_henry_1' }).lean();
      if (sub.status !== 'active') throw new Error('Duplicate should be ignored — status should remain active, got ' + sub.status);
      if (sub.autoRenew !== true) throw new Error('Duplicate should be ignored — autoRenew should remain true');

      const count = await ProcessedWebhookEvent.countDocuments({ eventId: 'evt_dup_1' });
      if (count !== 1) throw new Error('ProcessedWebhookEvent should have exactly one record for evt_dup_1');

      console.log('duplicate-ok');
    `);
    expect(output).toContain('duplicate-ok');
  }, 60000);

  test('unknown event type is a no-op and does not throw', () => {
    const output = runScenario(`
      const { PaymentService } = require('./src/services/PaymentService.ts');

      const service = new PaymentService();
      await service.handleWebhookEvent({
        id: 'evt_unknown_1',
        type: 'invoice.wild_unhandled_event',
        data: { object: {} },
      });

      console.log('unknown-noop-ok');
    `);
    expect(output).toContain('unknown-noop-ok');
  }, 60000);

  test('subscription event for unknown user logs warning but does not throw', () => {
    const output = runScenario(`
      const { PaymentService } = require('./src/services/PaymentService.ts');
      const { Subscription } = require('./src/models/Subscription.ts');

      const service = new PaymentService();
      await service.handleWebhookEvent({
        id: 'evt_orphan_1',
        type: 'customer.subscription.created',
        data: {
          object: {
            id: 'sub_orphan_1',
            customer: 'cus_unknown',
            status: 'active',
            cancel_at_period_end: false,
            start_date: 1700000000,
            current_period_start: 1700000000,
            current_period_end: 1702592000,
            metadata: {},
            items: { data: [{ price: { id: 'price_hustle', product: 'prod_hustle' } }] },
          },
        },
      });

      const count = await Subscription.countDocuments({ stripeSubscriptionId: 'sub_orphan_1' });
      if (count !== 0) throw new Error('Should not create subscription for unknown customer');

      console.log('orphan-ok');
    `);
    expect(output).toContain('orphan-ok');
  }, 60000);

  test('metadata.userId fallback resolves user when stripeCustomerId not yet persisted', () => {
    const output = runScenario(`
      const { PaymentService } = require('./src/services/PaymentService.ts');
      const { Subscription } = require('./src/models/Subscription.ts');
      const { User } = require('./src/models/User.ts');

      // User has NO stripeCustomerId persisted (simulates pre-PR-35 state).
      const user = await User.create({
        email: 'iris@example.com',
        emailHash: 'hash-iris',
        displayName: 'Iris',
      });

      const service = new PaymentService();
      await service.handleWebhookEvent({
        id: 'evt_meta_1',
        type: 'customer.subscription.created',
        data: {
          object: {
            id: 'sub_iris_1',
            customer: 'cus_unlinked',
            status: 'active',
            cancel_at_period_end: false,
            start_date: 1700000000,
            current_period_start: 1700000000,
            current_period_end: 1702592000,
            metadata: { userId: user._id.toString() },
            items: { data: [{ price: { id: 'price_hustle', product: 'prod_hustle' } }] },
          },
        },
      });

      const sub = await Subscription.findOne({ stripeSubscriptionId: 'sub_iris_1' }).lean();
      if (!sub) throw new Error('Subscription should be created via metadata.userId fallback');
      if (sub.userId.toString() !== user._id.toString()) throw new Error('userId should match metadata fallback');

      console.log('metadata-fallback-ok');
    `);
    expect(output).toContain('metadata-fallback-ok');
  }, 60000);
});
