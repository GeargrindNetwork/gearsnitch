/**
 * labProviderFactory — selects a concrete LabProvider based on env.
 *
 * LAB_PROVIDER=rupa   (default)  → RupaHealthProvider (sandbox skeleton)
 * LAB_PROVIDER=labcorp           → LabCorpProvider (signalling stub)
 *
 * The factory caches one instance per resolved id to avoid recreating
 * HTTP clients on every request.
 */

import { LabCorpProvider } from './LabCorpProvider.js';
import { RupaHealthProvider } from './RupaHealthProvider.js';
import type { LabProvider, LabProviderId } from './types.js';

const SUPPORTED: LabProviderId[] = ['rupa', 'labcorp'];
const DEFAULT_PROVIDER: LabProviderId = 'rupa';

const cache = new Map<LabProviderId, LabProvider>();

export function resolveLabProviderId(raw: string | undefined): LabProviderId {
  const candidate = (raw ?? '').trim().toLowerCase();
  if ((SUPPORTED as string[]).includes(candidate)) {
    return candidate as LabProviderId;
  }
  return DEFAULT_PROVIDER;
}

function instantiate(id: LabProviderId): LabProvider {
  switch (id) {
    case 'rupa':
      return new RupaHealthProvider();
    case 'labcorp':
      return new LabCorpProvider();
    default: {
      // Exhaustiveness guard — should be unreachable.
      const _never: never = id;
      void _never;
      return new RupaHealthProvider();
    }
  }
}

/**
 * Returns the configured LabProvider. Reads `process.env.LAB_PROVIDER` on
 * each call (cheap string compare) but reuses the underlying instance.
 */
export function labProviderFactory(): LabProvider {
  const id = resolveLabProviderId(process.env.LAB_PROVIDER);
  const cached = cache.get(id);
  if (cached) {
    return cached;
  }
  const instance = instantiate(id);
  cache.set(id, instance);
  return instance;
}

/** Test-only: drop cached instances so env overrides take effect mid-test. */
export function __resetLabProviderFactoryForTests(): void {
  cache.clear();
}

export const LAB_PROVIDER_IDS = SUPPORTED;
export const LAB_PROVIDER_DEFAULT = DEFAULT_PROVIDER;
