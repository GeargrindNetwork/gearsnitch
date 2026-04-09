import type { Response } from 'express';
import { StatusCodes } from 'http-status-codes';

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

export function errorResponse(
  res: Response,
  statusCode: number,
  message: string,
  details?: unknown,
): Response {
  const envelope: ApiEnvelope<null> = {
    success: false,
    data: null,
    error: {
      code: statusCode,
      message,
      ...(details !== undefined ? { details } : {}),
    },
  };
  return res.status(statusCode).json(envelope);
}
