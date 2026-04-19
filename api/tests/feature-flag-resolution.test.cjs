/**
 * Feature-flag resolution order regression test (backlog item #34).
 *
 * Exercises the actual `FeatureFlagService` runtime — loads the TypeScript
 * module via `tsx/cjs` in a child process (matching the existing
 * stripe-checkout-session-runtime / apns-push-integration pattern) and drives
 * it with an in-memory Redis stub that implements just the four methods the
 * service consumes (`get`, `set`, `del`, `keys`).
 *
 * Resolution order (highest → lowest):
 *   1. per-user override
 *   2. per-tier override
 *   3. global flag
 *   4. caller default (or `false`)
 */

const { execFileSync } = require('node:child_process');
const path = require('node:path');

const apiRoot = path.join(__dirname, '..');

/**
 * Run `body` inside a fresh tsx/cjs child process. The body runs in an
 * async IIFE that has the in-memory Redis stub + service already loaded on
 * the local scope. `expect`-like assertions throw — a thrown error is a
 * failing test.
 */
function runScenario(body) {
  const script = `
    process.env.NODE_ENV = 'test';
    process.env.LOG_DIR = require('node:os').tmpdir();

    class InMemoryRedis {
      constructor() { this.store = new Map(); }
      async get(key) { return this.store.has(key) ? this.store.get(key) : null; }
      async set(key, value) { this.store.set(key, String(value)); return 'OK'; }
      async del(key) { return this.store.delete(key) ? 1 : 0; }
      async keys(pattern) {
        // ioredis' KEYS accepts glob patterns — the service only uses the
        // trailing '*' form (e.g. 'ff:flag:*'), so a prefix match is enough.
        if (!pattern.endsWith('*')) {
          return [...this.store.keys()].filter((k) => k === pattern);
        }
        const prefix = pattern.slice(0, -1);
        return [...this.store.keys()].filter((k) => k.startsWith(prefix));
      }
    }

    function assert(cond, message) {
      if (!cond) throw new Error('assertion failed: ' + message);
    }
    function assertEqual(actual, expected, message) {
      if (actual !== expected) {
        throw new Error(
          'assertion failed (' + message + '): expected ' + JSON.stringify(expected)
            + ' but got ' + JSON.stringify(actual),
        );
      }
    }

    (async () => {
      const { FeatureFlagService } = require('./src/modules/feature-flags/FeatureFlagService.ts');
      const redis = new InMemoryRedis();
      // Deterministic clock — lets the test exercise TTL expiry without setTimeout.
      let clock = 1_000_000;
      const service = new FeatureFlagService(redis, () => clock);

      try {
        ${body}
        console.log('OK');
      } catch (err) {
        console.error('FAIL:', err && err.stack ? err.stack : String(err));
        process.exit(1);
      }
    })().catch((err) => {
      console.error('UNCAUGHT:', err && err.stack ? err.stack : String(err));
      process.exit(1);
    });
  `;

  return execFileSync(process.execPath, ['-r', 'tsx/cjs', '-e', script], {
    cwd: apiRoot,
    encoding: 'utf8',
    stdio: 'pipe',
  });
}

