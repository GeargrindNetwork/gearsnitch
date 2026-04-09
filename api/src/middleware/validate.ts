import type { Request, Response, NextFunction } from 'express';
import { type AnyZodObject, type ZodError, ZodSchema } from 'zod';
import { StatusCodes } from 'http-status-codes';
import { errorResponse } from '../utils/response.js';

export function validateResource(schema: AnyZodObject) {
  return (req: Request, res: Response, next: NextFunction): void => {
    try {
      schema.parse({
        body: req.body,
        query: req.query,
        params: req.params,
      });
      next();
    } catch (err) {
      const zodError = err as ZodError;
      const details = zodError.errors.map((e) => ({
        path: e.path.join('.'),
        message: e.message,
      }));

      errorResponse(res, StatusCodes.BAD_REQUEST, 'Validation failed', details);
    }
  };
}

export function validateBody(schema: ZodSchema) {
  return (req: Request, res: Response, next: NextFunction): void => {
    const result = schema.safeParse(req.body);
    if (!result.success) {
      const details = result.error.errors.map((e) => ({
        path: e.path.join('.'),
        message: e.message,
      }));
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Validation failed', details);
      return;
    }
    req.body = result.data;
    next();
  };
}
