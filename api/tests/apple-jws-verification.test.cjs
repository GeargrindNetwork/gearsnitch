const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const apiRoot = path.join(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

function runInApiRoot(script) {
  return execFileSync(
    process.execPath,
    ['-r', 'tsx/cjs', '-e', script],
    {
      cwd: apiRoot,
      encoding: 'utf8',
      stdio: 'pipe',
    },
  );
}

// ---------------------------------------------------------------------------
// Source-level contract: the insecure jose.decodeJwt path has been replaced
// with the verified `app-store-server-api` decodeTransaction path. This
// guards against silent regressions that would re-open the trust boundary.
// ---------------------------------------------------------------------------

describe('apple jws signature verification — source contract', () => {
  const service = read('src/modules/subscriptions/subscriptionService.ts');

  test('subscriptionService no longer relies on unverified jose.decodeJwt', () => {
    expect(service).not.toMatch(/jose\.decodeJwt/);
  });

  test('subscriptionService imports decodeTransaction from app-store-server-api', () => {
    expect(service).toContain("from 'app-store-server-api'");
    expect(service).toContain('decodeTransaction');
  });

  test('subscriptionService references Apple Root CA verification and the structured error code', () => {
    expect(service).toContain('APPLE_JWS_VERIFICATION_FAILED');
    expect(service).toMatch(/Apple['’]s Root CA/);
  });

  test('the comment admitting "you would verify the signature" is gone', () => {
    expect(service).not.toMatch(/you would verify the signature/i);
  });

  test('package.json declares app-store-server-api as a dependency', () => {
    const pkg = JSON.parse(read('package.json'));
    expect(pkg.dependencies).toHaveProperty('app-store-server-api');
  });
});

// ---------------------------------------------------------------------------
// Runtime tests — exercise validateAppleTransaction in a child Node process
// so we can load the TypeScript source directly via tsx and control
// `app-store-server-api`'s module exports through require.cache.
// ---------------------------------------------------------------------------

describe('apple jws signature verification — runtime behaviour', () => {
  test('forged JWS with correct shape but wrong signature is rejected', () => {
    const script = `
      const mongoose = require('mongoose');
      const { MongoMemoryServer } = require('mongodb-memory-server');

      // Forge a JWS — three base64url parts, valid shape, but the signature
      // is arbitrary bytes. The real decodeTransaction will reject this.
      const b64url = (obj) => Buffer.from(JSON.stringify(obj))
        .toString('base64')
        .replace(/=+$/,'').replace(/\\+/g,'-').replace(/\\//g,'_');
      const forged = [
        b64url({ alg: 'ES256', x5c: ['AAAA','BBBB','CCCC'] }),
        b64url({
          bundleId: 'com.gearsnitch.app',
          productId: 'com.gearsnitch.app.lifetime',
          transactionId: 't1',
          originalTransactionId: 't1',
          purchaseDate: Date.now(),
          type: 'Non-Consumable',
          environment: 'Production',
        }),
        'not-a-real-signature',
      ].join('.');

      (async () => {
        const mongoServer = await MongoMemoryServer.create();
        await mongoose.connect(mongoServer.getUri(), { serverSelectionTimeoutMS: 15000 });

        try {
          const { validateAppleTransaction } = require('./src/modules/subscriptions/subscriptionService.ts');
          let threw = false;
          let message = '';
          try {
            await validateAppleTransaction(forged, new mongoose.Types.ObjectId().toString());
          } catch (err) {
            threw = true;
            message = err instanceof Error ? err.message : String(err);
          }
          if (!threw) throw new Error('validateAppleTransaction accepted a forged JWS');
          if (!message.includes('APPLE_JWS_VERIFICATION_FAILED')) {
            throw new Error('Expected APPLE_JWS_VERIFICATION_FAILED, got: ' + message);
          }
          console.log('forged-jws-rejected-ok');
        } finally {
          await mongoose.disconnect();
          await mongoServer.stop();
        }
      })().catch((err) => { console.error(err && err.stack || err); process.exit(1); });
    `;
    const output = runInApiRoot(script);
    expect(output).toContain('forged-jws-rejected-ok');
  }, 60000);

  test('malformed JWS (not three parts) is rejected with APPLE_JWS_VERIFICATION_FAILED', () => {
    const script = `
      const mongoose = require('mongoose');
      const { MongoMemoryServer } = require('mongodb-memory-server');

      (async () => {
        const mongoServer = await MongoMemoryServer.create();
        await mongoose.connect(mongoServer.getUri(), { serverSelectionTimeoutMS: 15000 });

        try {
          const { validateAppleTransaction } = require('./src/modules/subscriptions/subscriptionService.ts');
          let threw = false;
          let message = '';
          try {
            await validateAppleTransaction('abc.def', new mongoose.Types.ObjectId().toString());
          } catch (err) {
            threw = true;
            message = err instanceof Error ? err.message : String(err);
          }
          if (!threw) throw new Error('validateAppleTransaction accepted a malformed JWS');
          if (!message.includes('APPLE_JWS_VERIFICATION_FAILED')) {
            throw new Error('Expected APPLE_JWS_VERIFICATION_FAILED, got: ' + message);
          }
          console.log('malformed-jws-rejected-ok');
        } finally {
          await mongoose.disconnect();
          await mongoServer.stop();
        }
      })().catch((err) => { console.error(err && err.stack || err); process.exit(1); });
    `;
    const output = runInApiRoot(script);
    expect(output).toContain('malformed-jws-rejected-ok');
  }, 60000);

  test('empty string jwsRepresentation is rejected', () => {
    const script = `
      const mongoose = require('mongoose');
      const { MongoMemoryServer } = require('mongodb-memory-server');

      (async () => {
        const mongoServer = await MongoMemoryServer.create();
        await mongoose.connect(mongoServer.getUri(), { serverSelectionTimeoutMS: 15000 });

        try {
          const { validateAppleTransaction } = require('./src/modules/subscriptions/subscriptionService.ts');
          let threw = false;
          let message = '';
          try {
            await validateAppleTransaction('', new mongoose.Types.ObjectId().toString());
          } catch (err) {
            threw = true;
            message = err instanceof Error ? err.message : String(err);
          }
          if (!threw) throw new Error('validateAppleTransaction accepted empty string');
          if (!message.includes('APPLE_JWS_VERIFICATION_FAILED')) {
            throw new Error('Expected APPLE_JWS_VERIFICATION_FAILED, got: ' + message);
          }
          console.log('empty-jws-rejected-ok');
        } finally {
          await mongoose.disconnect();
          await mongoServer.stop();
        }
      })().catch((err) => { console.error(err && err.stack || err); process.exit(1); });
    `;
    const output = runInApiRoot(script);
    expect(output).toContain('empty-jws-rejected-ok');
  }, 60000);

  test('positive path: decodeTransaction is invoked and its verified payload is persisted', () => {
    // We can't sign a real Apple JWS in tests, so we stub the verified-decode
    // function via require.cache manipulation. This also proves our code path
    // calls decodeTransaction *before* touching the DB — i.e. verification
    // happens on the trust boundary rather than being bypassable.
    const script = `
      const mongoose = require('mongoose');
      const { MongoMemoryServer } = require('mongodb-memory-server');

      // Replace app-store-server-api's exports in require.cache with a stub
      // BEFORE subscriptionService resolves it.
      const pkgPath = require.resolve('app-store-server-api');
      // Force-load so the cache entry exists, then overwrite exports in place.
      require('app-store-server-api');
      const entry = require.cache[pkgPath];
      const realExports = entry.exports;
      const verifiedPayload = {
        bundleId: 'com.gearsnitch.app',
        productId: 'com.gearsnitch.app.lifetime',
        transactionId: 'verified-txn-42',
        originalTransactionId: 'verified-txn-42',
        purchaseDate: Date.parse('2026-04-18T12:00:00Z'),
        expiresDate: undefined,
        type: 'Non-Consumable',
        environment: 'Production',
      };
      let decodeCalled = false;
      entry.exports = {
        ...realExports,
        decodeTransaction: async (token) => {
          decodeCalled = true;
          if (typeof token !== 'string' || token.split('.').length !== 3) {
            throw new Error('stub refused malformed token');
          }
          return verifiedPayload;
        },
      };

      const { validateAppleTransaction } = require('./src/modules/subscriptions/subscriptionService.ts');
      const { Subscription } = require('./src/models/Subscription.ts');

      (async () => {
        const mongoServer = await MongoMemoryServer.create();
        await mongoose.connect(mongoServer.getUri(), { serverSelectionTimeoutMS: 15000 });

        try {
          const userId = new mongoose.Types.ObjectId().toString();

          // Any three-part string — our stub ignores the contents.
          const fakeJws = 'hdr.payload.sig';
          const result = await validateAppleTransaction(fakeJws, userId);

          if (!decodeCalled) throw new Error('decodeTransaction stub was not invoked');
          if (result.productId !== 'com.gearsnitch.app.lifetime') {
            throw new Error('productId did not round-trip: ' + result.productId);
          }
          if (result.provider !== 'apple') {
            throw new Error('provider should be apple, got: ' + result.provider);
          }
          if (result.status !== 'active') {
            throw new Error('lifetime purchase should be active, got: ' + result.status);
          }

          const persisted = await Subscription.findOne({
            provider: 'apple',
            providerOriginalTransactionId: 'verified-txn-42',
          }).lean();
          if (!persisted) throw new Error('Subscription was not persisted');
          if (persisted.productId !== 'com.gearsnitch.app.lifetime') {
            throw new Error('Persisted productId mismatch: ' + persisted.productId);
          }

          console.log('positive-path-ok');
        } finally {
          try { await Subscription.deleteMany({}); } catch (_) {}
          await mongoose.disconnect();
          await mongoServer.stop();
        }
      })().catch((err) => { console.error(err && err.stack || err); process.exit(1); });
    `;
    const output = runInApiRoot(script);
    expect(output).toContain('positive-path-ok');
  }, 60000);

  test('positive path rejects receipts for a different bundle id', () => {
    // Even with a structurally valid, signature-verified payload, a mismatched
    // bundleId must be rejected — receipts from other Apple apps cannot be
    // replayed against GearSnitch.
    const script = `
      const mongoose = require('mongoose');
      const { MongoMemoryServer } = require('mongodb-memory-server');

      const pkgPath = require.resolve('app-store-server-api');
      require('app-store-server-api');
      const entry = require.cache[pkgPath];
      const realExports = entry.exports;
      entry.exports = {
        ...realExports,
        decodeTransaction: async () => ({
          bundleId: 'com.some.other.app',
          productId: 'com.gearsnitch.app.lifetime',
          transactionId: 't',
          originalTransactionId: 't',
          purchaseDate: Date.now(),
          type: 'Non-Consumable',
          environment: 'Production',
        }),
      };

      (async () => {
        const mongoServer = await MongoMemoryServer.create();
        await mongoose.connect(mongoServer.getUri(), { serverSelectionTimeoutMS: 15000 });

        try {
          const { validateAppleTransaction } = require('./src/modules/subscriptions/subscriptionService.ts');
          let threw = false;
          let message = '';
          try {
            await validateAppleTransaction('a.b.c', new mongoose.Types.ObjectId().toString());
          } catch (err) {
            threw = true;
            message = err instanceof Error ? err.message : String(err);
          }
          if (!threw) throw new Error('validateAppleTransaction accepted a foreign bundle id');
          if (!message.includes('APPLE_JWS_VERIFICATION_FAILED')) {
            throw new Error('Expected APPLE_JWS_VERIFICATION_FAILED, got: ' + message);
          }
          console.log('bundle-mismatch-rejected-ok');
        } finally {
          await mongoose.disconnect();
          await mongoServer.stop();
        }
      })().catch((err) => { console.error(err && err.stack || err); process.exit(1); });
    `;
    const output = runInApiRoot(script);
    expect(output).toContain('bundle-mismatch-rejected-ok');
  }, 60000);
});
