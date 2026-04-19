/**
 * Vitest global setup (item #24).
 *
 * Extends `expect` with @testing-library/jest-dom matchers, cleans up the DOM
 * between tests, and provides stubbed values for the `import.meta.env`
 * variables the app reads at module scope. Having this centralized here means
 * individual tests do not each have to juggle env setup.
 */

import '@testing-library/jest-dom/vitest';
import { cleanup } from '@testing-library/react';
import { afterEach, beforeAll, beforeEach, vi } from 'vitest';

/**
 * Node 25 ships a built-in `localStorage` that is only functional when
 * `--localstorage-file=…` is provided; otherwise it is a bare object with no
 * Storage prototype methods. That shadows jsdom's Storage implementation on
 * `window.localStorage`, which breaks any app code that calls
 * `localStorage.removeItem(...)`. Swap in a minimal in-memory Storage shim for
 * tests so behaviour is consistent across Node 20 (CI) and Node 25 (local).
 */
class MemoryStorage implements Storage {
  private store = new Map<string, string>();
  get length() { return this.store.size; }
  clear() { this.store.clear(); }
  getItem(key: string) { return this.store.has(key) ? this.store.get(key)! : null; }
  key(index: number) { return Array.from(this.store.keys())[index] ?? null; }
  removeItem(key: string) { this.store.delete(key); }
  setItem(key: string, value: string) { this.store.set(key, String(value)); }
}

function installMemoryStorage() {
  const storage = new MemoryStorage();
  Object.defineProperty(window, 'localStorage', {
    configurable: true,
    value: storage,
  });
  Object.defineProperty(globalThis, 'localStorage', {
    configurable: true,
    value: storage,
  });
  const sessionStorage = new MemoryStorage();
  Object.defineProperty(window, 'sessionStorage', {
    configurable: true,
    value: sessionStorage,
  });
  Object.defineProperty(globalThis, 'sessionStorage', {
    configurable: true,
    value: sessionStorage,
  });
}

beforeAll(() => {
  // Default env values for tests — individual tests can override via
  // `vi.stubEnv(key, value)` when they need to exercise alternate branches.
  vi.stubEnv('VITE_API_URL', 'http://localhost:3001/api/v1');
  vi.stubEnv('VITE_GOOGLE_CLIENT_ID', '');
  vi.stubEnv('VITE_APPLE_SERVICE_ID', '');
  vi.stubEnv('VITE_APPLE_REDIRECT_URI', '');
});

beforeEach(() => {
  installMemoryStorage();
});

afterEach(() => {
  cleanup();
  vi.clearAllMocks();
});
