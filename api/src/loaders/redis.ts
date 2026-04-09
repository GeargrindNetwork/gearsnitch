import IORedis from 'ioredis';
import logger from '../utils/logger';
import config from '../config';

let redisClient: IORedis | null = null;

export function getRedisClient(): IORedis {
  if (!redisClient) {
    throw new Error('Redis client not initialized — call connectRedis() first');
  }
  return redisClient;
}

export async function connectRedis(): Promise<IORedis> {
  if (redisClient) {
    return redisClient;
  }

  if (!config.redisUrl) {
    throw new Error('REDIS_URL is not configured');
  }

  redisClient = new IORedis(config.redisUrl, {
    maxRetriesPerRequest: 3,
    retryStrategy(times: number) {
      if (times > 10) {
        logger.error('Redis retry limit reached — giving up');
        return null;
      }
      const delay = Math.min(times * 200, 5000);
      logger.warn(`Redis reconnecting in ${delay}ms (attempt ${times})`);
      return delay;
    },
    enableReadyCheck: true,
    lazyConnect: true,
  });

  redisClient.on('connect', () => {
    logger.info('Redis connected');
  });

  redisClient.on('error', (err) => {
    logger.error('Redis connection error', { error: err.message });
  });

  redisClient.on('close', () => {
    logger.warn('Redis connection closed');
  });

  await redisClient.connect();
  return redisClient;
}

export async function disconnectRedis(): Promise<void> {
  if (redisClient) {
    await redisClient.quit();
    redisClient = null;
    logger.info('Redis disconnected gracefully');
  }
}
