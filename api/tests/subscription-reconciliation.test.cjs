const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const apiRoot = path.join(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

function readAbs(absolutePath) {
  return fs.readFileSync(absolutePath, 'utf8');
}

// ---------------------------------------------------------------------------
// 1. Static contract assertions — file shape, exports, event types, routes.
// ---------------------------------------------------------------------------
describe('subscription reconciliation — contract', () => {
  const reconciliation = read('src/modules/subscriptions/reconciliation.ts');
  const clients = read('src/modules/subscriptions/reconciliationClients.ts');
  const adminRoutes = read('src/modules/admin/routes.ts');
  const adminReconciliation = read('src/modules/admin/reconciliation.ts');
  const eventLog = read('src/models/EventLog.ts');
  const workerIndex = readAbs(
    path.join(apiRoot, '..', 'worker', 'src', 'index.ts'),
  );
  const workerJob = readAbs(
    path.join(apiRoot, '..', 'worker', 'src', 'jobs', 'subscriptionReconciliation.ts'),
  );

  test('EventLog declares all four reconciliation event types', () => {
    expect(eventLog).toContain('SubscriptionDriftHealed');
    expect(eventLog).toContain('SubscriptionNotAtProvider');
    expect(eventLog).toContain('ReconciliationFailed');
    expect(eventLog).toContain('ReconciliationRunComplete');
  });

  test('reconciliation module exports the pure decision function', () => {
    expect(reconciliation).toContain('export function decideReconciliationOutcome');
    expect(reconciliation).toContain('export async function reconcileOne');
    expect(reconciliation).toContain('export async function reconcileAllSubscriptions');
    expect(reconciliation).toContain('export async function getLastReconciliationRun');
  });

  test('reconciliation skips terminal statuses (only active/grace_period/past_due scan)', () => {
    expect(reconciliation).toMatch(
      /LIVE_RECONCILIATION_STATUSES[^=]*=\s*\[[^\]]*'active'[^\]]*'grace_period'[^\]]*'past_due'/,
    );
    expect(reconciliation).not.toMatch(
      /LIVE_RECONCILIATION_STATUSES[^=]*=\s*\[[^\]]*'cancelled'/,
    );
    expect(reconciliation).not.toMatch(
      /LIVE_RECONCILIATION_STATUSES[^=]*=\s*\[[^\]]*'refunded'/,
    );
    expect(reconciliation).not.toMatch(
      /LIVE_RECONCILIATION_STATUSES[^=]*=\s*\[[^\]]*'revoked'/,
    );
  });

  test('reconciliation streams via mongoose cursor + 100-row batches', () => {
    expect(reconciliation).toContain('.cursor()');
    expect(reconciliation).toMatch(/batchSize\s*=\s*100/);
  });

  test('clients bind to stripe subscriptions.retrieve + Apple getSubscriptionStatuses', () => {
    expect(clients).toMatch(/subscriptions\.retrieve\s*\(/);
    expect(clients).toContain('getSubscriptionStatuses');
    expect(clients).toContain('AppStoreServerAPI');
  });

  test('admin module mounts /reconciliation with admin auth already applied', () => {
    // `router.use(isAuthenticated, hasRole(['admin']))` is applied before
    // the reconciliation router is mounted, so both routes inherit it.
    const guardIdx = adminRoutes.indexOf(
      "router.use(isAuthenticated, hasRole(['admin']))",
    );
    const mountIdx = adminRoutes.indexOf("router.use('/reconciliation'");
    expect(guardIdx).toBeGreaterThan(-1);
    expect(mountIdx).toBeGreaterThan(guardIdx);
  });

  test('admin reconciliation router exposes GET /last-run and POST /run', () => {
    expect(adminReconciliation).toContain("router.get('/last-run'");
    expect(adminReconciliation).toContain("router.post('/run'");
  });

  test('worker registers subscription-reconciliation queue + weekly cron', () => {
    expect(workerIndex).toContain("'subscription-reconciliation'");
    expect(workerIndex).toContain('processSubscriptionReconciliation');
    // Sunday 03:00 UTC cron pattern
    expect(workerIndex).toMatch(/['"]0 3 \* \* 0['"]/);
    expect(workerIndex).toContain("tz: 'UTC'");
  });

  test('worker job scans only live statuses + paces + streams', () => {
    expect(workerJob).toMatch(
      /LIVE_STATUSES[^=]*=\s*\[[^\]]*'active'[^\]]*'grace_period'[^\]]*'past_due'/,
    );
    expect(workerJob).toMatch(/BATCH_SIZE\s*=\s*100/);
    expect(workerJob).toMatch(/PACING_MS\s*=\s*10/);
    expect(workerJob).toContain('SubscriptionDriftHealed');
    expect(workerJob).toContain('SubscriptionNotAtProvider');
    expect(workerJob).toContain('ReconciliationFailed');
    expect(workerJob).toContain('ReconciliationRunComplete');
  });
});

