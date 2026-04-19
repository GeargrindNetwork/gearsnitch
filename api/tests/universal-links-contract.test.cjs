const fs = require('node:fs');
const path = require('node:path');

const repoRoot = path.join(__dirname, '..', '..');

function read(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

function fileExists(relativePath) {
  return fs.existsSync(path.join(repoRoot, relativePath));
}

describe('Universal Links — /r/:code landing + AASA contract', () => {
  const referralRoutes = read('api/src/modules/referrals/routes.ts');
  const appTs = read('api/src/app.ts');
  const nginxConf = read('infrastructure/docker/nginx.conf');
  const entitlements = read('client-ios/GearSnitch/GearSnitch.entitlements');
  const projectYml = read('client-ios/project.yml');

  // ---------------------------------------------------------------------------
  // API — GET /r/:code
  // ---------------------------------------------------------------------------

  describe('API — /r/:code landing handler', () => {
    test('exposes a Universal Link router distinct from the authenticated /referrals router', () => {
      expect(referralRoutes).toMatch(/const universalLinkRouter\s*=\s*Router\(\);/);
      expect(referralRoutes).toContain('export { universalLinkRouter };');
      expect(referralRoutes).toContain("universalLinkRouter.get('/:code'");
    });

    test('handler is UNAUTHENTICATED (must not gate behind isAuthenticated)', () => {
      const handlerMatch = referralRoutes.match(
        /universalLinkRouter\.get\('\/:code',\s*([\s\S]*?)\)\s*;/,
      );
      expect(handlerMatch).not.toBeNull();
      const handlerSignature = handlerMatch[1];
      expect(handlerSignature).not.toMatch(/isAuthenticated/);
    });

    test('falls back to 302 App Store redirect for non-iOS UAs', () => {
      expect(referralRoutes).toContain(
        "res.redirect(StatusCodes.MOVED_TEMPORARILY, APP_STORE_FALLBACK_URL);",
      );
      expect(referralRoutes).toMatch(/APP_STORE_FALLBACK_URL\s*=\s*/);
      expect(referralRoutes).toContain('apps.apple.com');
    });

    test('sets a first-party gs_ref cookie with 30-day Max-Age / Lax / Secure', () => {
      expect(referralRoutes).toContain("REFERRAL_COOKIE_NAME = 'gs_ref'");
      expect(referralRoutes).toContain('60 * 60 * 24 * 30');
      expect(referralRoutes).toMatch(/sameSite:\s*'lax'/);
      expect(referralRoutes).toMatch(/secure:\s*true/);
      expect(referralRoutes).toContain('res.cookie(REFERRAL_COOKIE_NAME');
    });

    test('returns HTML 404 for missing / malformed codes', () => {
      expect(referralRoutes).toContain('renderNotFoundHtml');
      expect(referralRoutes).toContain('StatusCodes.NOT_FOUND');
      expect(referralRoutes).toMatch(/REFERRAL_CODE_PATTERN\s*=\s*\/\^\[A-Z0-9\]\{4,32\}\$\//);
    });

    test('returns the Universal Link bridge HTML for iOS user agents', () => {
      expect(referralRoutes).toContain('isIOSUserAgent');
      expect(referralRoutes).toContain('renderUniversalLinkBridgeHtml');
      expect(referralRoutes).toContain('meta http-equiv="refresh"');
      // Fallback button for the case where iOS didn't intercept.
      expect(referralRoutes).toMatch(/class="button"\s+href=/);
    });

    test('mounts the universal link router at /r on the express app, outside /api/v1', () => {
      expect(appTs).toContain("import { universalLinkRouter } from './modules/referrals/routes.js';");
      expect(appTs).toContain("app.use('/r', universalLinkRouter);");
      // Must come AFTER the global rate limiter & before the 404 fallthrough.
      const rIdx = appTs.indexOf("app.use('/r', universalLinkRouter);");
      const rateLimiterIdx = appTs.indexOf('app.use(globalRateLimiter);');
      const notFoundIdx = appTs.indexOf("message: 'Route not found'");
      expect(rIdx).toBeGreaterThan(rateLimiterIdx);
      expect(rIdx).toBeLessThan(notFoundIdx);
    });

    test('looks up the code against both User.referralCode and historical Referral rows', () => {
      expect(referralRoutes).toContain("User.exists({ referralCode: normalizedCode })");
      expect(referralRoutes).toContain("Referral.exists({ referralCode: normalizedCode })");
    });
  });

  // ---------------------------------------------------------------------------
  // Web — apple-app-site-association
  // ---------------------------------------------------------------------------

  describe('Web — apple-app-site-association', () => {
    const aasaPath = 'web/public/.well-known/apple-app-site-association';

    test('AASA file exists at the canonical well-known path', () => {
      expect(fileExists(aasaPath)).toBe(true);
    });

    test('AASA declares the correct appID and /r/* applinks pattern', () => {
      const raw = read(aasaPath);
      const parsed = JSON.parse(raw);

      expect(parsed).toHaveProperty('applinks.details');
      const details = parsed.applinks.details;
      expect(Array.isArray(details)).toBe(true);
      expect(details.length).toBeGreaterThan(0);

      const entry = details[0];
      expect(entry.appIDs).toContain('TUZYDM227C.com.gearsnitch.app');
      expect(Array.isArray(entry.components)).toBe(true);
      const referralComponent = entry.components.find((c) => c['/'] === '/r/*');
      expect(referralComponent).toBeDefined();
    });

    test('nginx serves the extensionless AASA file as application/json', () => {
      expect(nginxConf).toContain(
        'location = /.well-known/apple-app-site-association',
      );
      expect(nginxConf).toMatch(
        /location\s*=\s*\/\.well-known\/apple-app-site-association\s*\{[\s\S]*?default_type application\/json;/,
      );
    });

    test('nginx preserves apple-developer-merchantid-domain-association behavior', () => {
      expect(nginxConf).toContain(
        'location = /.well-known/apple-developer-merchantid-domain-association',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // iOS — entitlements already declare the associated domain
  // ---------------------------------------------------------------------------

  describe('iOS — associated domain', () => {
    test('entitlements declare applinks:gearsnitch.com', () => {
      expect(entitlements).toContain('<key>com.apple.developer.associated-domains</key>');
      expect(entitlements).toContain('<string>applinks:gearsnitch.com</string>');
    });

    test('xcodegen project.yml declares applinks:gearsnitch.com', () => {
      expect(projectYml).toContain('applinks:gearsnitch.com');
    });
  });
});
