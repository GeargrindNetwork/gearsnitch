/**
 * APNs (Apple Push Notification service) client.
 *
 * Implementation notes
 * --------------------
 * - Uses Node's stdlib `http2` and `crypto` only — no new npm deps. This lets
 *   the worker image stay lean and lets both the api and worker workspaces
 *   share the same logic without dragging `jose` into the worker.
 * - Signs a short-lived ES256 JWT (cached, rotated before the 1h expiry that
 *   Apple enforces) using the `.p8` key that Cloud Run mounts into
 *   `APNS_AUTH_KEY` (PEM string, with literal `\n` sequences supported so the
 *   secret manager round-trip does not break the PEM).
 * - Selects the sandbox vs. production host per-call based on the token's
 *   registered environment (iOS debug builds issue sandbox tokens; TestFlight
 *   and App Store builds issue production tokens — they are NOT
 *   interchangeable).
 * - Handles the common Apple error reasons (`BadDeviceToken`,
 *   `Unregistered`, `PayloadTooLarge`, `TooManyRequests`) with the semantics
 *   downstream callers care about (mark dead, retry once, etc.).
 *
 * If `APNS_AUTH_KEY` is missing we degrade gracefully and return
 * `{ success: false, statusCode: 0, reason: 'APNS_NOT_CONFIGURED' }` — we do
 * NOT throw. This keeps the stack running on dev boxes and on Cloud Run
 * revisions that haven't picked up the secret yet.
 */

import crypto from 'node:crypto';
import http2 from 'node:http2';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type ApnsEnvironment = 'sandbox' | 'production';
export type ApnsPushType = 'alert' | 'background' | 'voip' | 'complication' | 'liveactivity';
export type ApnsPriority = 5 | 10;

export interface ApnsAlert {
  title?: string;
  subtitle?: string;
  body?: string;
  'title-loc-key'?: string;
  'loc-key'?: string;
}

export interface ApnsAps {
  alert?: ApnsAlert | string;
  badge?: number;
  sound?: string | { critical?: 0 | 1; name?: string; volume?: number };
  'thread-id'?: string;
  category?: string;
  'content-available'?: 0 | 1;
  'mutable-content'?: 0 | 1;
  'interruption-level'?: 'passive' | 'active' | 'time-sensitive' | 'critical';
  'relevance-score'?: number;
  [key: string]: unknown;
}

export interface ApnsPayload {
  aps: ApnsAps;
  [key: string]: unknown;
}

export interface SendApnsPushOptions {
  deviceToken: string;
  payload: ApnsPayload;
  environment: ApnsEnvironment;
  collapseId?: string;
  priority?: ApnsPriority;
  pushType?: ApnsPushType;
  /**
   * Override the default bundle id / topic (`com.gearsnitch.app`) — mostly
   * for tests.
   */
  topic?: string;
  /**
   * Override the expiration timestamp (seconds since epoch). Default is 0
   * ("send immediately, don't store").
   */
  expiration?: number;
}

export interface ApnsSendResult {
  success: boolean;
  apnsId?: string;
  statusCode: number;
  reason?: string;
  /** When Apple tells us the token is dead, this is the Unix seconds. */
  unregisteredAt?: number;
}

/**
 * Minimal HTTP/2 client surface used by the APNs client — isolated so tests
 * can swap it out without opening a real socket to Apple.
 */
export interface ApnsHttp2Transport {
  request(
    host: string,
    headers: Record<string, string | number>,
    body: string,
  ): Promise<{
    statusCode: number;
    headers: Record<string, string | string[] | undefined>;
    body: string;
  }>;
}

// ---------------------------------------------------------------------------
// Config & constants
// ---------------------------------------------------------------------------

export const APNS_SANDBOX_HOST = 'api.sandbox.push.apple.com';
export const APNS_PRODUCTION_HOST = 'api.push.apple.com';
export const APNS_PORT = 443;
export const APNS_DEFAULT_TOPIC = 'com.gearsnitch.app';

// Apple enforces a 1h JWT lifetime. We rotate every 50m to leave slack for
// clock skew + in-flight requests.
const JWT_LIFETIME_SECONDS = 50 * 60;

// Common Apple error reasons we need to act on. The full list is larger —
// anything not here just bubbles up as `reason` for callers to log.
export const APNS_REASON_BAD_DEVICE_TOKEN = 'BadDeviceToken';
export const APNS_REASON_UNREGISTERED = 'Unregistered';
export const APNS_REASON_PAYLOAD_TOO_LARGE = 'PayloadTooLarge';
export const APNS_REASON_TOO_MANY_REQUESTS = 'TooManyRequests';
export const APNS_REASON_NOT_CONFIGURED = 'APNS_NOT_CONFIGURED';

