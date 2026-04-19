/**
 * Feature-flag module entrypoint — lazily constructs a singleton
 * `FeatureFlagService` bound to the live Redis client.
 *
 * Tests (or scripts that want a hermetic service) can bypass the singleton by
 * constructing `FeatureFlagService` directly with a stub client.
 */

import type IORedis from 'ioredis';
import { getRedisClient } from '../../loaders/redis.js';
import {
  FeatureFlagService,
  type FeatureFlagRedisClient,
} from './FeatureFlagService.js';

export { FeatureFlagService } from './FeatureFlagService.js';
export type {
  FeatureFlagRedisClient,
  FeatureFlagUser,
} from './FeatureFlagService.js';
export { adminRouter, userRouter } from './routes.js';

let instance: FeatureFlagService | null = null;

/**
 * ioredis' `get`/`set`/`del`/`keys` signatures include overloads we don't
 * need — cast to the minimal contract the service consumes.
 */
function adaptRedis(client: IORedis): FeatureFlagRedisClient {
  return {
    get: (key) => client.get(key),
    set: (key, value) => client.set(key, value),
    del: (key) => client.del(key),
    keys: (pattern) => client.keys(pattern),
  };
}

export function getFeatureFlagService(): FeatureFlagService {
  if (!instance) {
    instance = new FeatureFlagService(adaptRedis(getRedisClient()));
  }
  return instance;
}

/** Test helper — discards the singleton so a fresh one binds on next call. */
export function resetFeatureFlagService(): void {
  instance = null;
}
