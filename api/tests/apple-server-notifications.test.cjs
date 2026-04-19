const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const apiRoot = path.join(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

// ---------------------------------------------------------------------------
// 1. Static contract assertions — the route is mounted, unauthenticated,
//    and the new Subscription schema fields exist.
// ---------------------------------------------------------------------------
describe('apple server notifications v2 — route contract', () => {
  const routes = read('src/modules/subscriptions/routes.ts');
  const service = read('src/modules/subscriptions/appleServerNotifications.ts');
  const model = read('src/models/Subscription.ts');
  const webhookModel = read('src/models/ProcessedWebhookEvent.ts');
  const pkg = JSON.parse(read('package.json'));

  test('app-store-server-api is declared as a direct dependency', () => {
    expect(pkg.dependencies['app-store-server-api']).toBeDefined();
  });

  test('route POST /apple/notifications is mounted WITHOUT isAuthenticated', () => {
    expect(routes).toContain("router.post('/apple/notifications'");
    expect(routes).toMatch(
      /router\.post\('\/apple\/notifications',\s*async\s*\(/,
    );
    // Ensure isAuthenticated is NOT on this route
    expect(routes).not.toMatch(
      /router\.post\('\/apple\/notifications',\s*isAuthenticated/,
    );
    expect(routes).toContain('handleAppleSignedNotification');
  });

  test('service verifies notifications via decodeNotificationPayload', () => {
    expect(service).toContain("from 'app-store-server-api'");
    expect(service).toContain('decodeNotificationPayload');
    expect(service).toContain('decodeTransaction');
    expect(service).toContain('decodeRenewalInfo');
  });

  test('service handles all required notification types', () => {
    expect(service).toContain('NotificationType.Subscribed');
    expect(service).toContain('NotificationType.DidRenew');
    expect(service).toContain('NotificationType.DidChangeRenewalStatus');
    expect(service).toContain('NotificationType.DidFailToRenew');
    expect(service).toContain('NotificationType.GracePeriodExpired');
    expect(service).toContain('NotificationType.Expired');
    expect(service).toContain('NotificationType.Refund');
    expect(service).toContain('NotificationType.Revoke');
    expect(service).toContain('NotificationSubtype.AutoRenewDisabled');
    expect(service).toContain('NotificationSubtype.AutoRenewEnabled');
  });

  test('service writes the expected status transitions', () => {
    expect(service).toMatch(/updates\.status\s*=\s*'active'/);
    expect(service).toMatch(/updates\.status\s*=\s*'past_due'/);
    expect(service).toMatch(/updates\.status\s*=\s*'expired'/);
    expect(service).toMatch(/updates\.status\s*=\s*'refunded'/);
    expect(service).toMatch(/updates\.status\s*=\s*'revoked'/);
  });

  test('service uses ProcessedWebhookEvent collection for idempotency', () => {
    expect(service).toContain('ProcessedWebhookEvent');
    expect(service).toContain('notificationUUID');
  });

  test('Subscription schema exposes originalTransactionId + expanded statuses', () => {
    expect(model).toContain('originalTransactionId');
    expect(model).toMatch(/status[:\s]+[^;]*'past_due'/s);
    expect(model).toMatch(/status[:\s]+[^;]*'refunded'/s);
    expect(model).toMatch(/status[:\s]+[^;]*'revoked'/s);
    expect(model).toContain('autoRenew');
    expect(model).toContain('cancelledAt');
    expect(model).toContain("index({ originalTransactionId: 1 })");
  });

  test('ProcessedWebhookEvent model has unique provider+eventId index', () => {
    expect(webhookModel).toContain('provider');
    expect(webhookModel).toContain('eventId');
    expect(webhookModel).toContain('unique: true');
  });
});

// ---------------------------------------------------------------------------
// 2. Runtime integration — mount express app with mocked decode and verify
//    state transitions, invalid signatures, idempotency, and unknown types
//    against an in-memory Mongo.
// ---------------------------------------------------------------------------
describe('apple server notifications v2 — runtime integration', () => {
  test('full lifecycle against mocked decode and mongodb-memory-server', () => {
    const script = `
      const Module = require('module');
      const originalResolve = Module._resolve_filename || Module._resolveFilename;
      const path = require('node:path');
      const mongoose = require('mongoose');
      const { MongoMemoryServer } = require('mongodb-memory-server');
      const express = require('express');

      // Mock app-store-server-api BEFORE any downstream module imports it.
      const realAppStoreApi = require('app-store-server-api');
      const calls = { decodeCalls: 0 };
      const fixtures = new Map();

      function setFixture(signedPayload, payload) {
        fixtures.set(signedPayload, payload);
      }

      const mockedApi = {
        __esModule: true,
        ...realAppStoreApi,
        decodeNotificationPayload: async (signedPayload) => {
          calls.decodeCalls += 1;
          const fixture = fixtures.get(signedPayload);
          if (!fixture) throw new Error('invalid signature');
          return fixture.notification;
        },
        decodeTransaction: async (signedTx) => {
          for (const fixture of fixtures.values()) {
            if (fixture.signedTx === signedTx) return fixture.transaction;
          }
          throw new Error('unknown signed transaction');
        },
        decodeRenewalInfo: async () => ({ autoRenewStatus: 1 }),
      };

      // Override require cache for the package name so downstream imports
      // receive the mocked module.
      const pkgResolved = require.resolve('app-store-server-api');
      require.cache[pkgResolved] = {
        id: pkgResolved,
        filename: pkgResolved,
        loaded: true,
        exports: mockedApi,
      };

      (async () => {
        const mongoServer = await MongoMemoryServer.create();
        await mongoose.connect(mongoServer.getUri(), {
          serverSelectionTimeoutMS: 15000,
        });

        const { Subscription } = require('./src/models/Subscription.ts');
        const { ProcessedWebhookEvent } = require('./src/models/ProcessedWebhookEvent.ts');
        const subscriptionsRoutes = require('./src/modules/subscriptions/routes.ts').default;

        const app = express();
        app.use(express.json());
        app.use('/api/v1/subscriptions', subscriptionsRoutes);

        const http = require('node:http');
        const server = http.createServer(app);
        await new Promise((resolve) => server.listen(0, resolve));
        const port = server.address().port;

        async function post(body) {
          return await new Promise((resolve, reject) => {
            const data = JSON.stringify(body);
            const req = http.request({
              host: '127.0.0.1',
              port,
              method: 'POST',
              path: '/api/v1/subscriptions/apple/notifications',
              headers: {
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(data),
              },
            }, (res) => {
              let chunks = '';
              res.on('data', (c) => chunks += c);
              res.on('end', () => {
                resolve({ status: res.statusCode, body: JSON.parse(chunks || '{}') });
              });
            });
            req.on('error', reject);
            req.write(data);
            req.end();
          });
        }

        try {
          const userId = new mongoose.Types.ObjectId();
          const originalTransactionId = '1000000999999999';

          // Seed an active subscription that webhook handlers will mutate.
          await Subscription.create({
            userId,
            provider: 'apple',
            providerOriginalTransactionId: originalTransactionId,
            productId: 'com.geargrind.gearsnitch.monthly',
            status: 'active',
            purchaseDate: new Date('2026-01-01T00:00:00Z'),
            expiryDate: new Date('2026-02-01T00:00:00Z'),
            lastValidatedAt: new Date(),
            extensionDays: 0,
          });

          function makeFixture(opts) {
            const signedTx = 'signed-tx-' + opts.uuid;
            setFixture('signed-' + opts.uuid, {
              signedTx,
              notification: {
                notificationType: opts.notificationType,
                subtype: opts.subtype,
                notificationUUID: opts.uuid,
                version: '2.0',
                signedDate: Date.now(),
                data: {
                  appAppleId: 123,
                  bundleId: 'com.geargrind.gearsnitch',
                  bundleVersion: '1.0',
                  environment: 'Production',
                  signedTransactionInfo: signedTx,
                },
              },
              transaction: {
                originalTransactionId,
                transactionId: 'tx-' + opts.uuid,
                productId: 'com.geargrind.gearsnitch.monthly',
                purchaseDate: Date.now(),
                expiresDate: opts.expiresDate || Date.now() + 30 * 24 * 60 * 60 * 1000,
                bundleId: 'com.geargrind.gearsnitch',
              },
            });
            return 'signed-' + opts.uuid;
          }

          // Invalid signature → 400
          const invalid = await post({ signedPayload: 'totally-bogus' });
          if (invalid.status !== 400) throw new Error('expected 400 for invalid sig, got ' + invalid.status);

          // Missing signedPayload → 400
          const missing = await post({});
          if (missing.status !== 400) throw new Error('expected 400 for missing payload, got ' + missing.status);

          // DID_RENEW → active + bumped expiry
          const renewExpiry = Date.now() + 90 * 24 * 60 * 60 * 1000;
          const renewPayload = makeFixture({
            uuid: 'uuid-did-renew',
            notificationType: 'DID_RENEW',
            expiresDate: renewExpiry,
          });
          const renewRes = await post({ signedPayload: renewPayload });
          if (renewRes.status !== 200) throw new Error('DID_RENEW expected 200, got ' + renewRes.status);
          let sub = await Subscription.findOne({ providerOriginalTransactionId: originalTransactionId });
          if (sub.status !== 'active') throw new Error('expected active after DID_RENEW, got ' + sub.status);
          if (sub.autoRenew !== true) throw new Error('expected autoRenew true after DID_RENEW');
          if (sub.expiryDate.getTime() !== renewExpiry) {
            throw new Error('expiry not updated: ' + sub.expiryDate.toISOString());
          }

          // Duplicate notificationUUID → idempotent 200, still active, no reprocess
          const dupRes = await post({ signedPayload: renewPayload });
          if (dupRes.status !== 200) throw new Error('duplicate expected 200, got ' + dupRes.status);
          if (dupRes.body.data.status !== 'duplicate') {
            throw new Error('expected duplicate marker, got ' + JSON.stringify(dupRes.body));
          }

          // DID_CHANGE_RENEWAL_STATUS AUTO_RENEW_DISABLED → autoRenew=false
          makeFixture({
            uuid: 'uuid-disable',
            notificationType: 'DID_CHANGE_RENEWAL_STATUS',
            subtype: 'AUTO_RENEW_DISABLED',
          });
          await post({ signedPayload: 'signed-uuid-disable' });
          sub = await Subscription.findOne({ providerOriginalTransactionId: originalTransactionId });
          if (sub.autoRenew !== false) throw new Error('expected autoRenew false');

          // DID_CHANGE_RENEWAL_STATUS AUTO_RENEW_ENABLED → autoRenew=true
          makeFixture({
            uuid: 'uuid-enable',
            notificationType: 'DID_CHANGE_RENEWAL_STATUS',
            subtype: 'AUTO_RENEW_ENABLED',
          });
          await post({ signedPayload: 'signed-uuid-enable' });
          sub = await Subscription.findOne({ providerOriginalTransactionId: originalTransactionId });
          if (sub.autoRenew !== true) throw new Error('expected autoRenew true');

          // DID_FAIL_TO_RENEW → past_due
          makeFixture({
            uuid: 'uuid-fail',
            notificationType: 'DID_FAIL_TO_RENEW',
          });
          await post({ signedPayload: 'signed-uuid-fail' });
          sub = await Subscription.findOne({ providerOriginalTransactionId: originalTransactionId });
          if (sub.status !== 'past_due') throw new Error('expected past_due, got ' + sub.status);

          // GRACE_PERIOD_EXPIRED → expired
          makeFixture({
            uuid: 'uuid-grace',
            notificationType: 'GRACE_PERIOD_EXPIRED',
          });
          await post({ signedPayload: 'signed-uuid-grace' });
          sub = await Subscription.findOne({ providerOriginalTransactionId: originalTransactionId });
          if (sub.status !== 'expired') throw new Error('expected expired, got ' + sub.status);

          // REFUND → refunded + cancelledAt
          makeFixture({
            uuid: 'uuid-refund',
            notificationType: 'REFUND',
          });
          await post({ signedPayload: 'signed-uuid-refund' });
          sub = await Subscription.findOne({ providerOriginalTransactionId: originalTransactionId });
          if (sub.status !== 'refunded') throw new Error('expected refunded, got ' + sub.status);
          if (!sub.cancelledAt) throw new Error('expected cancelledAt set on REFUND');

          // REVOKE → revoked (Family Sharing)
          makeFixture({
            uuid: 'uuid-revoke',
            notificationType: 'REVOKE',
          });
          await post({ signedPayload: 'signed-uuid-revoke' });
          sub = await Subscription.findOne({ providerOriginalTransactionId: originalTransactionId });
          if (sub.status !== 'revoked') throw new Error('expected revoked, got ' + sub.status);

          // EXPIRED → expired
          await Subscription.updateOne({ _id: sub._id }, { status: 'active' });
          makeFixture({
            uuid: 'uuid-expired',
            notificationType: 'EXPIRED',
          });
          await post({ signedPayload: 'signed-uuid-expired' });
          sub = await Subscription.findOne({ providerOriginalTransactionId: originalTransactionId });
          if (sub.status !== 'expired') throw new Error('expected expired, got ' + sub.status);

          // Unknown notification type → 200, no state change
          makeFixture({
            uuid: 'uuid-weird',
            notificationType: 'CONSUMPTION_REQUEST',
          });
          const unknownRes = await post({ signedPayload: 'signed-uuid-weird' });
          if (unknownRes.status !== 200) throw new Error('unknown type expected 200, got ' + unknownRes.status);
          if (unknownRes.body.data.status !== 'ignored') throw new Error('expected ignored for unknown type');

          // Verify idempotency persistence
          const processedCount = await ProcessedWebhookEvent.countDocuments({ provider: 'apple' });
          if (processedCount < 8) throw new Error('expected >=8 processed events, got ' + processedCount);

          // SUBSCRIBED resets to active
          makeFixture({
            uuid: 'uuid-sub',
            notificationType: 'SUBSCRIBED',
          });
          await post({ signedPayload: 'signed-uuid-sub' });
          sub = await Subscription.findOne({ providerOriginalTransactionId: originalTransactionId });
          if (sub.status !== 'active') throw new Error('expected active after SUBSCRIBED, got ' + sub.status);

          console.log('apple-server-notifications-runtime-ok');
        } finally {
          await new Promise((resolve) => server.close(resolve));
          await Subscription.deleteMany({});
          await ProcessedWebhookEvent.deleteMany({});
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
        // PaymentService now instantiates Stripe at module-load, which the
        // subscriptions route drags in transitively. Provide a valid-shaped
        // test-mode key so the Stripe SDK constructor can parse; no live
        // calls are made in this test (everything is mocked).
        env: {
          ...process.env,
          STRIPE_SECRET_KEY: process.env.STRIPE_SECRET_KEY
            || 'sk_test_' + 'a'.repeat(99),
          STRIPE_WEBHOOK_SECRET: process.env.STRIPE_WEBHOOK_SECRET
            || 'whsec_test_' + 'a'.repeat(32),
        },
      },
    );

    expect(output).toContain('apple-server-notifications-runtime-ok');
  }, 60000);
});