// ---------------------------------------------------------------------------
// JWT signing (ES256, pure stdlib)
// ---------------------------------------------------------------------------

interface CachedJwt {
  token: string;
  expiresAt: number; // epoch seconds
}

let cachedJwt: CachedJwt | null = null;

/**
 * Reset the cached JWT. Exposed for tests; also called automatically when
 * the key material changes between calls (shouldn't happen in prod but does
 * in tests that flip env vars).
 */
export function resetApnsJwtCache(): void {
  cachedJwt = null;
}

function base64UrlEncode(buf: Buffer | string): string {
  return (typeof buf === 'string' ? Buffer.from(buf) : buf)
    .toString('base64')
    .replace(/=+$/u, '')
    .replace(/\+/gu, '-')
    .replace(/\//gu, '_');
}

/**
 * Convert an ECDSA signature from ASN.1/DER (which `crypto.sign` emits) to
 * the fixed-length r||s concatenation JWS requires (JOSE spec). For P-256
 * that's exactly 64 bytes.
 */
function derToJose(der: Buffer): Buffer {
  // DER: 0x30 len 0x02 rLen r 0x02 sLen s
  if (der[0] !== 0x30) {
    throw new Error('Invalid ECDSA signature: expected DER sequence');
  }

  let offset = 2;
  if (der[1] & 0x80) {
    // long-form length — shouldn't happen for P-256 (sig <= ~72 bytes)
    offset = 2 + (der[1] & 0x7f);
  }

  if (der[offset] !== 0x02) {
    throw new Error('Invalid ECDSA signature: expected integer marker for r');
  }
  const rLen = der[offset + 1];
  const rStart = offset + 2;
  let r = der.subarray(rStart, rStart + rLen);

  const sOffset = rStart + rLen;
  if (der[sOffset] !== 0x02) {
    throw new Error('Invalid ECDSA signature: expected integer marker for s');
  }
  const sLen = der[sOffset + 1];
  const sStart = sOffset + 2;
  let s = der.subarray(sStart, sStart + sLen);

  // Strip leading zero bytes (DER encodes positive integers with a 0x00
  // prefix if the high bit would otherwise be set).
  while (r.length > 32 && r[0] === 0x00) r = r.subarray(1);
  while (s.length > 32 && s[0] === 0x00) s = s.subarray(1);

  if (r.length > 32 || s.length > 32) {
    throw new Error('Invalid ECDSA signature: r or s exceeds 32 bytes');
  }

  // Left-pad to 32 bytes.
  const rPadded = Buffer.concat([Buffer.alloc(32 - r.length), r]);
  const sPadded = Buffer.concat([Buffer.alloc(32 - s.length), s]);
  return Buffer.concat([rPadded, sPadded]);
}

/**
 * Normalise the PEM string. Google Secret Manager sometimes round-trips
 * newlines as literal `\n` sequences; accept both.
 */
function normalizePem(raw: string): string {
  const trimmed = raw.trim();
  if (trimmed.includes('-----BEGIN') && trimmed.includes('\n')) {
    return trimmed;
  }
  return trimmed.replace(/\\n/gu, '\n');
}

/**
 * Sign an APNs-flavoured ES256 JWT. Pure-stdlib implementation — does not
 * require `jose`.
 */
export function signApnsJwt(params: {
  pem: string;
  keyId: string;
  teamId: string;
  issuedAt?: number;
}): string {
  const issuedAt = params.issuedAt ?? Math.floor(Date.now() / 1000);
  const header = { alg: 'ES256', kid: params.keyId, typ: 'JWT' };
  const claims = { iss: params.teamId, iat: issuedAt };

  const encodedHeader = base64UrlEncode(JSON.stringify(header));
  const encodedClaims = base64UrlEncode(JSON.stringify(claims));
  const signingInput = `${encodedHeader}.${encodedClaims}`;

  const privateKey = crypto.createPrivateKey({
    key: normalizePem(params.pem),
    format: 'pem',
  });

  const derSignature = crypto.sign('sha256', Buffer.from(signingInput), {
    key: privateKey,
    dsaEncoding: 'der',
  });
  const joseSignature = derToJose(derSignature);

  return `${signingInput}.${base64UrlEncode(joseSignature)}`;
}

function getApnsJwt(): string | null {
  const pem = process.env.APNS_AUTH_KEY;
  const keyId = process.env.APNS_KEY_ID;
  const teamId = process.env.APNS_TEAM_ID;

  if (!pem || !keyId || !teamId) {
    return null;
  }

  const now = Math.floor(Date.now() / 1000);
  if (cachedJwt && cachedJwt.expiresAt > now + 60) {
    return cachedJwt.token;
  }

  const token = signApnsJwt({ pem, keyId, teamId, issuedAt: now });
  cachedJwt = { token, expiresAt: now + JWT_LIFETIME_SECONDS };
  return token;
}

// ---------------------------------------------------------------------------
// HTTP/2 transport (real + mockable)
// ---------------------------------------------------------------------------

class Http2Transport implements ApnsHttp2Transport {
  private sessions = new Map<string, http2.ClientHttp2Session>();

  private getSession(host: string): http2.ClientHttp2Session {
    const existing = this.sessions.get(host);
    if (existing && !existing.closed && !existing.destroyed) {
      return existing;
    }

    const session = http2.connect(`https://${host}:${APNS_PORT}`);
    session.on('error', () => {
      // Socket errors drop the session so the next call reconnects.
      this.sessions.delete(host);
    });
    session.on('close', () => {
      this.sessions.delete(host);
    });
    this.sessions.set(host, session);
    return session;
  }

  request(
    host: string,
    headers: Record<string, string | number>,
    body: string,
  ): Promise<{
    statusCode: number;
    headers: Record<string, string | string[] | undefined>;
    body: string;
  }> {
    return new Promise((resolve, reject) => {
      const session = this.getSession(host);
      const stream = session.request({
        ':method': 'POST',
        ...headers,
      });

      let responseHeaders: Record<string, string | string[] | undefined> = {};
      const chunks: Buffer[] = [];

      stream.on('response', (h) => {
        responseHeaders = h as Record<string, string | string[] | undefined>;
      });
      stream.on('data', (chunk) => {
        chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
      });
      stream.on('end', () => {
        const statusCode = Number(responseHeaders[':status']) || 0;
        resolve({
          statusCode,
          headers: responseHeaders,
          body: Buffer.concat(chunks).toString('utf8'),
        });
      });
      stream.on('error', (error) => {
        reject(error);
      });

      stream.setEncoding('utf8');
      stream.end(body);
    });
  }

  close(): void {
    for (const session of this.sessions.values()) {
      try {
        session.close();
      } catch {
        // ignore — we're tearing down anyway
      }
    }
    this.sessions.clear();
  }
}

let defaultTransport: Http2Transport | null = null;
let transportOverride: ApnsHttp2Transport | null = null;

/**
 * Swap the HTTP/2 transport for testing. Pass `null` to restore the real one.
 */
export function __setApnsTransportForTests(t: ApnsHttp2Transport | null): void {
  transportOverride = t;
}

function getTransport(): ApnsHttp2Transport {
  if (transportOverride) return transportOverride;
  if (!defaultTransport) defaultTransport = new Http2Transport();
  return defaultTransport;
}

/**
 * Shut down any open HTTP/2 sessions. Call from graceful-shutdown paths
 * (worker SIGTERM, test teardown) to stop Node keeping the event loop alive.
 */
export function shutdownApnsClient(): void {
  if (defaultTransport) {
    defaultTransport.close();
    defaultTransport = null;
  }
  cachedJwt = null;
}

// ---------------------------------------------------------------------------
// Logging — we avoid hard-importing winston so this module stays usable
// from worker (which has its own winston instance) and tests without
// pulling in api's logger config.
// ---------------------------------------------------------------------------

type MinimalLogger = {
  warn: (msg: string, meta?: Record<string, unknown>) => void;
  error: (msg: string, meta?: Record<string, unknown>) => void;
  info?: (msg: string, meta?: Record<string, unknown>) => void;
};

let logger: MinimalLogger = {
  warn: (msg, meta) => {
    // eslint-disable-next-line no-console -- fallback only when no logger injected
    console.warn(msg, meta ?? {});
  },
  error: (msg, meta) => {
    // eslint-disable-next-line no-console -- fallback only when no logger injected
    console.error(msg, meta ?? {});
  },
};

export function setApnsLogger(l: MinimalLogger): void {
  logger = l;
}

// ---------------------------------------------------------------------------
// Main send API
// ---------------------------------------------------------------------------

function hostForEnvironment(env: ApnsEnvironment): string {
  return env === 'production' ? APNS_PRODUCTION_HOST : APNS_SANDBOX_HOST;
}

function parseReason(rawBody: string, headers: Record<string, string | string[] | undefined>): {
  reason?: string;
  unregisteredAt?: number;
} {
  const apnsId =
    typeof headers['apns-id'] === 'string' ? (headers['apns-id'] as string) : undefined;
  void apnsId;

  if (!rawBody) return {};
  try {
    const parsed = JSON.parse(rawBody) as { reason?: string; timestamp?: number };
    return {
      reason: parsed.reason,
      unregisteredAt: typeof parsed.timestamp === 'number' ? parsed.timestamp : undefined,
    };
  } catch {
    return {};
  }
}

function readApnsId(headers: Record<string, string | string[] | undefined>): string | undefined {
  const id = headers['apns-id'];
  return typeof id === 'string' ? id : Array.isArray(id) ? id[0] : undefined;
}

async function singleSend(options: SendApnsPushOptions & { jwt: string }): Promise<ApnsSendResult> {
  const topic = options.topic ?? process.env.APNS_BUNDLE_ID ?? APNS_DEFAULT_TOPIC;
  const host = hostForEnvironment(options.environment);
  const body = JSON.stringify(options.payload);

  const headers: Record<string, string | number> = {
    ':path': `/3/device/${options.deviceToken}`,
    ':scheme': 'https',
    ':authority': host,
    'apns-topic': topic,
    'apns-push-type': options.pushType ?? 'alert',
    'apns-expiration': String(options.expiration ?? 0),
    'apns-priority': String(options.priority ?? 10),
    authorization: `bearer ${options.jwt}`,
    'content-type': 'application/json',
    'content-length': Buffer.byteLength(body),
  };

  if (options.collapseId) {
    headers['apns-collapse-id'] = options.collapseId;
  }

  const response = await getTransport().request(host, headers, body);
  const apnsId = readApnsId(response.headers);

  if (response.statusCode === 200) {
    return {
      success: true,
      statusCode: 200,
      apnsId,
    };
  }

  const { reason, unregisteredAt } = parseReason(response.body, response.headers);
  return {
    success: false,
    statusCode: response.statusCode,
    apnsId,
    reason,
    unregisteredAt,
  };
}

/**
 * Send a push to a single device token. Returns a structured result — never
 * throws for "normal" Apple errors. Only unexpected I/O or key-parsing
 * failures surface as rejected promises, and those get logged here first.
 */
export async function sendAPNsPush(options: SendApnsPushOptions): Promise<ApnsSendResult> {
  const jwt = getApnsJwt();
  if (!jwt) {
    logger.warn('APNs client called without APNS_AUTH_KEY/KEY_ID/TEAM_ID — push skipped', {
      hasKey: Boolean(process.env.APNS_AUTH_KEY),
      hasKeyId: Boolean(process.env.APNS_KEY_ID),
      hasTeamId: Boolean(process.env.APNS_TEAM_ID),
      environment: options.environment,
    });
    return {
      success: false,
      statusCode: 0,
      reason: APNS_REASON_NOT_CONFIGURED,
    };
  }

  try {
    const first = await singleSend({ ...options, jwt });

    // Retry once on 429 TooManyRequests. We backoff briefly so a hot loop
    // doesn't hammer Apple — Apple documents this as the correct handling.
    if (first.statusCode === 429 || first.reason === APNS_REASON_TOO_MANY_REQUESTS) {
      await new Promise((resolve) => setTimeout(resolve, 500));
      const second = await singleSend({ ...options, jwt });
      return second;
    }

    if (first.reason === APNS_REASON_PAYLOAD_TOO_LARGE) {
      logger.error('APNs rejected payload: PayloadTooLarge', {
        deviceToken: options.deviceToken.slice(0, 8) + '…',
        payloadBytes: Buffer.byteLength(JSON.stringify(options.payload)),
      });
    }

    return first;
  } catch (error) {
    logger.error('APNs send failed with unexpected error', {
      error: error instanceof Error ? error.message : String(error),
      environment: options.environment,
    });
    return {
      success: false,
      statusCode: 0,
      reason: error instanceof Error ? error.message : 'APNS_TRANSPORT_ERROR',
    };
  }
}

/**
 * True once the three secrets are present. Useful for health checks.
 */
export function isApnsConfigured(): boolean {
  return Boolean(
    process.env.APNS_AUTH_KEY && process.env.APNS_KEY_ID && process.env.APNS_TEAM_ID,
  );
}
