/**
 * Integration test: worker/src/jobs/pushNotification routes iOS tokens
 * through sendAPNsPush and writes NotificationLog rows (one per token).
 *
 * We run everything in a child tsx/cjs process because the worker job
 * reaches into mongoose collections. Uses mongodb-memory-server (already
 * a dev dep) for the mongo side, and the APNs transport is swapped out
 * with an in-memory mock so no sockets are opened to Apple.
 */

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');

const apiRoot = path.join(__dirname, '..');
const repoRoot = path.join(apiRoot, '..');

// Source contract assertions first — cheap and guard the wiring.
describe('APNs push integration — source contract', () => {
  const job = fs.readFileSync(
    path.join(repoRoot, 'worker/src/jobs/pushNotification.ts'),
    'utf8',
  );

  test('worker push job imports sendAPNsPush from the APNs client', () => {
    expect(job).toContain("from '../utils/apnsClient'");
    expect(job).toContain('sendAPNsPush');
  });

  test('worker push job still writes to notificationlogs', () => {
    expect(job).toContain("getCollection('notificationlogs')");
    expect(job).toContain('insertMany');
  });

  test('worker push job respects per-token environment (sandbox vs production)', () => {
    expect(job).toContain('token.environment');
    expect(job).toMatch(/environment\s*[:=]/);
  });

  test('worker push job marks BadDeviceToken/Unregistered tokens dead', () => {
    expect(job).toContain('APNS_REASON_BAD_DEVICE_TOKEN');
    expect(job).toContain('APNS_REASON_UNREGISTERED');
    expect(job).toContain('active: false');
  });

  test('worker push job no longer ships the placeholder-only dispatch stub', () => {
    // Old behaviour: just updateMany(lastUsedAt). New behaviour must
    // actually attempt to send.
    expect(job).toContain('sendAPNsPush({');
    expect(job).not.toMatch(/Push notification dispatch recorded/);
  });
});

// ---------------------------------------------------------------------------
// Runtime: fire processPushNotification against a real in-memory Mongo with
// a mocked APNs transport, then assert NotificationLog rows are written
// and dead tokens are marked inactive.
// ---------------------------------------------------------------------------

