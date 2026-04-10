import type { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { StatusCodes } from 'http-status-codes';
import { errorResponse } from '../utils/response.js';
import { getRedisClient } from '../loaders/redis.js';
import config from '../config/index.js';

export interface JwtPayload {
  sub: string;
  jti: string;
  email: string;
  role: string;
  scope: string[];
  iat: number;
  exp: number;
}

declare global {
  namespace Express {
    interface Request {
      user?: JwtPayload;
    }
  }
}

function extractToken(req: Request): string | null {
  const authHeader = req.headers.authorization;
  if (authHeader?.startsWith('Bearer ')) {
    return authHeader.slice(7);
  }
  return null;
}

export async function isAuthenticated(
  req: Request,
  res: Response,
  next: NextFunction,
): Promise<void> {
  const token = extractToken(req);
  if (!token) {
    errorResponse(res, StatusCodes.UNAUTHORIZED, 'Authentication required');
    return;
  }

  try {
    const signingKey = config.isProduction ? config.jwtPublicKey : config.jwtPrivateKey;
    if (!signingKey) {
      errorResponse(res, StatusCodes.INTERNAL_SERVER_ERROR, 'JWT signing key not configured');
      return;
    }

    const algorithm = config.isProduction ? 'RS256' : 'HS256';
    const decoded = jwt.verify(token, signingKey, {
      algorithms: [algorithm],
    }) as JwtPayload;

    // Check Redis whitelist — token must be present in active sessions
    const redis = getRedisClient();
    const sessionKey = `session:${decoded.sub}:${decoded.jti}`;
    const sessionExists = await redis.exists(sessionKey);
    if (!sessionExists) {
      errorResponse(res, StatusCodes.UNAUTHORIZED, 'Session expired or revoked');
      return;
    }

    req.user = decoded;
    next();
  } catch (err) {
    if (err instanceof jwt.TokenExpiredError) {
      errorResponse(res, StatusCodes.UNAUTHORIZED, 'Token expired');
      return;
    }
    if (err instanceof jwt.JsonWebTokenError) {
      errorResponse(res, StatusCodes.UNAUTHORIZED, 'Invalid token');
      return;
    }
    errorResponse(res, StatusCodes.INTERNAL_SERVER_ERROR, 'Authentication error');
  }
}

export function hasRole(roles: string[]) {
  return (req: Request, res: Response, next: NextFunction): void => {
    if (!req.user) {
      errorResponse(res, StatusCodes.UNAUTHORIZED, 'Authentication required');
      return;
    }

    if (!roles.includes(req.user.role)) {
      errorResponse(res, StatusCodes.FORBIDDEN, 'Insufficient role');
      return;
    }

    next();
  };
}

export function enforceScope(requiredScopes: string[]) {
  return (req: Request, res: Response, next: NextFunction): void => {
    if (!req.user) {
      errorResponse(res, StatusCodes.UNAUTHORIZED, 'Authentication required');
      return;
    }

    const userScopes = req.user.scope ?? [];
    const hasAllScopes = requiredScopes.every((s) => userScopes.includes(s));

    if (!hasAllScopes) {
      errorResponse(res, StatusCodes.FORBIDDEN, 'Insufficient scope');
      return;
    }

    next();
  };
}