// ---------------------------------------------------------------------------
// 2. Unit tests for `decideReconciliationOutcome` — the pure drift decider.
// ---------------------------------------------------------------------------
describe('subscription reconciliation — decideReconciliationOutcome', () => {
  function runScript(body) {
    const script = `
      (async () => {
        const { decideReconciliationOutcome } = require('./src/modules/subscriptions/reconciliation.ts');
        const results = [];
        const assert = require('node:assert');
        const push = (label, value) => results.push({ label, value });
        ${body}
        console.log(JSON.stringify(results));
      })().catch((err) => {
        console.error(err.stack || err);
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
        env: {
          ...process.env,
          STRIPE_SECRET_KEY:
            process.env.STRIPE_SECRET_KEY || 'sk_test_' + 'a'.repeat(99),
          STRIPE_WEBHOOK_SECRET:
            process.env.STRIPE_WEBHOOK_SECRET || 'whsec_test_' + 'a'.repeat(32),
        },
      },
    );
    const lastLine = output.trim().split('\n').pop();
    return JSON.parse(lastLine);
  }

  test('Apple: active in Mongo, expired at Apple → drift_healed(expired)', () => {
    const results = runScript(`
      const sub = {
        id: 'sub_a',
        userId: 'u1',
        provider: 'apple',
        providerOriginalTransactionId: 'oti-a',
        status: 'active',
        expiryDate: new Date('2026-05-01T00:00:00Z'),
        autoRenew: true,
      };
      const lookup = {
        outcome: 'found',
        state: {
          status: 'expired',
          expiryDate: new Date('2026-04-15T00:00:00Z'),
          autoRenew: false,
        },
      };
      const out = decideReconciliationOutcome(sub, lookup);
      push('kind', out.kind);
      push('afterStatus', out.kind === 'drift_healed' ? out.after.status : null);
    `);
    const byLabel = Object.fromEntries(results.map((r) => [r.label, r.value]));
    expect(byLabel.kind).toBe('drift_healed');
    expect(byLabel.afterStatus).toBe('expired');
  });

  test('Stripe: active in Mongo, cancelled at Stripe → drift_healed(cancelled)', () => {
    const results = runScript(`
      const sub = {
        id: 'sub_s',
        userId: 'u2',
        provider: 'stripe',
        providerOriginalTransactionId: 'sub_stripe_abc',
        stripeSubscriptionId: 'sub_stripe_abc',
        status: 'active',
        expiryDate: new Date('2026-06-01T00:00:00Z'),
        autoRenew: true,
      };
      const lookup = {
        outcome: 'found',
        state: {
          status: 'cancelled',
          expiryDate: new Date('2026-04-10T00:00:00Z'),
          autoRenew: false,
        },
      };
      const out = decideReconciliationOutcome(sub, lookup);
      push('kind', out.kind);
      push('afterStatus', out.kind === 'drift_healed' ? out.after.status : null);
    `);
    const byLabel = Object.fromEntries(results.map((r) => [r.label, r.value]));
    expect(byLabel.kind).toBe('drift_healed');
    expect(byLabel.afterStatus).toBe('cancelled');
  });

  test('Apple: past_due in Mongo, active at Apple → drift_healed(active)', () => {
    const results = runScript(`
      const sub = {
        id: 'sub_p',
        userId: 'u3',
        provider: 'apple',
        providerOriginalTransactionId: 'oti-p',
        status: 'past_due',
        expiryDate: new Date('2026-04-10T00:00:00Z'),
        autoRenew: true,
      };
      const lookup = {
        outcome: 'found',
        state: {
          status: 'active',
          expiryDate: new Date('2026-05-10T00:00:00Z'),
          autoRenew: true,
        },
      };
      const out = decideReconciliationOutcome(sub, lookup);
      push('kind', out.kind);
      push('afterStatus', out.kind === 'drift_healed' ? out.after.status : null);
    `);
    const byLabel = Object.fromEntries(results.map((r) => [r.label, r.value]));
    expect(byLabel.kind).toBe('drift_healed');
    expect(byLabel.afterStatus).toBe('active');
  });

  test('not_at_provider → outcome.kind = not_at_provider', () => {
    const results = runScript(`
      const sub = {
        id: 'sub_missing',
        userId: 'u4',
        provider: 'stripe',
        providerOriginalTransactionId: 'sub_missing',
        stripeSubscriptionId: 'sub_missing',
        status: 'active',
        expiryDate: new Date('2026-05-01T00:00:00Z'),
        autoRenew: true,
      };
      const out = decideReconciliationOutcome(sub, { outcome: 'not_found' });
      push('kind', out.kind);
    `);
    const byLabel = Object.fromEntries(results.map((r) => [r.label, r.value]));
    expect(byLabel.kind).toBe('not_at_provider');
  });

  test('provider 5xx / transient → outcome.kind = transient_error, no mutation', () => {
    const results = runScript(`
      const sub = {
        id: 'sub_flap',
        userId: 'u5',
        provider: 'stripe',
        providerOriginalTransactionId: 'sub_flap',
        stripeSubscriptionId: 'sub_flap',
        status: 'active',
        expiryDate: new Date('2026-05-01T00:00:00Z'),
        autoRenew: true,
      };
      const out = decideReconciliationOutcome(sub, {
        outcome: 'transient_error',
        error: 'HTTP 503 from Stripe',
      });
      push('kind', out.kind);
      push('error', out.kind === 'transient_error' ? out.error : null);
    `);
    const byLabel = Object.fromEntries(results.map((r) => [r.label, r.value]));
    expect(byLabel.kind).toBe('transient_error');
    expect(byLabel.error).toContain('503');
  });

  test('no material difference → noop', () => {
    const results = runScript(`
      const expiry = new Date('2026-05-01T00:00:00Z');
      const sub = {
        id: 'sub_ok',
        userId: 'u6',
        provider: 'stripe',
        providerOriginalTransactionId: 'sub_ok',
        stripeSubscriptionId: 'sub_ok',
        status: 'active',
        expiryDate: expiry,
        autoRenew: true,
      };
      const out = decideReconciliationOutcome(sub, {
        outcome: 'found',
        state: {
          status: 'active',
          expiryDate: new Date(expiry.getTime()),
          autoRenew: true,
        },
      });
      push('kind', out.kind);
    `);
    const byLabel = Object.fromEntries(results.map((r) => [r.label, r.value]));
    expect(byLabel.kind).toBe('noop');
  });
});

// ---------------------------------------------------------------------------
// 3. Integration test — full POST /admin/reconciliation/run flow with
//    seeded divergent subscriptions + mocked provider clients.
// ---------------------------------------------------------------------------
describe('subscription reconciliation — integration', () => {
  test('POST /admin/reconciliation/run heals drift, marks missing, logs failures', () => {
    const script = `
      const mongoose = require('mongoose');
      const { MongoMemoryServer } = require('mongodb-memory-server');
      const express = require('express');

      (async () => {
        const mongoServer = await MongoMemoryServer.create();
        await mongoose.connect(mongoServer.getUri(), {
          serverSelectionTimeoutMS: 15000,
        });

        const { Subscription } = require('./src/models/Subscription.ts');
        const { EventLog } = require('./src/models/EventLog.ts');
        const { createReconciliationRouter } = require('./src/modules/admin/reconciliation.ts');

        // Mock clients: return fixtures keyed on providerOriginalTransactionId.
        const appleLookups = new Map();
        const stripeLookups = new Map();
        const mockClients = {
          apple: {
            async lookup(sub) {
              const fx = appleLookups.get(sub.providerOriginalTransactionId);
              if (!fx) throw new Error('Apple fixture missing for ' + sub.providerOriginalTransactionId);
              return fx;
            },
          },
          stripe: {
            async lookup(sub) {
              const fx = stripeLookups.get(sub.providerOriginalTransactionId);
              if (!fx) throw new Error('Stripe fixture missing for ' + sub.providerOriginalTransactionId);
              return fx;
            },
          },
        };

        const router = createReconciliationRouter(() => mockClients);
        const app = express();
        app.use(express.json());
        app.use('/admin/reconciliation', router);

        const http = require('node:http');
        const server = http.createServer(app);
        await new Promise((resolve) => server.listen(0, resolve));
        const port = server.address().port;

        async function post(pathname) {
          return new Promise((resolve, reject) => {
            const req = http.request({
              host: '127.0.0.1',
              port,
              method: 'POST',
              path: pathname,
              headers: { 'Content-Type': 'application/json' },
            }, (res) => {
              let chunks = '';
              res.on('data', (c) => chunks += c);
              res.on('end', () => {
                resolve({ status: res.statusCode, body: JSON.parse(chunks || '{}') });
              });
            });
            req.on('error', reject);
            req.end();
          });
        }

        async function get(pathname) {
          return new Promise((resolve, reject) => {
            const req = http.request({
              host: '127.0.0.1',
              port,
              method: 'GET',
              path: pathname,
            }, (res) => {
              let chunks = '';
              res.on('data', (c) => chunks += c);
              res.on('end', () => {
                resolve({ status: res.statusCode, body: JSON.parse(chunks || '{}') });
              });
            });
            req.on('error', reject);
            req.end();
          });
        }

        try {
          const userId = new mongoose.Types.ObjectId();

          // Seed 5 rows covering every case:
          //   a) Apple: active in Mongo, expired at Apple → heal to expired.
          //   b) Stripe: active in Mongo, cancelled at Stripe → heal to cancelled.
          //   c) Apple: past_due in Mongo, active at Apple → heal to active.
          //   d) Stripe: not_found at provider → mark Mongo expired.
          //   e) Apple: transient 5xx → leave row alone, log failure.
          //   f) Terminal row (refunded) → must be SKIPPED (not scanned).
          const now = new Date();

          const subA = await Subscription.create({
            userId, provider: 'apple',
            providerOriginalTransactionId: 'apple-a',
            productId: 'com.geargrind.gearsnitch.monthly',
            status: 'active',
            purchaseDate: new Date('2026-03-01T00:00:00Z'),
            expiryDate: new Date('2026-05-01T00:00:00Z'),
            lastValidatedAt: now,
            extensionDays: 0,
            autoRenew: true,
          });
          appleLookups.set('apple-a', {
            outcome: 'found',
            state: {
              status: 'expired',
              expiryDate: new Date('2026-04-15T00:00:00Z'),
              autoRenew: false,
            },
          });

          const subB = await Subscription.create({
            userId, provider: 'stripe',
            providerOriginalTransactionId: 'stripe-b',
            stripeSubscriptionId: 'stripe-b',
            productId: 'prod_b',
            status: 'active',
            purchaseDate: new Date('2026-03-05T00:00:00Z'),
            expiryDate: new Date('2026-06-01T00:00:00Z'),
            lastValidatedAt: now,
            extensionDays: 0,
            autoRenew: true,
          });
          stripeLookups.set('stripe-b', {
            outcome: 'found',
            state: {
              status: 'cancelled',
              expiryDate: new Date('2026-04-10T00:00:00Z'),
              autoRenew: false,
            },
          });

          const subC = await Subscription.create({
            userId, provider: 'apple',
            providerOriginalTransactionId: 'apple-c',
            productId: 'com.geargrind.gearsnitch.annual',
            status: 'past_due',
            purchaseDate: new Date('2026-01-01T00:00:00Z'),
            expiryDate: new Date('2026-04-10T00:00:00Z'),
            lastValidatedAt: now,
            extensionDays: 0,
            autoRenew: true,
          });
          appleLookups.set('apple-c', {
            outcome: 'found',
            state: {
              status: 'active',
              expiryDate: new Date('2026-05-10T00:00:00Z'),
              autoRenew: true,
            },
          });

          const subD = await Subscription.create({
            userId, provider: 'stripe',
            providerOriginalTransactionId: 'stripe-d',
            stripeSubscriptionId: 'stripe-d',
            productId: 'prod_d',
            status: 'active',
            purchaseDate: new Date('2026-02-01T00:00:00Z'),
            expiryDate: new Date('2026-05-01T00:00:00Z'),
            lastValidatedAt: now,
            extensionDays: 0,
            autoRenew: true,
          });
          stripeLookups.set('stripe-d', { outcome: 'not_found' });

          const subE = await Subscription.create({
            userId, provider: 'apple',
            providerOriginalTransactionId: 'apple-e',
            productId: 'com.geargrind.gearsnitch.monthly',
            status: 'active',
            purchaseDate: new Date('2026-03-15T00:00:00Z'),
            expiryDate: new Date('2026-05-15T00:00:00Z'),
            lastValidatedAt: now,
            extensionDays: 0,
            autoRenew: true,
          });
          appleLookups.set('apple-e', {
            outcome: 'transient_error',
            error: 'HTTP 503 upstream',
          });

          // Terminal — must not be scanned.
          const subTerm = await Subscription.create({
            userId, provider: 'stripe',
            providerOriginalTransactionId: 'stripe-terminal',
            stripeSubscriptionId: 'stripe-terminal',
            productId: 'prod_t',
            status: 'refunded',
            purchaseDate: new Date('2026-01-15T00:00:00Z'),
            expiryDate: new Date('2026-02-15T00:00:00Z'),
            lastValidatedAt: now,
            extensionDays: 0,
            autoRenew: false,
          });
          // If the reconciler scans it, this will throw "fixture missing".

          // Initially /last-run should say null.
          const empty = await get('/admin/reconciliation/last-run');
          if (empty.status !== 200) throw new Error('last-run initial expected 200, got ' + empty.status);
          if (empty.body.data.lastRun !== null) {
            throw new Error('expected null lastRun initially, got ' + JSON.stringify(empty.body));
          }

          // Kick the run.
          const runRes = await post('/admin/reconciliation/run');
          if (runRes.status !== 200) throw new Error('run expected 200, got ' + runRes.status + ' body=' + JSON.stringify(runRes.body));
          const counters = runRes.body.data.run.counters;
          if (counters.rows_scanned !== 5) throw new Error('expected rows_scanned=5, got ' + counters.rows_scanned);
          if (counters.drift_healed !== 3) throw new Error('expected drift_healed=3, got ' + counters.drift_healed);
          if (counters.not_at_provider !== 1) throw new Error('expected not_at_provider=1, got ' + counters.not_at_provider);
          if (counters.failed !== 1) throw new Error('expected failed=1, got ' + counters.failed);

          // Verify Mongo state.
          const after = {};
          for (const id of ['apple-a', 'stripe-b', 'apple-c', 'stripe-d', 'apple-e', 'stripe-terminal']) {
            after[id] = await Subscription.findOne({ providerOriginalTransactionId: id });
          }
          if (after['apple-a'].status !== 'expired') throw new Error('apple-a expected expired, got ' + after['apple-a'].status);
          if (after['stripe-b'].status !== 'cancelled') throw new Error('stripe-b expected cancelled, got ' + after['stripe-b'].status);
          if (after['apple-c'].status !== 'active') throw new Error('apple-c expected active, got ' + after['apple-c'].status);
          if (after['stripe-d'].status !== 'expired') throw new Error('stripe-d expected expired, got ' + after['stripe-d'].status);
          if (after['apple-e'].status !== 'active') throw new Error('apple-e should have been left alone on transient, got ' + after['apple-e'].status);
          if (after['stripe-terminal'].status !== 'refunded') throw new Error('terminal row must not be touched');

          // Verify EventLog counts.
          const heals = await EventLog.countDocuments({ eventType: 'SubscriptionDriftHealed' });
          const missing = await EventLog.countDocuments({ eventType: 'SubscriptionNotAtProvider' });
          const failed = await EventLog.countDocuments({ eventType: 'ReconciliationFailed' });
          const completes = await EventLog.countDocuments({ eventType: 'ReconciliationRunComplete' });
          if (heals !== 3) throw new Error('expected 3 DriftHealed events, got ' + heals);
          if (missing !== 1) throw new Error('expected 1 NotAtProvider event, got ' + missing);
          if (failed !== 1) throw new Error('expected 1 Failed event, got ' + failed);
          if (completes !== 1) throw new Error('expected 1 RunComplete event, got ' + completes);

          // /last-run should now surface the summary.
          const lastRes = await get('/admin/reconciliation/last-run');
          if (lastRes.status !== 200) throw new Error('last-run expected 200, got ' + lastRes.status);
          if (!lastRes.body.data.lastRun) throw new Error('expected lastRun populated after run');
          if (lastRes.body.data.lastRun.counters.drift_healed !== 3) {
            throw new Error('expected lastRun counters to reflect drift_healed=3');
          }

          console.log('subscription-reconciliation-integration-ok');
        } finally {
          await new Promise((resolve) => server.close(resolve));
          await Subscription.deleteMany({});
          await EventLog.deleteMany({});
          await mongoose.disconnect();
          await mongoServer.stop();
        }
      })().catch((err) => {
        console.error(err && err.stack ? err.stack : err);
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
        env: {
          ...process.env,
          // PaymentService is loaded transitively (admin/routes → reconciliation → clients)
          // so provide valid-shaped keys; no live calls happen.
          STRIPE_SECRET_KEY:
            process.env.STRIPE_SECRET_KEY || 'sk_test_' + 'a'.repeat(99),
          STRIPE_WEBHOOK_SECRET:
            process.env.STRIPE_WEBHOOK_SECRET || 'whsec_test_' + 'a'.repeat(32),
        },
      },
    );

    expect(output).toContain('subscription-reconciliation-integration-ok');
  }, 90000);
});
