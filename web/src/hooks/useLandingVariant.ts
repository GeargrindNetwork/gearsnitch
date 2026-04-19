/**
 * Landing page A/B bucketing hook (RALPH backlog item #36).
 *
 * Two variants:
 *   - `v1` — control (existing landing copy + layout)
 *   - `v2` — benefits-forward variant (fresh copy/layout)
 *
 * Bucketing rules, in priority order:
 *   1. `?variant=v1|v2` query string — wins for QA/preview, never persists.
 *   2. `gs_landing_variant` cookie — once assigned a visitor stays in the same
 *      bucket for `VARIANT_COOKIE_MAX_AGE_DAYS` days.
 *   3. Fresh random split — `Math.random() < 0.5 ? 'v1' : 'v2'`, then written
 *      to the cookie so subsequent visits are sticky.
 *
 * On first resolution per hook instance we emit a `landing_variant_assigned`
 * analytics event exactly once with `{ variant }`. Re-mounts during the same
 * page load (e.g. Strict Mode double-invocation) do not double-fire thanks to
 * a module-level guard keyed by variant.
 */
import { useEffect, useState } from 'react';
import { trackEvent } from '@/lib/analytics';

export const VARIANT_COOKIE_NAME = 'gs_landing_variant';
export const VARIANT_COOKIE_MAX_AGE_DAYS = 30;
export const VARIANT_QUERY_PARAM = 'variant';
export const VARIANT_ANALYTICS_EVENT = 'landing_variant_assigned';

export type LandingVariant = 'v1' | 'v2';

const VALID_VARIANTS: readonly LandingVariant[] = ['v1', 'v2'];

function isValidVariant(value: string | null | undefined): value is LandingVariant {
  return value === 'v1' || value === 'v2';
}

function readCookie(name: string): string | null {
  if (typeof document === 'undefined') return null;
  const target = `${name}=`;
  const parts = document.cookie ? document.cookie.split(';') : [];
  for (const raw of parts) {
    const trimmed = raw.trim();
    if (trimmed.startsWith(target)) {
      return decodeURIComponent(trimmed.slice(target.length));
    }
  }
  return null;
}

function writeCookie(name: string, value: string, maxAgeDays: number): void {
  if (typeof document === 'undefined') return;
  const maxAgeSeconds = maxAgeDays * 24 * 60 * 60;
  document.cookie = `${name}=${encodeURIComponent(value)}; path=/; max-age=${maxAgeSeconds}; SameSite=Lax`;
}

function readQueryOverride(): LandingVariant | null {
  if (typeof window === 'undefined' || !window.location) return null;
  try {
    const params = new URLSearchParams(window.location.search);
    const raw = params.get(VARIANT_QUERY_PARAM);
    return isValidVariant(raw) ? raw : null;
  } catch {
    return null;
  }
}

function rollFreshVariant(): LandingVariant {
  return Math.random() < 0.5 ? 'v1' : 'v2';
}

/**
 * Module-scoped guard so that even if multiple `useLandingVariant` consumers
 * mount on the same page (or React strict mode double-invokes effects), the
 * `landing_variant_assigned` event fires at most once per page load.
 */
let analyticsFiredThisLoad = false;

/** Test-only helper — reset the fire-once guard between tests. */
export function __resetLandingVariantAnalyticsGuard(): void {
  analyticsFiredThisLoad = false;
}

export interface UseLandingVariantResult {
  /** The resolved variant. `null` until the hook has run on the client. */
  variant: LandingVariant | null;
  /** Was the variant supplied via `?variant=…` (i.e. QA/preview)? */
  isOverride: boolean;
}

export function resolveLandingVariant(): { variant: LandingVariant; isOverride: boolean; persist: boolean } {
  const override = readQueryOverride();
  if (override) {
    return { variant: override, isOverride: true, persist: false };
  }
  const fromCookie = readCookie(VARIANT_COOKIE_NAME);
  if (isValidVariant(fromCookie)) {
    return { variant: fromCookie, isOverride: false, persist: false };
  }
  return { variant: rollFreshVariant(), isOverride: false, persist: true };
}

export function useLandingVariant(): UseLandingVariantResult {
  // Resolve synchronously via a lazy initializer so the first paint already
  // has the correct variant (no flash of control). The app runs as a Vite
  // SPA, so `document` / `window` are available by the time any component
  // renders — we still guard for SSR inside the helpers to be safe.
  const [state] = useState<UseLandingVariantResult & { resolved: ReturnType<typeof resolveLandingVariant> | null }>(
    () => {
      if (typeof document === 'undefined' || typeof window === 'undefined') {
        return { variant: null, isOverride: false, resolved: null };
      }
      const resolved = resolveLandingVariant();
      return {
        variant: resolved.variant,
        isOverride: resolved.isOverride,
        resolved,
      };
    },
  );

  useEffect(() => {
    // Persist + emit analytics as side effects, never via setState. The lazy
    // initializer above already handled state, so this effect only deals
    // with the outside world (cookie jar, analytics pipeline).
    const resolved = state.resolved;
    if (!resolved) return;
    if (resolved.persist) {
      writeCookie(VARIANT_COOKIE_NAME, resolved.variant, VARIANT_COOKIE_MAX_AGE_DAYS);
    }
    if (!analyticsFiredThisLoad) {
      analyticsFiredThisLoad = true;
      try {
        trackEvent('experiment', VARIANT_ANALYTICS_EVENT, resolved.variant);
      } catch {
        // Analytics failures must never break the landing render.
      }
    }
    // Bucket once per mount — the resolved value is stable for the lifetime
    // of this hook instance so the effect must not re-run on re-renders.
  }, [state.resolved]);

  return { variant: state.variant, isOverride: state.isOverride };
}

// Re-export for tests that want to assert the list of valid variants.
export const LANDING_VARIANTS = VALID_VARIANTS;