describe('FeatureFlagService — resolution order (item #34)', () => {
  test('default fallback is returned when nothing is set anywhere', () => {
    const out = runScenario(`
      const result = await service.isEnabled('new-feature');
      assertEqual(result, false, 'unset + no default = false');

      const withDefault = await service.isEnabled('new-feature-2', null, true);
      assertEqual(withDefault, true, 'unset + default=true = true');
    `);
    expect(out).toContain('OK');
  });

  test('global flag is returned when no overrides exist', () => {
    const out = runScenario(`
      await service.setGlobal('dark-mode', true);
      const anon = await service.isEnabled('dark-mode');
      assertEqual(anon, true, 'global true for anonymous caller');

      const withUser = await service.isEnabled('dark-mode', { id: 'u1', tier: 'hustle' });
      assertEqual(withUser, true, 'global true for user with no overrides');
    `);
    expect(out).toContain('OK');
  });

  test('tier override beats global', () => {
    const out = runScenario(`
      await service.setGlobal('premium-charts', false);
      await service.setTierOverride('hwmf', 'premium-charts', true);

      const free = await service.isEnabled('premium-charts', { id: 'u1', tier: null });
      assertEqual(free, false, 'free user falls back to global=false');

      const hustle = await service.isEnabled('premium-charts', { id: 'u2', tier: 'hustle' });
      assertEqual(hustle, false, 'hustle tier has no override, global=false wins');

      const hwmf = await service.isEnabled('premium-charts', { id: 'u3', tier: 'hwmf' });
      assertEqual(hwmf, true, 'hwmf tier override=true beats global=false');
    `);
    expect(out).toContain('OK');
  });

  test('user override beats tier override beats global', () => {
    const out = runScenario(`
      await service.setGlobal('beta-panel', false);
      await service.setTierOverride('babyMomma', 'beta-panel', true);
      await service.setUserOverride('opt-out-user', 'beta-panel', false);

      // Global path — free tier user with no user override.
      const anon = await service.isEnabled('beta-panel', { id: 'anon', tier: null });
      assertEqual(anon, false, 'no overrides = global false');

      // Tier path — babyMomma tier user with no user override.
      const baby = await service.isEnabled('beta-panel', { id: 'baby', tier: 'babyMomma' });
      assertEqual(baby, true, 'tier override wins over global');

      // User override path — even on babyMomma the per-user 'false' wins.
      const optOut = await service.isEnabled('beta-panel', { id: 'opt-out-user', tier: 'babyMomma' });
      assertEqual(optOut, false, 'user override beats tier override');
    `);
    expect(out).toContain('OK');
  });

  test('user override of false wins even if tier and global are true', () => {
    // Guards against a bug where the service confuses "not set" with "false".
    const out = runScenario(`
      await service.setGlobal('sparkle', true);
      await service.setTierOverride('hustle', 'sparkle', true);
      await service.setUserOverride('u99', 'sparkle', false);

      const off = await service.isEnabled('sparkle', { id: 'u99', tier: 'hustle' });
      assertEqual(off, false, 'explicit user=false overrides higher layers');

      const otherUser = await service.isEnabled('sparkle', { id: 'u100', tier: 'hustle' });
      assertEqual(otherUser, true, 'other user still sees tier=true');
    `);
    expect(out).toContain('OK');
  });

  test('deleteGlobal / deleteTierOverride / deleteUserOverride strip layers', () => {
    const out = runScenario(`
      await service.setGlobal('layered', true);
      await service.setTierOverride('hwmf', 'layered', false);
      await service.setUserOverride('u1', 'layered', true);

      const before = await service.isEnabled('layered', { id: 'u1', tier: 'hwmf' });
      assertEqual(before, true, 'user=true wins initially');

      service.clearCache();
      await service.deleteUserOverride('u1', 'layered');
      const afterUserDelete = await service.isEnabled('layered', { id: 'u1', tier: 'hwmf' });
      assertEqual(afterUserDelete, false, 'tier=false now wins');

      await service.deleteTierOverride('hwmf', 'layered');
      const afterTierDelete = await service.isEnabled('layered', { id: 'u1', tier: 'hwmf' });
      assertEqual(afterTierDelete, true, 'global=true wins');

      await service.deleteGlobal('layered');
      const afterGlobalDelete = await service.isEnabled('layered', { id: 'u1', tier: 'hwmf' });
      assertEqual(afterGlobalDelete, false, 'nothing set = default false');
    `);
    expect(out).toContain('OK');
  });

  test('cache TTL expires after 60s and re-reads Redis', () => {
    const out = runScenario(`
      await service.setGlobal('cached', true);
      const first = await service.isEnabled('cached');
      assertEqual(first, true, 'first read = true');

      // Mutate Redis directly, bypassing the service API so the cache isn't
      // invalidated. This simulates another process flipping the flag.
      await redis.set('ff:flag:cached', '0');
      const stillCached = await service.isEnabled('cached');
      assertEqual(stillCached, true, 'cached true survives while TTL is live');

      // Advance the deterministic clock past the 60 s TTL.
      clock += 61_000;
      const afterTTL = await service.isEnabled('cached');
      assertEqual(afterTTL, false, 'after TTL, service re-reads Redis and sees false');
    `);
    expect(out).toContain('OK');
  });

  test('resolveAllForUser discovers every global flag and applies overrides', () => {
    const out = runScenario(`
      await service.setGlobal('alpha', true);
      await service.setGlobal('beta', false);
      await service.setGlobal('gamma', true);
      await service.setTierOverride('hustle', 'beta', true);
      await service.setUserOverride('u1', 'gamma', false);

      const map = await service.resolveAllForUser({ id: 'u1', tier: 'hustle' });

      assertEqual(map.alpha, true, 'alpha = global true');
      assertEqual(map.beta, true, 'beta = tier override true');
      assertEqual(map.gamma, false, 'gamma = user override false');
      assertEqual(Object.keys(map).sort().join(','), 'alpha,beta,gamma', 'map covers all globals');
    `);
    expect(out).toContain('OK');
  });
});

describe('feature-flags module — contract', () => {
  const fs = require('node:fs');

  function read(rel) {
    return fs.readFileSync(path.join(apiRoot, rel), 'utf8');
  }

  test('routes file guards admin endpoints with isAuthenticated + hasRole(["admin"])', () => {
    const routes = read('src/modules/feature-flags/routes.ts');
    expect(routes).toContain("adminRouter.use(isAuthenticated, hasRole(['admin']))");
    expect(routes).toContain("userRouter.use(isAuthenticated)");
    expect(routes).toMatch(/adminRouter\.get\(\s*['"]\/:name['"]/);
    expect(routes).toMatch(/adminRouter\.put\(\s*['"]\/:name['"]/);
    expect(routes).toMatch(/adminRouter\.delete\(\s*['"]\/:name['"]/);
    expect(routes).toMatch(/userRouter\.get\(\s*['"]\/['"]/);
  });

  test('router index mounts both feature-flag surfaces', () => {
    const routerIndex = read('src/routes/index.ts');
    expect(routerIndex).toContain("/admin/feature-flags");
    expect(routerIndex).toContain("/feature-flags");
    expect(routerIndex).toContain('featureFlagsAdminRouter');
    expect(routerIndex).toContain('featureFlagsUserRouter');
  });

  test('service exports resolution key helpers with documented prefixes', () => {
    const service = read('src/modules/feature-flags/FeatureFlagService.ts');
    expect(service).toContain("GLOBAL_KEY_PREFIX = 'ff:flag:'");
    expect(service).toContain("USER_KEY_PREFIX = 'ff:user:'");
    expect(service).toContain("TIER_KEY_PREFIX = 'ff:tier:'");
    expect(service).toContain('isEnabled');
    expect(service).toContain('resolveAllForUser');
  });
});
