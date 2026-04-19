/**
 * Unit tests for api/src/services/apnsClient.ts.
 *
 * Runs the TypeScript source directly via tsx/cjs — same pattern as
 * apple-jws-verification.test.cjs. Uses a child Node process so we can
 * swap env vars and the HTTP/2 transport without leaking state between
 * tests.
 */

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');

const apiRoot = path.join(__dirname, '..');
const repoRoot = path.join(apiRoot, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

function runInApiRoot(script) {
  return execFileSync(process.execPath, ['-r', 'tsx/cjs', '-e', script], {
    cwd: apiRoot,
    encoding: 'utf8',
    stdio: 'pipe',
  });
}

// ---------------------------------------------------------------------------
// Source-level contract: keep the invariants the reviewer cares about
// pinned so future refactors cannot silently strip them.
// ---------------------------------------------------------------------------

describe('apnsClient — source contract', () => {
  const client = read('src/services/apnsClient.ts');
  const workerClient = fs.readFileSync(
    path.join(repoRoot, 'worker/src/utils/apnsClient.ts'),
    'utf8',
  );

  test('uses stdlib http2 + crypto (no new npm deps)', () => {
    expect(client).toContain("from 'node:http2'");
    expect(client).toContain("from 'node:crypto'");
    expect(workerClient).toContain("from 'node:http2'");
    expect(workerClient).toContain("from 'node:crypto'");
  });

  test('signs ES256 JWT with the required claims/headers', () => {
    expect(client).toContain("alg: 'ES256'");
    expect(client).toContain('kid: params.keyId');
    expect(client).toContain('iss: params.teamId');
    expect(client).toContain('iat: issuedAt');
  });

  test('exports sandbox + production hosts', () => {
    expect(client).toContain('api.sandbox.push.apple.com');
    expect(client).toContain('api.push.apple.com');
    expect(workerClient).toContain('api.sandbox.push.apple.com');
    expect(workerClient).toContain('api.push.apple.com');
  });

  test('defaults apns-topic to com.gearsnitch.app', () => {
    expect(client).toContain("APNS_DEFAULT_TOPIC = 'com.gearsnitch.app'");
    expect(workerClient).toContain("APNS_DEFAULT_TOPIC = 'com.gearsnitch.app'");
  });

  test('handles the four Apple error reasons the spec calls out', () => {
    expect(client).toContain("APNS_REASON_BAD_DEVICE_TOKEN = 'BadDeviceToken'");
    expect(client).toContain("APNS_REASON_UNREGISTERED = 'Unregistered'");
    expect(client).toContain("APNS_REASON_PAYLOAD_TOO_LARGE = 'PayloadTooLarge'");
    expect(client).toContain("APNS_REASON_TOO_MANY_REQUESTS = 'TooManyRequests'");
  });

  test('graceful-degradation contract: no throw when env missing', () => {
    expect(client).toContain("APNS_REASON_NOT_CONFIGURED = 'APNS_NOT_CONFIGURED'");
    expect(client).toContain("reason: APNS_REASON_NOT_CONFIGURED");
    // sendAPNsPush must not re-throw on missing env — it returns.
    expect(client).toMatch(/if \(!jwt\) \{[\s\S]*?return \{/);
  });

  test('retries once on TooManyRequests/429', () => {
    expect(client).toMatch(/TooManyRequests|statusCode === 429/);
    expect(client).toContain('setTimeout');
  });
});

// ---------------------------------------------------------------------------
// Runtime: JWT signing produces a valid ES256 token.
//
// We generate a fresh P-256 keypair in this parent process, pass it to a
// child tsx/cjs process via env vars, have the child sign a JWT, then
// verify the signature back here with the matching public key.
// ---------------------------------------------------------------------------

describe('apnsClient — JWT signing runtime', () => {
  function generateP256() {
    const { publicKey, privateKey } = crypto.generateKeyPairSync('ec', {
      namedCurve: 'P-256',
    });
    return {
      publicPem: publicKey.export({ type: 'spki', format: 'pem' }),
      privatePem: privateKey.export({ type: 'pkcs8', format: 'pem' }),
    };
  }

  function base64UrlDecode(s) {
    const padded = s + '==='.slice((s.length + 3) % 4);
    return Buffer.from(padded.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
  }

  function verifyEs256(jwt, publicPem) {
    const [h, c, sig] = jwt.split('.');
    const signingInput = `${h}.${c}`;
    const rawSig = base64UrlDecode(sig);
    if (rawSig.length !== 64) {
      throw new Error(`Expected 64-byte JWS signature, got ${rawSig.length}`);
    }
    // Convert jose (r||s) back to DER for crypto.verify.
    const r = rawSig.subarray(0, 32);
    const s = rawSig.subarray(32, 64);
    const trim = (buf) => {
      let i = 0;
      while (i < buf.length - 1 && buf[i] === 0x00) i++;
      let out = buf.subarray(i);
      if (out[0] & 0x80) out = Buffer.concat([Buffer.from([0x00]), out]);
      return out;
    };
    const rDer = trim(r);
    const sDer = trim(s);
    const seq = Buffer.concat([
      Buffer.from([0x02, rDer.length]),
      rDer,
      Buffer.from([0x02, sDer.length]),
      sDer,
    ]);
    const der = Buffer.concat([Buffer.from([0x30, seq.length]), seq]);

    return crypto.verify(
      'sha256',
      Buffer.from(signingInput),
      { key: publicPem, dsaEncoding: 'der' },
      der,
    );
  }

  test('signApnsJwt produces a verifiable ES256 token with correct claims', () => {
    const { publicPem, privatePem } = generateP256();

    const script = `
      const { signApnsJwt } = require('./src/services/apnsClient');
      const pem = process.env.APNS_AUTH_KEY;
      const jwt = signApnsJwt({
        pem,
        keyId: process.env.APNS_KEY_ID,
        teamId: process.env.APNS_TEAM_ID,
        issuedAt: 1700000000,
      });
      process.stdout.write(jwt);
    `;

    const jwt = execFileSync(process.execPath, ['-r', 'tsx/cjs', '-e', script], {
      cwd: apiRoot,
      encoding: 'utf8',
      env: {
        ...process.env,
        APNS_AUTH_KEY: privatePem,
        APNS_KEY_ID: 'FU3NKNSKL8',
        APNS_TEAM_ID: 'TUZYDM227C',
      },
    });

    expect(typeof jwt).toBe('string');
    expect(jwt.split('.').length).toBe(3);

    const [encodedHeader, encodedClaims] = jwt.split('.');
    const header = JSON.parse(base64UrlDecode(encodedHeader).toString('utf8'));
    const claims = JSON.parse(base64UrlDecode(encodedClaims).toString('utf8'));

    expect(header).toEqual({ alg: 'ES256', kid: 'FU3NKNSKL8', typ: 'JWT' });
    expect(claims).toEqual({ iss: 'TUZYDM227C', iat: 1700000000 });

    expect(verifyEs256(jwt, publicPem)).toBe(true);
  });

  test('accepts PEM with literal \\n (Secret Manager round-trip)', () => {
    const { privatePem } = generateP256();
    const escaped = privatePem.replace(/\n/g, '\\n');

    const script = `
      const { signApnsJwt } = require('./src/services/apnsClient');
      const jwt = signApnsJwt({
        pem: process.env.APNS_AUTH_KEY,
        keyId: 'K',
        teamId: 'T',
        issuedAt: 1,
      });
      process.stdout.write(jwt.split('.').length.toString());
    `;

    const out = execFileSync(process.execPath, ['-r', 'tsx/cjs', '-e', script], {
      cwd: apiRoot,
      encoding: 'utf8',
      env: { ...process.env, APNS_AUTH_KEY: escaped },
    });

    expect(out).toBe('3');
  });
});

// ---------------------------------------------------------------------------
// Runtime: sendAPNsPush behaviour with a mocked HTTP/2 transport.
// ---------------------------------------------------------------------------

describe('apnsClient — send behaviour (mocked transport)', () => {
  function runSend({ env, transportScript, optionsScript }) {
    const script = `
      const { sendAPNsPush, __setApnsTransportForTests, resetApnsJwtCache } =
        require('./src/services/apnsClient');
      resetApnsJwtCache();
      ${transportScript}
      (async () => {
        const result = await sendAPNsPush(${optionsScript});
        process.stdout.write(JSON.stringify(result));
      })().catch((err) => {
        process.stderr.write('REJECTED:' + err.message);
        process.exit(1);
      });
    `;

    return execFileSync(process.execPath, ['-r', 'tsx/cjs', '-e', script], {
      cwd: apiRoot,
      encoding: 'utf8',
      env: { ...process.env, ...env },
    });
  }

  test('returns APNS_NOT_CONFIGURED without throwing when env missing', () => {
    const script = `
      const { sendAPNsPush, resetApnsJwtCache } = require('./src/services/apnsClient');
      resetApnsJwtCache();
      (async () => {
        const result = await sendAPNsPush({
          deviceToken: 'abc',
          payload: { aps: { alert: { title: 't', body: 'b' } } },
          environment: 'sandbox',
        });
        process.stdout.write(JSON.stringify(result));
      })();
    `;

    const out = execFileSync(process.execPath, ['-r', 'tsx/cjs', '-e', script], {
      cwd: apiRoot,
      encoding: 'utf8',
      env: {
        ...process.env,
        // Wipe any inherited values.
        APNS_AUTH_KEY: '',
        APNS_KEY_ID: '',
        APNS_TEAM_ID: '',
      },
    });

    const parsed = JSON.parse(out);
    expect(parsed).toEqual({
      success: false,
      statusCode: 0,
      reason: 'APNS_NOT_CONFIGURED',
    });
  });

  test('maps BadDeviceToken response to { success: false, reason: BadDeviceToken }', () => {
    const { privateKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'P-256' });
    const pem = privateKey.export({ type: 'pkcs8', format: 'pem' });

    const transportScript = `
      __setApnsTransportForTests({
        async request(host, headers, body) {
          return {
            statusCode: 400,
            headers: { 'apns-id': 'apns-id-123' },
            body: JSON.stringify({ reason: 'BadDeviceToken' }),
          };
        },
      });
    `;

    const out = runSend({
      env: {
        APNS_AUTH_KEY: pem,
        APNS_KEY_ID: 'FU3NKNSKL8',
        APNS_TEAM_ID: 'TUZYDM227C',
      },
      transportScript,
      optionsScript: `{
        deviceToken: 'deadbeef',
        payload: { aps: { alert: { title: 't', body: 'b' } } },
        environment: 'production',
      }`,
    });

    const parsed = JSON.parse(out);
    expect(parsed.success).toBe(false);
    expect(parsed.statusCode).toBe(400);
    expect(parsed.reason).toBe('BadDeviceToken');
    expect(parsed.apnsId).toBe('apns-id-123');
  });

  test('returns success: true with apnsId on 200', () => {
    const { privateKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'P-256' });
    const pem = privateKey.export({ type: 'pkcs8', format: 'pem' });

    const transportScript = `
      __setApnsTransportForTests({
        async request(host, headers, body) {
          if (host !== 'api.push.apple.com') {
            throw new Error('expected production host, got ' + host);
          }
          if (headers['apns-topic'] !== 'com.gearsnitch.app') {
            throw new Error('unexpected topic: ' + headers['apns-topic']);
          }
          if (!String(headers['authorization']).startsWith('bearer ')) {
            throw new Error('missing bearer auth header');
          }
          return {
            statusCode: 200,
            headers: { 'apns-id': 'good-id' },
            body: '',
          };
        },
      });
    `;

    const out = runSend({
      env: {
        APNS_AUTH_KEY: pem,
        APNS_KEY_ID: 'FU3NKNSKL8',
        APNS_TEAM_ID: 'TUZYDM227C',
      },
      transportScript,
      optionsScript: `{
        deviceToken: 'abcd',
        payload: { aps: { alert: { title: 'Hello', body: 'World' } } },
        environment: 'production',
      }`,
    });

    const parsed = JSON.parse(out);
    expect(parsed).toEqual({
      success: true,
      statusCode: 200,
      apnsId: 'good-id',
    });
  });

  test('retries once on TooManyRequests then returns the retry result', () => {
    const { privateKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'P-256' });
    const pem = privateKey.export({ type: 'pkcs8', format: 'pem' });

    const transportScript = `
      let calls = 0;
      __setApnsTransportForTests({
        async request(host, headers, body) {
          calls++;
          if (calls === 1) {
            return {
              statusCode: 429,
              headers: {},
              body: JSON.stringify({ reason: 'TooManyRequests' }),
            };
          }
          return {
            statusCode: 200,
            headers: { 'apns-id': 'retry-ok' },
            body: '',
          };
        },
      });
    `;

    const out = runSend({
      env: {
        APNS_AUTH_KEY: pem,
        APNS_KEY_ID: 'FU3NKNSKL8',
        APNS_TEAM_ID: 'TUZYDM227C',
      },
      transportScript,
      optionsScript: `{
        deviceToken: 'x',
        payload: { aps: { alert: { title: 'a', body: 'b' } } },
        environment: 'sandbox',
      }`,
    });

    const parsed = JSON.parse(out);
    expect(parsed.success).toBe(true);
    expect(parsed.apnsId).toBe('retry-ok');
  });
});
