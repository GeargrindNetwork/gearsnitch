/**
 * Redis-backed feature flag service (backlog item #34).
 *
 * Resolution order (highest precedence first):
 *   1. Per-user override:   ff:user:<userId>:flag:<name>
 *   2. Per-tier override:   ff:tier:<tier>:flag:<name>
 *   3. Global value:        ff:flag:<name>
 *   4. Caller-supplied default (or `false` if omitted)
 *
 * All Redis values are stored as the ASCII strings `'1'` (true) or `'0'`
 * (false). Any other / missing value is treated as "unset" and falls through
 * to the next layer in the resolution chain.
 *
 * The service caches resolved lookups for 60 seconds in-process. The cache is
 * keyed by (flagName, userId, tier) so overrides don't bleed across users.
 * Admin mutations (`setGlobal`, `setUserOverride`, `setTierOverride`,
 * `deleteGlobal`, etc.) invalidate the relevant cache entries on the current
 * process; cross-process invalidation is intentionally out of scope for v1
 * (60 s staleness is acceptable).
 */

export interface FeatureFlagRedisClient {
  get(key: string): Promise<string | null>;
  set(key: string, value: string): Promise<unknown>;
  del(key: string): Promise<unknown>;
  keys(pattern: string): Promise<string[]>;
}

export interface FeatureFlagUser {
  id: string;
  tier?: string | null;
}

interface CacheEntry {
  value: boolean;
  expiresAt: number;
}

const CACHE_TTL_MS = 60 * 1000;

export const GLOBAL_KEY_PREFIX = 'ff:flag:';
export const USER_KEY_PREFIX = 'ff:user:';
export const TIER_KEY_PREFIX = 'ff:tier:';

export function globalFlagKey(name: string): string {
  return `${GLOBAL_KEY_PREFIX}${name}`;
}

export function userFlagKey(userId: string, name: string): string {
  return `${USER_KEY_PREFIX}${userId}:flag:${name}`;
}

export function tierFlagKey(tier: string, name: string): string {
  return `${TIER_KEY_PREFIX}${tier}:flag:${name}`;
}

/**
 * Parse a Redis flag value. `'1'` = true, `'0'` = false, anything else
 * (including `null` / missing) returns `undefined` which means "not set".
 */
export function parseFlagValue(raw: string | null | undefined): boolean | undefined {
  if (raw === '1') {
    return true;
  }
  if (raw === '0') {
    return false;
  }
  return undefined;
}

export function serializeFlagValue(value: boolean): string {
  return value ? '1' : '0';
}

export class FeatureFlagService {
  private cache = new Map<string, CacheEntry>();

  constructor(
    private readonly redis: FeatureFlagRedisClient,
    private readonly now: () => number = () => Date.now(),
  ) {}

  private cacheKey(flagName: string, user?: FeatureFlagUser | null): string {
    if (!user) {
      return `g:${flagName}`;
    }
    return `u:${user.id}:t:${user.tier ?? ''}:${flagName}`;
  }

  private readCache(key: string): boolean | undefined {
    const entry = this.cache.get(key);
    if (!entry) {
      return undefined;
    }
    if (entry.expiresAt <= this.now()) {
      this.cache.delete(key);
      return undefined;
    }
    return entry.value;
  }

  private writeCache(key: string, value: boolean): void {
    this.cache.set(key, {
      value,
      expiresAt: this.now() + CACHE_TTL_MS,
    });
  }

  /**
   * Invalidate every cached entry whose key contains the given flag name.
   * Used after admin writes so a change is visible to callers on the current
   * process immediately instead of after the 60 s TTL expires.
   */
  private invalidateFlag(flagName: string): void {
    const suffix = `:${flagName}`;
    for (const key of this.cache.keys()) {
      if (key === `g:${flagName}` || key.endsWith(suffix)) {
        this.cache.delete(key);
      }
    }
  }

