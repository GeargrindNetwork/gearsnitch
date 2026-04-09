import type { Request, Response, NextFunction } from 'express';
import { StatusCodes } from 'http-status-codes';
import logger from '../utils/logger.js';
import type { ApiEnvelope } from '../utils/response.js';

export class AppError extends Error {
  public readonly statusCode: number;
  public readonly details?: unknown;

  constructor(statusCode: number, message: string, details?: unknown) {
    super(message);
    this.statusCode = statusCode;
    this.details = details;
    this.name = 'AppError';
    Error.captureStackTrace(this, this.constructor);
  }
}

export function errorHandler(
  err: Error,
  req: Request,
  res: Response,
  _next: NextFunction,
): void {
  const requestId = req.requestId ?? 'unknown';

  if (err instanceof AppError) {
    logger.warn('Application error', {
      correlationId: requestId,
      statusCode: err.statusCode,
      message: err.message,
      path: req.path,
    });

    const envelope: ApiEnvelope<null> = {
      success: false,
      data: null,
      error: {
        code: err.statusCode,
        message: err.message,
        ...(err.details !== undefined ? { details: err.details } : {}),
      },
    };

    res.status(err.statusCode).json(envelope);
    return;
  }

  // Unexpected error
  logger.error('Unhandled error', {
    correlationId: requestId,
    error: err.message,
    stack: err.stack,
    path: req.path,
    method: req.method,
  });

  const envelope: ApiEnvelope<null> = {
    success: false,
    data: null,
    error: {
      code: StatusCodes.INTERNAL_SERVER_ERROR,
      message: 'Internal server error',
    },
  };

  res.status(StatusCodes.INTERNAL_SERVER_ERROR).json(envelope);
}
