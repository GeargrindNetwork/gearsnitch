const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const apiRoot = path.join(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

// -----------------------------------------------------------------------------
// Static / source-level contract checks — cheap guard against future refactors
// silently breaking the Billing History surface (backlog item #22).
// -----------------------------------------------------------------------------
describe('subscription invoices contract — static guards (item #22)', () => {
  const routes = read('src/modules/subscriptions/routes.ts');
  const invoicesService = read('src/modules/subscriptions/invoicesService.ts');

  test('GET /invoices is registered and auth-guarded', () => {
    expect(routes).toMatch(
      /router\.get\(\s*['"]\/invoices['"]\s*,\s*isAuthenticated\s*,/,
    );
  });

  test('route delegates to a service (no raw Stripe client inside routes.ts)', () => {
    // Keeps parity with the portal-session contract: no `new StripeLib` in routes.
    expect(routes).not.toMatch(/new\s+StripeLib\s*\(/);
    expect(routes).toContain('listSanitizedInvoicesForUser');
  });

  test('route surfaces pagination fields so the client can page further', () => {
    expect(routes).toContain('startingAfter');
    expect(routes).toContain('hasMore');
    expect(routes).toContain('nextCursor');
  });

  test('InvoiceListError is translated into the Stripe error envelope', () => {
    expect(routes).toContain('InvoiceListError');
    expect(routes).toContain('err.statusCode');
    expect(routes).toContain('subscription.invoices.failed');
  });

  test('invoicesService wraps stripe.invoices.list with the users customer id', () => {
    expect(invoicesService).toContain('stripe.invoices.list');
    expect(invoicesService).toContain('customer: user.stripeCustomerId');
    expect(invoicesService).toContain("starting_after: startingAfter");
  });

  test('invoicesService returns empty list (not 4xx) for users without a Stripe customer', () => {
    // Apple-only subscribers legitimately have no stripeCustomerId — that
    // MUST NOT surface as an error to the client, otherwise the UI would
    // show an error toast instead of the empty state.
    expect(invoicesService).toMatch(
      /if\s*\(\s*!\s*user\.stripeCustomerId\s*\)[\s\S]{0,600}?invoices:\s*\[\]/,
    );
  });

  test('invoicesService produces sanitized fields matching the web API contract', () => {
    // These keys are the agreed-upon web payload; changing them is a
    // breaking change for BillingHistoryPage.tsx.
    for (const field of [
      'id',
      'number',
      'createdAt',
      'paidAt',
      'amountPaid',
      'amountDue',
      'currency',
      'status',
      'hostedInvoiceUrl',
      'invoicePdfUrl',
      'description',
      'periodStart',
      'periodEnd',
    ]) {
      expect(invoicesService).toContain(field);
    }
  });

  test('Stripe errors throw InvoiceListError so the route can emit 502 Bad Gateway', () => {
    expect(invoicesService).toContain('InvoiceListError');
    expect(invoicesService).toContain('STRIPE_INVOICE_LIST_FAILED');
    expect(invoicesService).toMatch(/statusCode[\s\S]{0,80}?502/);
  });

  test('listing is limited to a sane upper bound (no unbounded pagination)', () => {
    // The service clamps limit to [1, 100]. If this regresses to `limit: 1000`
    // we risk accidental DoS of the Stripe API on customers with many invoices.
    expect(invoicesService).toMatch(/Math\.min\([^\n]*100/);
  });

  test('portal-session contract is unchanged (existing route is not regressed)', () => {
    expect(routes).toMatch(/router\.post\(\s*['"]\/portal-session['"]\s*,\s*isAuthenticated\s*,/);
    expect(routes).toContain('paymentService.createBillingPortalSession');
  });
});

// -----------------------------------------------------------------------------
// Runtime behavior — exercises the handler against in-memory mongo with a
// stubbed Stripe SDK injected via __setInvoicesStripeClientForTesting. Covers
// the five required cases and more:
//   1) happy path returns sanitized invoices
//   2) no stripeCustomerId -> 200 with empty list (NOT 4xx)
//   3) Stripe SDK rejects -> 502
//   4) paid vs open invoices -> preserved as distinct statuses
//   5) starting_after cursor is forwarded to Stripe
// -----------------------------------------------------------------------------
describe('subscription invoices contract — runtime behavior (item #22)', () => {
  test('end-to-end invoice listing scenarios against in-memory mongo + stubbed stripe', () => {
    const script = `
      const mongoose = require('mongoose');
      const { MongoMemoryServer } = require('mongodb-memory-server');

      // Silence logger file transports in CI.
      process.env.LOG_DIR = process.env.LOG_DIR || '/tmp/gearsnitch-logs-test';
      process.env.STRIPE_SECRET_KEY = process.env.STRIPE_SECRET_KEY || 'sk_test_stub';
      process.env.NODE_ENV = 'test';

      const express = require('express');
      const { User } = require('./src/models/User.ts');
      const subscriptionsRouter = require('./src/modules/subscriptions/routes.ts').default;
      const {
        __setInvoicesStripeClientForTesting,
      } = require('./src/modules/subscriptions/invoicesService.ts');

      // --- Stripe stub -----------------------------------------------------
      const stripeCalls = [];
      let listImpl = null;
      function setStripeList(fn) { listImpl = fn; }

      const stripeStub = {
        invoices: {
          list: async (params) => {
            stripeCalls.push({ method: 'list', params });
            if (!listImpl) return { data: [], has_more: false };
            return listImpl(params);
          },
        },
      };
      __setInvoicesStripeClientForTesting(stripeStub);

      // --- Test app with auth shim ----------------------------------------
      const app = express();
      app.use(express.json());
      app.use((req, _res, next) => {
        req.user = { sub: req.header('x-test-user-id'), jti: 't', email: 'e', role: 'r', scope: [], iat: 0, exp: 0 };
        next();
      });
      for (const layer of subscriptionsRouter.stack) {
        if (!layer.route) continue;
        const stack = layer.route.stack;
        if (stack.length > 1 && stack[0].name === 'isAuthenticated') {
          stack.shift();
        }
      }
      app.use('/subscriptions', subscriptionsRouter);

      function request(method, url, { userId } = {}) {
        return new Promise((resolve, reject) => {
          const http = require('http');
          const server = app.listen(0, () => {
            const { port } = server.address();
            const req = http.request({
              hostname: '127.0.0.1', port, path: url, method,
              headers: {
                'content-type': 'application/json',
                'x-test-user-id': userId || '',
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
            req.end();
          });
        });
      }

      (async () => {
        const mongoServer = await MongoMemoryServer.create();
        await mongoose.connect(mongoServer.getUri(), { serverSelectionTimeoutMS: 15000 });

        try {
          // -------- Scenario 1: happy path, paid + open mixed --------------
          const happyUser = await User.create({
            email: 'happy@example.com',
            emailHash: 'hash-happy',
            displayName: 'Happy Path',
            stripeCustomerId: 'cus_happy_123',
          });

          stripeCalls.length = 0;
          setStripeList(async () => ({
            has_more: false,
            data: [
              {
                id: 'in_paid_001',
                number: 'GS-0001',
                created: 1700000000,
                status: 'paid',
                amount_paid: 499,
                amount_due: 499,
                currency: 'usd',
                hosted_invoice_url: 'https://invoice.stripe.com/hosted_paid',
                invoice_pdf: 'https://invoice.stripe.com/pdf_paid',
                description: 'Hustle — monthly',
                period_start: 1700000000,
                period_end: 1702592000,
                status_transitions: { paid_at: 1700000100 },
              },
              {
                id: 'in_open_002',
                number: 'GS-0002',
                created: 1702500000,
                status: 'open',
                amount_paid: 0,
                amount_due: 499,
                currency: 'usd',
                hosted_invoice_url: 'https://invoice.stripe.com/hosted_open',
                invoice_pdf: 'https://invoice.stripe.com/pdf_open',
                description: null,
                period_start: 1702500000,
                period_end: 1705092000,
                status_transitions: { paid_at: null },
              },
            ],
          }));
          const r1 = await request('GET', '/subscriptions/invoices', { userId: happyUser._id.toString() });
          if (r1.status !== 200) throw new Error('Expected 200 for happy path, got ' + r1.status + ' body=' + JSON.stringify(r1.body));
          const payload1 = r1.body.data;
          if (!payload1 || !Array.isArray(payload1.invoices)) throw new Error('Expected invoices array');
          if (payload1.invoices.length !== 2) throw new Error('Expected 2 invoices, got ' + payload1.invoices.length);
          const paid = payload1.invoices.find(i => i.id === 'in_paid_001');
          const open = payload1.invoices.find(i => i.id === 'in_open_002');
          if (!paid || paid.status !== 'paid') throw new Error('Expected paid status preserved');
          if (paid.invoicePdfUrl !== 'https://invoice.stripe.com/pdf_paid') throw new Error('PDF url not passed through');
          if (paid.hostedInvoiceUrl !== 'https://invoice.stripe.com/hosted_paid') throw new Error('hosted url not passed through');
          if (paid.amountPaid !== 499) throw new Error('amountPaid not surfaced');
          if (!paid.paidAt || paid.paidAt.indexOf('2023') === -1) throw new Error('paidAt ISO missing: ' + paid.paidAt);
          if (!open || open.status !== 'open') throw new Error('Expected open status preserved');
          if (open.paidAt !== null) throw new Error('open invoice should have null paidAt');
          if (open.amountDue !== 499) throw new Error('amountDue not surfaced for open invoice');
          if (stripeCalls.length !== 1) throw new Error('Expected exactly 1 stripe call on happy path, got ' + stripeCalls.length);
          if (stripeCalls[0].params.customer !== 'cus_happy_123') {
            throw new Error('Wrong customer forwarded to Stripe: ' + stripeCalls[0].params.customer);
          }

          // -------- Scenario 2: no stripeCustomerId -> 200 + empty list ----
          const appleOnlyUser = await User.create({
            email: 'apple-only@example.com',
            emailHash: 'hash-apple-only',
            displayName: 'Apple Only',
          });
          stripeCalls.length = 0;
          const r2 = await request('GET', '/subscriptions/invoices', { userId: appleOnlyUser._id.toString() });
          if (r2.status !== 200) throw new Error('Expected 200 for apple-only, got ' + r2.status);
          const payload2 = r2.body.data;
          if (!payload2 || !Array.isArray(payload2.invoices)) throw new Error('Expected invoices array');
          if (payload2.invoices.length !== 0) throw new Error('Expected empty list for apple-only user, got ' + payload2.invoices.length);
          if (stripeCalls.length !== 0) throw new Error('Stripe MUST NOT be called for users without a stripeCustomerId');

          // -------- Scenario 3: Stripe SDK rejects -> 502 -----------------
          const errorUser = await User.create({
            email: 'err@example.com',
            emailHash: 'hash-err',
            displayName: 'Err',
            stripeCustomerId: 'cus_err_001',
          });
          setStripeList(async () => {
            const e = new Error('Stripe simulated failure');
            throw e;
          });
          const r3 = await request('GET', '/subscriptions/invoices', { userId: errorUser._id.toString() });
          if (r3.status !== 502) throw new Error('Expected 502 on Stripe failure, got ' + r3.status);
          if (!r3.body || r3.body.success !== false) throw new Error('Error envelope wrong');

          // -------- Scenario 4: paid vs open distinction (already partially covered above).
          //           Here we re-run with only-open + uncollectible to assert status mapping.
          const errorUser2 = await User.create({
            email: 'mixed@example.com',
            emailHash: 'hash-mixed',
            displayName: 'Mixed',
            stripeCustomerId: 'cus_mixed_001',
          });
          setStripeList(async () => ({
            has_more: false,
            data: [
              {
                id: 'in_open_only',
                number: null,
                created: 1700100000,
                status: 'open',
                amount_paid: 0,
                amount_due: 999,
                currency: 'usd',
                hosted_invoice_url: null,
                invoice_pdf: null,
                description: null,
                period_start: 1700100000,
                period_end: 1702692000,
                status_transitions: { paid_at: null },
              },
              {
                id: 'in_uncollectible',
                number: null,
                created: 1700200000,
                status: 'uncollectible',
                amount_paid: 0,
                amount_due: 499,
                currency: 'usd',
                hosted_invoice_url: null,
                invoice_pdf: null,
                description: null,
                period_start: 1700200000,
                period_end: 1702792000,
                status_transitions: { paid_at: null },
              },
            ],
          }));
          const r4 = await request('GET', '/subscriptions/invoices', { userId: errorUser2._id.toString() });
          if (r4.status !== 200) throw new Error('Expected 200, got ' + r4.status);
          const statuses4 = r4.body.data.invoices.map(i => i.status).sort();
          if (JSON.stringify(statuses4) !== JSON.stringify(['open', 'uncollectible'])) {
            throw new Error('Status mapping wrong: ' + JSON.stringify(statuses4));
          }

          // -------- Scenario 5: starting_after cursor is forwarded ---------
          const cursorUser = await User.create({
            email: 'cursor@example.com',
            emailHash: 'hash-cursor',
            displayName: 'Cursor',
            stripeCustomerId: 'cus_cursor_001',
          });
          stripeCalls.length = 0;
          setStripeList(async (params) => ({
            has_more: true,
            data: [
              {
                id: 'in_page_b_1',
                number: 'GS-0099',
                created: 1703000000,
                status: 'paid',
                amount_paid: 499,
                amount_due: 499,
                currency: 'usd',
                hosted_invoice_url: 'https://invoice.stripe.com/hosted_b',
                invoice_pdf: 'https://invoice.stripe.com/pdf_b',
                description: null,
                period_start: 1703000000,
                period_end: 1705592000,
                status_transitions: { paid_at: 1703001000 },
              },
            ],
          }));
          const r5 = await request(
            'GET',
            '/subscriptions/invoices?startingAfter=in_page_a_last&limit=10',
            { userId: cursorUser._id.toString() },
          );
          if (r5.status !== 200) throw new Error('Expected 200 for cursor, got ' + r5.status);
          const call = stripeCalls[stripeCalls.length - 1];
          if (!call || call.params.starting_after !== 'in_page_a_last') {
            throw new Error('Expected starting_after to be forwarded, got ' + JSON.stringify(call && call.params));
          }
          if (call.params.limit !== 10) throw new Error('Expected limit to be forwarded as 10, got ' + call.params.limit);
          if (!r5.body.data.hasMore) throw new Error('hasMore should be true when Stripe says so');
          if (r5.body.data.nextCursor !== 'in_page_b_1') throw new Error('nextCursor should equal last invoice id, got ' + r5.body.data.nextCursor);

          console.log('subscription-invoices-runtime-ok');
        } finally {
          __setInvoicesStripeClientForTesting(null);
          await User.deleteMany({});
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

    expect(output).toContain('subscription-invoices-runtime-ok');
  }, 60000);
});
