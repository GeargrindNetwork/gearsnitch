const { execFileSync } = require('node:child_process');
const path = require('node:path');

const apiRoot = path.join(__dirname, '..');

/**
 * Runs a TS-aware script inside the api workspace with the `stripe` SDK
 * replaced by an in-memory mock. We do this by installing a Module.require
 * hook BEFORE requiring PaymentService, so when the service evaluates
 * `new StripeLib(...)` it gets our fake constructor.
 *
 * Each case exports its own tiny scenario that drives
 * PaymentService.getOrCreateStripeCustomer and then asserts against the
 * mock call log + the persisted user document.
 */
function runScenario(scenarioBody) {
  const script = `
    const Module = require('module');
    const originalResolve = Module._resolveFilename;

    // --- Stripe mock -----------------------------------------------------
    const calls = {
      retrieve: [],
      list: [],
      create: [],
    };
    let retrieveImpl = null;
    let listImpl = null;
    let createImpl = null;

    function setRetrieveImpl(fn) { retrieveImpl = fn; }
    function setListImpl(fn) { listImpl = fn; }
    function setCreateImpl(fn) { createImpl = fn; }

    class FakeStripe {
      constructor() {
        const self = this;
        this.customers = {
          async retrieve(id) {
            calls.retrieve.push(id);
            if (!retrieveImpl) {
              const err = new Error('No such customer: ' + id);
              err.code = 'resource_missing';
              throw err;
            }
            return retrieveImpl(id);
          },
          async list(params) {
            calls.list.push(params);
            if (!listImpl) {
              return { data: [] };
            }
            return listImpl(params);
          },
          async create(params) {
            calls.create.push(params);
            if (!createImpl) {
              return { id: 'cus_fake_' + Math.random().toString(36).slice(2, 8), metadata: params.metadata || {} };
            }
            return createImpl(params);
          },
        };
        this.paymentIntents = { create: async () => ({}), confirm: async () => ({}), retrieve: async () => ({}) };
        this.paymentMethods = { create: async () => ({}), list: async () => ({ data: [] }) };
        this.webhooks = { constructEvent: () => ({}) };
      }
    }
    // default-export interop: TS "import StripeLib from 'stripe'" compiles to
    // require('stripe').default when esModuleInterop is on, else the module
    // itself. We set both so either works.
    const stripeExport = FakeStripe;
    stripeExport.default = FakeStripe;
    stripeExport.Stripe = FakeStripe;

    const fakeStripeCore = { Stripe: FakeStripe };

    const originalRequire = Module.prototype.require;
    Module.prototype.require = function patchedRequire(id) {
      if (id === 'stripe') return stripeExport;
      if (id === 'stripe/cjs/stripe.core.js') return fakeStripeCore;
      return originalRequire.apply(this, arguments);
    };

    // --- Now pull in mongoose + the service under test -------------------
    const mongoose = require('mongoose');
    const { MongoMemoryServer } = require('mongodb-memory-server');
    const { PaymentService } = require('./src/services/PaymentService.ts');
    const { User } = require('./src/models/User.ts');

    (async () => {
      const mongoServer = await MongoMemoryServer.create();
      await mongoose.connect(mongoServer.getUri(), { serverSelectionTimeoutMS: 15000 });

      try {
        const ctx = {
          mongoose,
          User,
          PaymentService,
          service: new PaymentService(),
          calls,
          setRetrieveImpl,
          setListImpl,
          setCreateImpl,
          assert: (cond, msg) => { if (!cond) throw new Error('assertion failed: ' + msg); },
        };
        ${scenarioBody}
      } finally {
        await User.deleteMany({});
        await mongoose.disconnect();
        await mongoServer.stop();
      }
    })().catch((err) => {
      console.error(err && err.stack || err);
      process.exit(1);
    });
  `;

  return execFileSync(
    process.execPath,
    ['-r', 'tsx/cjs', '-e', script],
    {
      cwd: apiRoot,
      encoding: 'utf8',
      stdio: 'pipe',
    }
  );
}

