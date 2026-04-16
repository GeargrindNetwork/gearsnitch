import type { Response } from 'express';
import { StatusCodes } from 'http-status-codes';
import config from '../config/index.js';

export interface ApiEnvelope<T = unknown> {
  success: boolean;
  data: T | null;
  meta?: Record<string, unknown>;
  error?: {
    code: number;
    message: string;
    details?: unknown;
  };
}

export function successResponse<T>(
  res: Response,
  data: T,
  statusCode: number = StatusCodes.OK,
  meta?: Record<string, unknown>,
): Response {
  const envelope: ApiEnvelope<T> = {
    success: true,
    data,
    ...(meta ? { meta } : {}),
  };
  return res.status(statusCode).json(envelope);
}

/**
 * Error details are only included in the response in non-production environments
 * to prevent leaking internal error messages, stack traces, or sensitive data
 * to clients. In production, details are logged server-side but not returned.
 */
export function errorResponse(
  res: Response,
  statusCode: number,
  message: string,
  details?: unknown,
): Response {
  const includeDetails = !config.isProduction && details !== undefined;
  const envelope: ApiEnvelope<null> = {
    success: false,
    data: null,
    error: {
      code: statusCode,
      message,
      ...(includeDetails ? { details } : {}),
    },
  };
  return res.status(statusCode).json(envelope);
}