  /**
   * Resolve a flag for a user. Implements the 4-layer precedence described
   * at the top of the file.
   */
  async isEnabled(
    flagName: string,
    user?: FeatureFlagUser | null,
    defaultValue = false,
  ): Promise<boolean> {
    const cacheKey = this.cacheKey(flagName, user);
    const cached = this.readCache(cacheKey);
    if (cached !== undefined) {
      return cached;
    }

    let resolved: boolean | undefined;

    if (user?.id) {
      resolved = parseFlagValue(await this.redis.get(userFlagKey(user.id, flagName)));
    }

    if (resolved === undefined && user?.tier) {
      resolved = parseFlagValue(await this.redis.get(tierFlagKey(user.tier, flagName)));
    }

    if (resolved === undefined) {
      resolved = parseFlagValue(await this.redis.get(globalFlagKey(flagName)));
    }

    const finalValue = resolved ?? defaultValue;
    this.writeCache(cacheKey, finalValue);
    return finalValue;
  }

  /**
   * Resolve every known flag for a user in one shot. Discovers the flag set
   * by scanning the global keyspace `ff:flag:*` — per-user / per-tier
   * overrides only count for flags that also exist globally, which matches
   * the "globals are the source of truth, overrides are exceptions" model.
   */
  async resolveAllForUser(
    user?: FeatureFlagUser | null,
  ): Promise<Record<string, boolean>> {
    const globalKeys = await this.redis.keys(`${GLOBAL_KEY_PREFIX}*`);
    const out: Record<string, boolean> = {};

    for (const key of globalKeys) {
      const name = stripGlobalPrefix(key);
      if (!name) {
        continue;
      }
      out[name] = await this.isEnabled(name, user);
    }

    return out;
  }

  /** Read the global value for a flag — admin read path. */
  async getGlobal(flagName: string): Promise<boolean | undefined> {
    return parseFlagValue(await this.redis.get(globalFlagKey(flagName)));
  }

  /** Set the global value for a flag — admin write path. */
  async setGlobal(flagName: string, value: boolean): Promise<void> {
    await this.redis.set(globalFlagKey(flagName), serializeFlagValue(value));
    this.invalidateFlag(flagName);
  }

  /** Delete the global value for a flag — admin write path. */
  async deleteGlobal(flagName: string): Promise<void> {
    await this.redis.del(globalFlagKey(flagName));
    this.invalidateFlag(flagName);
  }

  async setUserOverride(
    userId: string,
    flagName: string,
    value: boolean,
  ): Promise<void> {
    await this.redis.set(userFlagKey(userId, flagName), serializeFlagValue(value));
    this.invalidateFlag(flagName);
  }

  async deleteUserOverride(userId: string, flagName: string): Promise<void> {
    await this.redis.del(userFlagKey(userId, flagName));
    this.invalidateFlag(flagName);
  }

  async setTierOverride(
    tier: string,
    flagName: string,
    value: boolean,
  ): Promise<void> {
    await this.redis.set(tierFlagKey(tier, flagName), serializeFlagValue(value));
    this.invalidateFlag(flagName);
  }

  async deleteTierOverride(tier: string, flagName: string): Promise<void> {
    await this.redis.del(tierFlagKey(tier, flagName));
    this.invalidateFlag(flagName);
  }

  /**
   * Test-only helper: wipe the in-memory cache. The production code path
   * relies on 60 s TTL expiry — this is just here so the unit test can run
   * consecutive scenarios without flushing global state.
   */
  clearCache(): void {
    this.cache.clear();
  }
}

function stripGlobalPrefix(key: string): string | null {
  // ioredis may or may not return the `gs:` keyPrefix depending on client
  // version — strip it defensively before the `ff:flag:` segment.
  const marker = GLOBAL_KEY_PREFIX;
  const idx = key.indexOf(marker);
  if (idx === -1) {
    return null;
  }
  const name = key.slice(idx + marker.length);
  return name.length > 0 ? name : null;
}
