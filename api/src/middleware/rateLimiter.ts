import rateLimit from 'express-rate-limit';
import RedisStore from 'rate-limit-redis';
import { getRedisClient } from '../loaders/redis.js';
import logger from '../utils/logger.js';

export function createRateLimiter(
  windowMs: number = 15 * 60 * 1000,
  max: number = 100,
  prefix: string = 'rl:',
) {
  let store: RedisStore | undefined;

  try {
    const redis = getRedisClient();
    store = new RedisStore({
      sendCommand: ((...args: string[]) => redis.call(args[0], ...args.slice(1))) as never,
      prefix,
    });
  } catch {
    logger.warn('Redis not available for rate limiter — falling back to memory store');
  }

  return rateLimit({
    windowMs,
    max,
    standardHeaders: true,
    legacyHeaders: false,
    ...(store ? { store } : {}),
    message: {
      success: false,
      data: null,
      error: {
        code: 429,
        message: 'Too many requests — please try again later',
      },
    },
  });
}

export function createGlobalRateLimiter() {
  return createRateLimiter(15 * 60 * 1000, 100, 'rl:global:');
}

export function createAuthRateLimiter() {
  return createRateLimiter(15 * 60 * 1000, 20, 'rl:auth:');
}
