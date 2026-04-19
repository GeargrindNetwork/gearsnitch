import { useEffect, useState, useRef } from 'react';
import { getFeatureFlags } from '@/lib/api';

/**
 * In-memory cache for the resolved feature-flag map. Shared across every
 * mounted `useFeatureFlag` / `useFeatureFlags` consumer on the page so they
 * don't each issue their own `GET /feature-flags` request.
 *
 * TTL matches the server-side cache (60 s). The promise slot coalesces
 * concurrent initial loads — if two components mount on the same tick, only
 * one network request fires.
 */
const CACHE_TTL_MS = 60_000;
interface CacheSlot {
  flags: Record<string, boolean> | null;
  expiresAt: number;
  inFlight: Promise<Record<string, boolean>> | null;
}
const slot: CacheSlot = { flags: null, expiresAt: 0, inFlight: null };

function loadFlags(): Promise<Record<string, boolean>> {
  const now = Date.now();
  if (slot.flags && slot.expiresAt > now) {
    return Promise.resolve(slot.flags);
  }
  if (slot.inFlight) {
    return slot.inFlight;
  }
  slot.inFlight = getFeatureFlags()
    .then((flags) => {
      slot.flags = flags;
      slot.expiresAt = Date.now() + CACHE_TTL_MS;
      return flags;
    })
    .finally(() => {
      slot.inFlight = null;
    });
  return slot.inFlight;
}

/**
 * Test / logout helper — drop the cached flag map so the next call refetches.
 */
export function resetFeatureFlagsCache(): void {
  slot.flags = null;
  slot.expiresAt = 0;
  slot.inFlight = null;
}

/**
 * Return the boolean value of a single flag for the current user. While the
 * first request is in flight, returns `fallback` (defaults to `false`).
 */
export function useFeatureFlag(name: string, fallback = false): boolean {
  const flags = useFeatureFlags();
  if (flags == null) {
    return fallback;
  }
  return flags[name] ?? fallback;
}

/**
 * Return the resolved flag map (or `null` while loading). Consumers that
 * want to branch on multiple flags should prefer this over calling
 * `useFeatureFlag` N times.
 */
export function useFeatureFlags(): Record<string, boolean> | null {
  const [flags, setFlags] = useState<Record<string, boolean> | null>(slot.flags);
  const mountedRef = useRef(true);

  useEffect(() => {
    mountedRef.current = true;
    let cancelled = false;
    loadFlags()
      .then((resolved) => {
        if (!cancelled && mountedRef.current) {
          setFlags(resolved);
        }
      })
      .catch(() => {
        if (!cancelled && mountedRef.current) {
          // On failure, expose an empty map so consumers can fall through to
          // their per-flag `fallback` values instead of showing a loading
          // state forever.
          setFlags({});
        }
      });
    return () => {
      cancelled = true;
      mountedRef.current = false;
    };
  }, []);

  return flags;
}
