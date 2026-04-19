/**
 * Tests for the landing A/B bucketing hook (item #36).
 *
 * Covers:
 *   1. First-visit assigns a variant and persists it to the cookie.
 *   2. Repeat visit preserves the cookie-assigned variant.
 *   3. `?variant=v2` override wins over the cookie.
 *   4. `landing_variant_assigned` analytics event fires exactly once per load.
 *   5. Invalid override values fall through to cookie / random assignment.
 */
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import {
  useLandingVariant,
  resolveLandingVariant,
  __resetLandingVariantAnalyticsGuard,
  VARIANT_COOKIE_NAME,
  VARIANT_ANALYTICS_EVENT,
} from '@/hooks/useLandingVariant';

// Mock the analytics module so we can assert trackEvent calls without hitting GA.
vi.mock('@/lib/analytics', () => ({
  trackEvent: vi.fn(),
  trackPageView: vi.fn(),
  initGA: vi.fn(),
}));

import { trackEvent } from '@/lib/analytics';

function clearCookies(): void {
  // Expire every cookie currently set on the document.
  for (const raw of document.cookie.split(';')) {
    const name = raw.split('=')[0]?.trim();
    if (name) {
      document.cookie = `${name}=; path=/; max-age=0`;
    }
  }
}

function setLocationSearch(search: string): void {
  // jsdom permits direct mutation of window.location.search.
  window.history.replaceState({}, '', `/${search}`);
}

beforeEach(() => {
  clearCookies();
  setLocationSearch('');
  __resetLandingVariantAnalyticsGuard();
  vi.mocked(trackEvent).mockClear();
});

afterEach(() => {
  clearCookies();
  setLocationSearch('');
});

describe('useLandingVariant — first visit', () => {
  it('assigns a valid variant and writes it to the cookie', () => {
    // Force deterministic roll — Math.random() < 0.5 → 'v1'.
    const randSpy = vi.spyOn(Math, 'random').mockReturnValue(0.1);

    const { result } = renderHook(() => useLandingVariant());

    expect(result.current.variant).toBe('v1');
    expect(result.current.isOverride).toBe(false);
    expect(document.cookie).toContain(`${VARIANT_COOKIE_NAME}=v1`);

    randSpy.mockRestore();
  });

  it('rolls v2 when Math.random() >= 0.5', () => {
    const randSpy = vi.spyOn(Math, 'random').mockReturnValue(0.9);

    const { result } = renderHook(() => useLandingVariant());

    expect(result.current.variant).toBe('v2');
    expect(document.cookie).toContain(`${VARIANT_COOKIE_NAME}=v2`);

    randSpy.mockRestore();
  });
});

describe('useLandingVariant — repeat visit', () => {
  it('preserves the cookie-assigned variant across renders', () => {
    document.cookie = `${VARIANT_COOKIE_NAME}=v2; path=/`;
    // Even if the random roll would flip it, the cookie should win.
    const randSpy = vi.spyOn(Math, 'random').mockReturnValue(0.1);

    const { result } = renderHook(() => useLandingVariant());

    expect(result.current.variant).toBe('v2');
    expect(result.current.isOverride).toBe(false);

    randSpy.mockRestore();
  });

  it('does not re-roll when the cookie is already set', () => {
    document.cookie = `${VARIANT_COOKIE_NAME}=v1; path=/`;
    const randSpy = vi.spyOn(Math, 'random');

    renderHook(() => useLandingVariant());

    expect(randSpy).not.toHaveBeenCalled();
    randSpy.mockRestore();
  });
});

describe('useLandingVariant — query override', () => {
  it('?variant=v2 wins over an existing v1 cookie', () => {
    document.cookie = `${VARIANT_COOKIE_NAME}=v1; path=/`;
    setLocationSearch('?variant=v2');

    const { result } = renderHook(() => useLandingVariant());

    expect(result.current.variant).toBe('v2');
    expect(result.current.isOverride).toBe(true);
    // Override must NOT overwrite the persisted cookie — bucketing is sticky.
    expect(document.cookie).toContain(`${VARIANT_COOKIE_NAME}=v1`);
  });

  it('?variant=v1 wins over an existing v2 cookie', () => {
    document.cookie = `${VARIANT_COOKIE_NAME}=v2; path=/`;
    setLocationSearch('?variant=v1');

    const { result } = renderHook(() => useLandingVariant());

    expect(result.current.variant).toBe('v1');
    expect(result.current.isOverride).toBe(true);
  });

  it('ignores unknown variant values and falls back to cookie/random', () => {
    document.cookie = `${VARIANT_COOKIE_NAME}=v2; path=/`;
    setLocationSearch('?variant=v99');

    const { result } = renderHook(() => useLandingVariant());

    expect(result.current.variant).toBe('v2');
    expect(result.current.isOverride).toBe(false);
  });
});

describe('useLandingVariant — analytics', () => {
  it('fires landing_variant_assigned exactly once per page load', () => {
    document.cookie = `${VARIANT_COOKIE_NAME}=v1; path=/`;

    const first = renderHook(() => useLandingVariant());
    const second = renderHook(() => useLandingVariant());

    expect(first.result.current.variant).toBe('v1');
    expect(second.result.current.variant).toBe('v1');

    // Exactly one trackEvent call across both hook instances.
    const experimentCalls = vi
      .mocked(trackEvent)
      .mock.calls.filter((call) => call[1] === VARIANT_ANALYTICS_EVENT);
    expect(experimentCalls).toHaveLength(1);
    expect(experimentCalls[0]).toEqual(['experiment', VARIANT_ANALYTICS_EVENT, 'v1']);
  });

  it('passes the resolved variant as the analytics label', () => {
    setLocationSearch('?variant=v2');

    renderHook(() => useLandingVariant());

    expect(trackEvent).toHaveBeenCalledWith(
      'experiment',
      VARIANT_ANALYTICS_EVENT,
      'v2',
    );
  });

  it('refires after the guard is reset (simulates a new page load)', () => {
    document.cookie = `${VARIANT_COOKIE_NAME}=v1; path=/`;
    renderHook(() => useLandingVariant());
    expect(trackEvent).toHaveBeenCalledTimes(1);

    act(() => {
      __resetLandingVariantAnalyticsGuard();
    });
    renderHook(() => useLandingVariant());
    expect(trackEvent).toHaveBeenCalledTimes(2);
  });
});

describe('resolveLandingVariant — pure resolution', () => {
  it('returns persist:true on fresh assignment', () => {
    const randSpy = vi.spyOn(Math, 'random').mockReturnValue(0.1);
    const resolved = resolveLandingVariant();
    expect(resolved.variant).toBe('v1');
    expect(resolved.isOverride).toBe(false);
    expect(resolved.persist).toBe(true);
    randSpy.mockRestore();
  });

  it('returns persist:false when reading from the cookie', () => {
    document.cookie = `${VARIANT_COOKIE_NAME}=v2; path=/`;
    const resolved = resolveLandingVariant();
    expect(resolved.variant).toBe('v2');
    expect(resolved.persist).toBe(false);
  });

  it('returns persist:false for query overrides', () => {
    setLocationSearch('?variant=v1');
    const resolved = resolveLandingVariant();
    expect(resolved.isOverride).toBe(true);
    expect(resolved.persist).toBe(false);
  });
});
