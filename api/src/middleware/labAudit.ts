import type { Request, Response, NextFunction } from 'express';
import logger from '../utils/logger.js';
import { LabAuditLog } from '../models/LabAuditLog.js';
import type { JwtPayload } from './auth.js';

/**
 * labAuditMiddleware — HIPAA access log for /api/v1/labs/*.
 *
 * Responsibilities:
 *   1. Emit a structured log line per request via a dedicated Winston child
 *      logger (`logger: 'lab-audit'`) so downstream drains can isolate
 *      PHI-adjacent traffic.
 *   2. Persist an entry to the `lab_audit_logs` Mongo collection via the
 *      `LabAuditLog` model. Failures are swallowed — audit should never
 *      break a member-facing request.
 *
 * What we DO NOT log:
 *   - request bodies (may contain patient identity / DOB / email)
 *   - response bodies (may contain FHIR results — PHI)
 *   - error messages sent to clients (sanitized elsewhere)
 *
 * What we DO log: user id, method, route, ip, user-agent, status,
 * optional orderId from `req.params.orderId`, and request id.
 */

const AUDIT_LOGGER = logger.child({ logger: 'lab-audit' });

function resolveOrderId(req: Request): string | undefined {
  const fromParams = (req.params ?? {}) as Record<string, string | undefined>;
  return fromParams.orderId ?? fromParams.id;
}

function safeUserId(req: Request): string | undefined {
  const user = req.user as JwtPayload | undefined;
  return user?.sub;
}

/**
 * Persists an audit entry. Best-effort: logs + swallows on failure so a
 * misconfigured DB never blocks lab traffic.
 */
async function persistAuditEntry(payload: {
  userId?: string;
  route: string;
  method: string;
  orderId?: string;
  providerId?: string;
  ip?: string;
  userAgent?: string;
  statusCode?: number;
  requestId?: string;
}): Promise<void> {
  try {
    await LabAuditLog.create({
      ...payload,
      // Mongoose casts string to ObjectId when it's valid; otherwise it
      // throws — guard that specifically.
      userId: payload.userId && /^[a-f\d]{24}$/i.test(payload.userId)
        ? payload.userId
        : undefined,
    });
  } catch (err) {
    AUDIT_LOGGER.warn('lab audit persistence failed', {
      reason: (err as Error).message,
      route: payload.route,
      requestId: payload.requestId,
    });
  }
}

export function labAuditMiddleware(
  req: Request,
  res: Response,
  next: NextFunction,
): void {
  const startedAt = Date.now();
  const route = req.originalUrl ?? req.url;
  const method = req.method;
  const orderId = resolveOrderId(req);
  const userId = safeUserId(req);
  const ip = req.ip;
  const userAgent = req.get('user-agent') ?? undefined;
  const requestId = req.requestId;
  const providerId = (process.env.LAB_PROVIDER ?? 'rupa').trim().toLowerCase();

  // Fire the metadata-only log immediately so we record access even if
  // the response is never finished.
  AUDIT_LOGGER.info('lab access', {
    userId,
    route,
    method,
    orderId,
    providerId,
    ip,
    userAgent,
    requestId,
    phase: 'request',
  });

  res.on('finish', () => {
    const durationMs = Date.now() - startedAt;
    AUDIT_LOGGER.info('lab access', {
      userId,
      route,
      method,
      orderId,
      providerId,
      ip,
      userAgent,
      statusCode: res.statusCode,
      durationMs,
      requestId,
      phase: 'response',
    });

    void persistAuditEntry({
      userId,
      route,
      method,
      orderId,
      providerId,
      ip,
      userAgent,
      statusCode: res.statusCode,
      requestId,
    });
  });

  next();
}