describe('APNs push integration — runtime', () => {
  test('routes iOS token through APNs and writes NotificationLog', () => {
    const { privateKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'P-256' });
    const pem = privateKey.export({ type: 'pkcs8', format: 'pem' });

    const script = `
      const mongoose = require('mongoose');
      const { MongoMemoryServer } = require('mongodb-memory-server');

      (async () => {
        const mongoServer = await MongoMemoryServer.create();
        await mongoose.connect(mongoServer.getUri(), { serverSelectionTimeoutMS: 15000 });

        // Swap the APNs transport before the job imports the client.
        const apns = require('../worker/src/utils/apnsClient');
        let callCount = 0;
        apns.__setApnsTransportForTests({
          async request(host, headers, body) {
            callCount++;
            // First token succeeds, second token is BadDeviceToken.
            if (callCount === 1) {
              return {
                statusCode: 200,
                headers: { 'apns-id': 'ok-' + callCount },
                body: '',
              };
            }
            return {
              statusCode: 400,
              headers: { 'apns-id': 'bad-' + callCount },
              body: JSON.stringify({ reason: 'BadDeviceToken' }),
            };
          },
        });
        apns.resetApnsJwtCache();

        const { processPushNotification } = require('../worker/src/jobs/pushNotification');

        const userId = new mongoose.Types.ObjectId();
        const token1Id = new mongoose.Types.ObjectId();
        const token2Id = new mongoose.Types.ObjectId();

        const db = mongoose.connection.db;
        await db.collection('users').insertOne({
          _id: userId,
          preferences: { pushEnabled: true },
        });
        await db.collection('notificationtokens').insertMany([
          {
            _id: token1Id,
            userId,
            platform: 'ios',
            token: 'goodtoken',
            environment: 'production',
            active: true,
          },
          {
            _id: token2Id,
            userId,
            platform: 'ios',
            token: 'badtoken',
            environment: 'sandbox',
            active: true,
          },
        ]);

        await processPushNotification({
          id: 'job-1',
          data: {
            userId: userId.toString(),
            type: 'panic_alarm',
            title: 'Test',
            body: 'Body',
          },
        });

        const logs = await db.collection('notificationlogs').find({ userId }).toArray();
        const tokens = await db
          .collection('notificationtokens')
          .find({ userId })
          .sort({ _id: 1 })
          .toArray();

        const result = {
          callCount,
          logCount: logs.length,
          successLog: logs.find((l) =>
            l.tokenId && l.tokenId.equals(token1Id),
          ) || null,
          failureLog: logs.find((l) =>
            l.tokenId && l.tokenId.equals(token2Id),
          ) || null,
          tokens: tokens.map((t) => ({
            token: t.token,
            active: t.active,
            hasUnregisteredAt: Boolean(t.unregisteredAt),
          })),
        };

        process.stdout.write('RESULT:' + JSON.stringify(result));

        // Tear down connections so the child process exits — the worker's
        // jobRuntime opens an IORedis connection via withIdempotency which
        // would otherwise keep the event loop alive forever.
        const { shutdownJobRuntime } = require('../worker/src/utils/jobRuntime');
        apns.shutdownApnsClient();
        await shutdownJobRuntime();
        await mongoose.disconnect();
        await mongoServer.stop();
        process.exit(0);
      })().catch((err) => {
        process.stderr.write('ERR:' + (err && err.stack ? err.stack : err));
        process.exit(1);
      });
    `;

    const out = execFileSync(process.execPath, ['-r', 'tsx/cjs', '-e', script], {
      cwd: apiRoot,
      encoding: 'utf8',
      env: {
        ...process.env,
        APNS_AUTH_KEY: pem,
        APNS_KEY_ID: 'FU3NKNSKL8',
        APNS_TEAM_ID: 'TUZYDM227C',
      },
      timeout: 120000,
    });

    const marker = out.indexOf('RESULT:');
    expect(marker).toBeGreaterThanOrEqual(0);
    const parsed = JSON.parse(out.slice(marker + 'RESULT:'.length));

    expect(parsed.callCount).toBe(2);
    expect(parsed.logCount).toBe(2);

    expect(parsed.successLog).not.toBeNull();
    expect(parsed.successLog.failureReason).toBeNull();
    expect(parsed.successLog.deliveredAt).not.toBeNull();

    expect(parsed.failureLog).not.toBeNull();
    expect(parsed.failureLog.failureReason).toBe('BadDeviceToken');
    expect(parsed.failureLog.deliveredAt).toBeNull();

    const goodTok = parsed.tokens.find((t) => t.token === 'goodtoken');
    const badTok = parsed.tokens.find((t) => t.token === 'badtoken');
    expect(goodTok.active).toBe(true);
    expect(badTok.active).toBe(false);
    expect(badTok.hasUnregisteredAt).toBe(true);
  }, 90000);

  test('suppresses push when user has pushEnabled: false', () => {
    const script = `
      const mongoose = require('mongoose');
      const { MongoMemoryServer } = require('mongodb-memory-server');

      (async () => {
        const mongoServer = await MongoMemoryServer.create();
        await mongoose.connect(mongoServer.getUri(), { serverSelectionTimeoutMS: 15000 });

        const apns = require('../worker/src/utils/apnsClient');
        let callCount = 0;
        apns.__setApnsTransportForTests({
          async request() {
            callCount++;
            return { statusCode: 200, headers: {}, body: '' };
          },
        });

        const { processPushNotification } = require('../worker/src/jobs/pushNotification');

        const userId = new mongoose.Types.ObjectId();
        const db = mongoose.connection.db;
        await db.collection('users').insertOne({
          _id: userId,
          preferences: { pushEnabled: false },
        });
        await db.collection('notificationtokens').insertOne({
          userId,
          platform: 'ios',
          token: 'some',
          environment: 'production',
          active: true,
        });

        await processPushNotification({
          id: 'job-sup',
          data: {
            userId: userId.toString(),
            type: 'general',
            title: 't',
            body: 'b',
          },
        });

        const logs = await db.collection('notificationlogs').countDocuments({});
        process.stdout.write('RESULT:' + JSON.stringify({ callCount, logs }));

        const { shutdownJobRuntime } = require('../worker/src/utils/jobRuntime');
        apns.shutdownApnsClient();
        await shutdownJobRuntime();
        await mongoose.disconnect();
        await mongoServer.stop();
        process.exit(0);
      })().catch((err) => {
        process.stderr.write('ERR:' + (err && err.stack ? err.stack : err));
        process.exit(1);
      });
    `;

    const out = execFileSync(process.execPath, ['-r', 'tsx/cjs', '-e', script], {
      cwd: apiRoot,
      encoding: 'utf8',
      timeout: 120000,
    });

    const marker = out.indexOf('RESULT:');
    expect(marker).toBeGreaterThanOrEqual(0);
    const parsed = JSON.parse(out.slice(marker + 'RESULT:'.length));
    expect(parsed.callCount).toBe(0);
    expect(parsed.logs).toBe(0);
  }, 90000);
});
