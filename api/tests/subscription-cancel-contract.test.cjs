const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const apiRoot = path.join(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

// -----------------------------------------------------------------------------
// Static / source-level contract checks — fast, zero-IO guards on the cancel
// code path so future refactors cannot silently regress back to the NOOP.
// -----------------------------------------------------------------------------
describe('subscription cancel contract — static guards', () => {
  const routes = read('src/modules/subscriptions/routes.ts');
  const paymentService = read('src/services/PaymentService.ts');
  const model = read('src/models/Subscription.ts');

  test('DELETE handler is no longer a NOOP stub', () => {
    expect(routes).not.toContain('Stripe cancellation integration pending');
    expect(routes).not.toContain('// TODO: Call Stripe to cancel');
  });

  test('DELETE handler branches on provider', () => {
    expect(routes).toMatch(/currentSub\.provider === 'apple'/);
    expect(routes).toMatch(/currentSub\.provider === 'stripe'/);
  });

  test('Apple branch returns platform="apple" and manageUrl', () => {
    expect(routes).toContain("platform: 'apple'");
    expect(routes).toContain('https://apps.apple.com/account/subscriptions');
  });

  test('Stripe branch calls cancel helper before mutating local state', () => {
    expect(routes).toContain('cancelStripeSubscriptionAtPeriodEnd');
    // The Stripe await must appear before the save() of the local row.
    const stripeCallIdx = routes.indexOf('cancelStripeSubscriptionAtPeriodEnd');
    // Find the save() that follows on the cancelled row in the stripe branch.
    const afterStripe = routes.slice(stripeCallIdx);
    expect(afterStripe).toMatch(/currentSub\.status = 'cancelled'/);
    expect(afterStripe).toMatch(/currentSub\.autoRenew = false/);
  });

  test('PaymentService exposes a Stripe cancel helper that uses cancel_at_period_end', () => {
    expect(paymentService).toContain('cancelStripeSubscriptionAtPeriodEnd');
    expect(paymentService).toContain('cancel_at_period_end: true');
  });

  test('404 path for missing subscription', () => {
    expect(routes).toContain('StatusCodes.NOT_FOUND');
    expect(routes).toContain('No active subscription to cancel');
  });

  test('Subscription model persists autoRenew and cancelledAt', () => {
    expect(model).toContain('autoRenew: boolean');
    expect(model).toMatch(/autoRenew:\s*\{\s*type:\s*Boolean/);
    expect(model).toMatch(/cancelledAt\??:\s*Date/);
  });

  test('audit log line is emitted on cancel intent', () => {
    expect(routes).toContain('subscription.cancel.intent');
    expect(routes).toContain('previousTier');
  });
});

// -----------------------------------------------------------------------------
// Runtime behavior — exercises the actual DELETE handler against an in-memory
// MongoDB and a stubbed Stripe service. Covers:
//   1) no sub -> 404
//   2) apple sub -> 200, Mongo flipped, response has platform+manageUrl
//   3) stripe sub -> 200, Mongo flipped, stripe.update called with cancel_at_period_end=true
//   4) stripe failure -> 502, Mongo NOT flipped
// -----------------------------------------------------------------------------
describe('subscription cancel contract — runtime behavior', () => {
  test('end-to-end cancel scenarios against in-memory mongo + stubbed stripe', () => {
    const script = `
      const mongoose = require('mongoose');
      const { MongoMemoryServer } = require('mongodb-memory-server');

      // Install Stripe stub BEFORE loading anything that constructs Stripe.
      const stripeCalls = [];
      const StripeModule = require('stripe');
      const OriginalStripe = StripeModule.default || StripeModule;
      function StripeStub() {
        return {
          subscriptions: {
            update: async (id, params) => {
              stripeCalls.push({ method: 'update', id, params });
              if (id === 'sub_force_fail') {
                const e = new Error('Stripe API simulated failure');
                throw e;
              }
              return { id, cancel_at_period_end: true, status: 'active' };
            },
          },
          paymentIntents: { create: async () => ({}), confirm: async () => ({}), retrieve: async () => ({}) },
          paymentMethods: { create: async () => ({}), list: async () => ({ data: [] }) },
          customers: { list: async () => ({ data: [] }), create: async () => ({ id: 'cus_stub' }) },
          webhooks: { constructEvent: () => ({}) },
        };
      }
      StripeStub.default = StripeStub;
      require.cache[require.resolve('stripe')].exports = StripeStub;

      // Silence winston file transport for tests.
      process.env.LOG_DIR = process.env.LOG_DIR || '/tmp/gearsnitch-logs-test';
      process.env.STRIPE_SECRET_KEY = process.env.STRIPE_SECRET_KEY || 'sk_test_stub';
      process.env.NODE_ENV = 'test';

      const express = require('express');
      const { Subscription } = require('./src/models/Subscription.ts');
      const subscriptionsRouter = require('./src/modules/subscriptions/routes.ts').default;

      // Provide a fake auth middleware by stubbing the JWT verification.
      // Simpler: mount a tiny shim that injects req.user.sub before the router.
      const app = express();
      app.use(express.json());
      app.use((req, _res, next) => {
        req.user = { sub: req.header('x-test-user-id'), jti: 't', email: 'e', role: 'r', scope: [], iat: 0, exp: 0 };
        next();
      });
      // Override isAuthenticated by reaching into the router stack is fragile —
      // instead mount a dedicated tester app that skips auth and remounts the
      // same handler functions. We do this by require()ing auth and
      // monkey-patching isAuthenticated BEFORE the router was required would
      // be ideal; here we post-patch the router layers to skip isAuthenticated.
      for (const layer of subscriptionsRouter.stack) {
        if (!layer.route) continue;
        // Strip the first handler (isAuthenticated) from each route stack.
        const stack = layer.route.stack;
        if (stack.length > 1 && stack[0].name === 'isAuthenticated') {
          stack.shift();
        }
      }
      app.use('/subscriptions', subscriptionsRouter);

      function request(method, url, { userId, body } = {}) {
        return new Promise((resolve, reject) => {
          const http = require('http');
          const server = app.listen(0, () => {
            const { port } = server.address();
            const payload = body ? JSON.stringify(body) : null;
            const req = http.request({
              hostname: '127.0.0.1', port, path: url, method,
              headers: {
                'content-type': 'application/json',
                'x-test-user-id': userId,
                ...(payload ? { 'content-length': Buffer.byteLength(payload) } : {}),
              },
            }, (res) => {
              let data = '';
              res.on('data', (c) => { data += c; });
              res.on('end', () => {
                server.close();
                try { resolve({ status: res.statusCode, body: JSON.parse(data) }); }
                catch (e) { resolve({ status: res.statusCode, body: data }); }
              });
            });
            req.on('error', (err) => { server.close(); reject(err); });
            if (payload) req.write(payload);
            req.end();
          });
        });
      }

      (async () => {
        const mongoServer = await MongoMemoryServer.create();
        await mongoose.connect(mongoServer.getUri(), { serverSelectionTimeoutMS: 15000 });

        const results = {};
        try {
          // -------- Scenario 1: no subscription -> 404 --------
          const noSubUser = new mongoose.Types.ObjectId().toString();
          const r1 = await request('DELETE', '/subscriptions', { userId: noSubUser });
          results.scenario1 = r1;
          if (r1.status !== 404) throw new Error('Expected 404 for no-sub, got ' + r1.status);

          // -------- Scenario 2: Apple sub -> 200 + local flip + manageUrl --------
          const appleUser = new mongoose.Types.ObjectId().toString();
          const appleSub = await Subscription.create({
            userId: appleUser,
            provider: 'apple',
            providerOriginalTransactionId: 'apple-orig-tx-1',
            productId: 'com.geargrind.gearsnitch.monthly',
            status: 'active',
            purchaseDate: new Date(),
            expiryDate: new Date(Date.now() + 30 * 24 * 3600 * 1000),
            lastValidatedAt: new Date(),
            extensionDays: 0,
            autoRenew: true,
          });
          const r2 = await request('DELETE', '/subscriptions', { userId: appleUser });
          results.scenario2 = r2;
          if (r2.status !== 200) throw new Error('Expected 200 for apple, got ' + r2.status);
          const d2 = r2.body.data;
          if (d2.platform !== 'apple') throw new Error('Expected platform apple, got ' + d2.platform);
          if (d2.autoRenew !== false) throw new Error('Expected autoRenew false');
          if (d2.manageUrl !== 'https://apps.apple.com/account/subscriptions') {
            throw new Error('Expected manageUrl for Apple, got ' + d2.manageUrl);
          }
          const appleReloaded = await Subscription.findById(appleSub._id).lean();
          if (appleReloaded.status !== 'cancelled') {
            throw new Error('Apple local status not flipped, got ' + appleReloaded.status);
          }
          if (appleReloaded.autoRenew !== false) {
            throw new Error('Apple autoRenew not flipped');
          }

          // -------- Scenario 3: Stripe sub -> 200 + mongo flip + stripe called --------
          const stripeUser = new mongoose.Types.ObjectId().toString();
          const stripeSub = await Subscription.create({
            userId: stripeUser,
            provider: 'stripe',
            providerOriginalTransactionId: 'sub_test_abc123',
            productId: 'com.geargrind.gearsnitch.monthly',
            status: 'active',
            purchaseDate: new Date(),
            expiryDate: new Date(Date.now() + 30 * 24 * 3600 * 1000),
            lastValidatedAt: new Date(),
            extensionDays: 0,
            autoRenew: true,
          });
          const r3 = await request('DELETE', '/subscriptions', { userId: stripeUser });
          results.scenario3 = r3;
          if (r3.status !== 200) throw new Error('Expected 200 for stripe, got ' + r3.status + ' body=' + JSON.stringify(r3.body));
          const stripeReloaded = await Subscription.findById(stripeSub._id).lean();
          if (stripeReloaded.status !== 'cancelled') {
            throw new Error('Stripe local status not flipped, got ' + stripeReloaded.status);
          }
          if (stripeReloaded.autoRenew !== false) {
            throw new Error('Stripe autoRenew not flipped');
          }
          const updateCall = stripeCalls.find(c => c.id === 'sub_test_abc123');
          if (!updateCall) throw new Error('Stripe update was not invoked for sub_test_abc123');
          if (updateCall.params.cancel_at_period_end !== true) {
            throw new Error('Stripe update called without cancel_at_period_end=true');
          }

          // -------- Scenario 4: Stripe failure -> 502, Mongo NOT flipped --------
          const failUser = new mongoose.Types.ObjectId().toString();
          const failSub = await Subscription.create({
            userId: failUser,
            provider: 'stripe',
            providerOriginalTransactionId: 'sub_force_fail',
            productId: 'com.geargrind.gearsnitch.monthly',
            status: 'active',
            purchaseDate: new Date(),
            expiryDate: new Date(Date.now() + 30 * 24 * 3600 * 1000),
            lastValidatedAt: new Date(),
            extensionDays: 0,
            autoRenew: true,
          });
          const r4 = await request('DELETE', '/subscriptions', { userId: failUser });
          results.scenario4 = r4;
          if (r4.status !== 502) {
            throw new Error('Expected 502 on stripe failure, got ' + r4.status);
          }
          const failReloaded = await Subscription.findById(failSub._id).lean();
          if (failReloaded.status !== 'active') {
            throw new Error('Mongo was flipped on stripe failure — truth rewritten! got ' + failReloaded.status);
          }
          if (failReloaded.autoRenew !== true) {
            throw new Error('autoRenew was flipped on stripe failure');
          }

          console.log('subscription-cancel-runtime-ok');
        } finally {
          await Subscription.deleteMany({});
          await mongoose.disconnect();
          await mongoServer.stop();
        }
      })().catch((err) => {
        console.error('RUNTIME_FAIL:', err.message || err);
        if (err.stack) console.error(err.stack);
        process.exit(1);
      });
    `;

    const output = execFileSync(
      process.execPath,
      ['-r', 'tsx/cjs', '-e', script],
      {
        cwd: apiRoot,
        encoding: 'utf8',
        stdio: 'pipe',
      },
    );

    expect(output).toContain('subscription-cancel-runtime-ok');
  }, 60000);
});