describe('PaymentService.getOrCreateStripeCustomer', () => {
  test('creates new Stripe customer and persists id when user has none', () => {
    const output = runScenario(`
      ctx.setCreateImpl(async (params) => {
        return { id: 'cus_new_001', email: params.email, metadata: params.metadata };
      });

      const user = await ctx.User.create({
        email: 'alice@example.com',
        emailHash: 'hash-alice',
        displayName: 'Alice',
      });

      const customerId = await ctx.service.getOrCreateStripeCustomer(
        user._id.toString(),
        user.email,
      );

      ctx.assert(customerId === 'cus_new_001', 'returned id should be cus_new_001');
      ctx.assert(ctx.calls.retrieve.length === 0, 'should not retrieve without a persisted id');
      ctx.assert(ctx.calls.list.length === 1, 'should list by email for backfill once');
      ctx.assert(ctx.calls.create.length === 1, 'should create exactly one new customer');
      ctx.assert(ctx.calls.create[0].metadata.userId === user._id.toString(), 'create metadata must carry userId');

      const reloaded = await ctx.User.findById(user._id);
      ctx.assert(reloaded.stripeCustomerId === 'cus_new_001', 'stripeCustomerId must be persisted on user');
      console.log('scenario-create-new-ok');
    `);
    expect(output).toContain('scenario-create-new-ok');
  }, 30000);

  test('uses persisted stripeCustomerId and skips list/create', () => {
    const output = runScenario(`
      ctx.setRetrieveImpl(async (id) => ({ id, deleted: false, metadata: {} }));

      const user = await ctx.User.create({
        email: 'bob@example.com',
        emailHash: 'hash-bob',
        displayName: 'Bob',
        stripeCustomerId: 'cus_existing_bob',
      });

      const customerId = await ctx.service.getOrCreateStripeCustomer(
        user._id.toString(),
        user.email,
      );

      ctx.assert(customerId === 'cus_existing_bob', 'should return the persisted id');
      ctx.assert(ctx.calls.retrieve.length === 1, 'should retrieve exactly once');
      ctx.assert(ctx.calls.retrieve[0] === 'cus_existing_bob', 'retrieve should be called with the persisted id');
      ctx.assert(ctx.calls.list.length === 0, 'should NOT call customers.list when id is persisted');
      ctx.assert(ctx.calls.create.length === 0, 'should NOT call customers.create when id is persisted');
      console.log('scenario-retrieve-existing-ok');
    `);
    expect(output).toContain('scenario-retrieve-existing-ok');
  }, 30000);

  test('falls back to create when persisted id is missing in Stripe', () => {
    const output = runScenario(`
      ctx.setRetrieveImpl(async (id) => {
        const err = new Error('No such customer: ' + id);
        err.code = 'resource_missing';
        throw err;
      });
      ctx.setCreateImpl(async (params) => {
        return { id: 'cus_replacement_001', email: params.email, metadata: params.metadata };
      });

      const user = await ctx.User.create({
        email: 'carol@example.com',
        emailHash: 'hash-carol',
        displayName: 'Carol',
        stripeCustomerId: 'cus_stale_xyz',
      });

      const customerId = await ctx.service.getOrCreateStripeCustomer(
        user._id.toString(),
        user.email,
      );

      ctx.assert(customerId === 'cus_replacement_001', 'should return newly created id');
      ctx.assert(ctx.calls.retrieve.length === 1, 'retrieve was attempted once');
      ctx.assert(ctx.calls.create.length === 1, 'create called once after resource_missing');

      const reloaded = await ctx.User.findById(user._id);
      ctx.assert(
        reloaded.stripeCustomerId === 'cus_replacement_001',
        'stale id must be replaced with new one on user doc, got ' + reloaded.stripeCustomerId,
      );
      console.log('scenario-stale-id-recreate-ok');
    `);
    expect(output).toContain('scenario-stale-id-recreate-ok');
  }, 30000);

  test('backfills user.stripeCustomerId when Stripe already has a matching customer by metadata', () => {
    const output = runScenario(`
      const user = await ctx.User.create({
        email: 'dave@example.com',
        emailHash: 'hash-dave',
        displayName: 'Dave',
      });
      const expectedUserId = user._id.toString();

      ctx.setListImpl(async (params) => {
        ctx.assert(params.email === 'dave@example.com', 'list called with correct email');
        return {
          data: [
            { id: 'cus_preexisting_dave', email: params.email, metadata: { userId: expectedUserId } },
          ],
        };
      });

      const customerId = await ctx.service.getOrCreateStripeCustomer(
        expectedUserId,
        user.email,
      );

      ctx.assert(customerId === 'cus_preexisting_dave', 'should link to existing Stripe customer');
      ctx.assert(ctx.calls.retrieve.length === 0, 'no retrieve: user had no persisted id');
      ctx.assert(ctx.calls.list.length === 1, 'one list call for backfill');
      ctx.assert(ctx.calls.create.length === 0, 'must NOT create new customer when metadata matches');

      const reloaded = await ctx.User.findById(user._id);
      ctx.assert(reloaded.stripeCustomerId === 'cus_preexisting_dave', 'stripeCustomerId must be persisted from backfill');
      console.log('scenario-backfill-metadata-ok');
    `);
    expect(output).toContain('scenario-backfill-metadata-ok');
  }, 30000);

  test('ignores email-matched Stripe customer whose metadata.userId belongs to a different user', () => {
    // Safety check: the exact race the audit flagged.
    const output = runScenario(`
      ctx.setListImpl(async (params) => {
        return {
          data: [
            { id: 'cus_other_user', email: params.email, metadata: { userId: 'some-other-user-id' } },
          ],
        };
      });
      ctx.setCreateImpl(async (params) => {
        return { id: 'cus_fresh_for_eve', email: params.email, metadata: params.metadata };
      });

      const user = await ctx.User.create({
        email: 'shared@example.com',
        emailHash: 'hash-eve',
        displayName: 'Eve',
      });

      const customerId = await ctx.service.getOrCreateStripeCustomer(
        user._id.toString(),
        user.email,
      );

      ctx.assert(customerId === 'cus_fresh_for_eve', 'should NOT link to other user customer; must create fresh');
      ctx.assert(ctx.calls.create.length === 1, 'create should fire because metadata did not match');

      const reloaded = await ctx.User.findById(user._id);
      ctx.assert(reloaded.stripeCustomerId === 'cus_fresh_for_eve', 'persisted id must be the fresh one');
      console.log('scenario-cross-user-race-safe-ok');
    `);
    expect(output).toContain('scenario-cross-user-race-safe-ok');
  }, 30000);
});
