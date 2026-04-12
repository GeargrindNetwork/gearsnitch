const fs = require('node:fs');
const path = require('node:path');

const apiRoot = path.join(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

describe('oauth provisioning policy regression sweep', () => {
  const authService = read('src/services/AuthService.ts');
  const authRoutes = read('src/modules/auth/routes.ts');
  const config = read('src/config/index.ts');

  test('google and apple accept multiple configured audiences', () => {
    expect(config).toContain('const googleOAuthClientIds = parseEnvList(');
    expect(config).toContain('process.env.GOOGLE_OAUTH_CLIENT_IDS');
    expect(config).toContain('googleOAuthClientIds,');
    expect(authService).toContain('const audiences = AuthService.getConfiguredGoogleAudiences();');
    expect(authService).toContain('const appleAudiences = expectedAudience');
    expect(authService).toContain('return config.googleOAuthClientIds;');
    expect(authService).toContain('return config.appleClientIds;');
  });

  test('new social accounts can only be provisioned from iOS', () => {
    expect(authService).toContain("AuthService.assertProvisioningAllowed('google', deviceInfo.platform);");
    expect(authService).toContain("AuthService.assertProvisioningAllowed('apple', deviceInfo.platform);");
    expect(authService).toContain("if (platform === 'ios')");
    expect(authService).toContain('Create it in the iOS app first');
  });

  test('platform header parsing is normalized before auth decisions', () => {
    expect(authRoutes).toContain("const rawPlatform = String(req.headers['x-client-platform'] ?? 'ios').toLowerCase();");
    expect(authRoutes).toContain("const platform: DeviceInfo['platform'] = rawPlatform === 'web'");
  });
});
