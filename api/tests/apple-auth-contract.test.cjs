const fs = require('node:fs');
const path = require('node:path');

const apiRoot = path.join(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

describe('apple sign-in contract regression sweep', () => {
  const authService = read('src/services/AuthService.ts');
  const config = read('src/config/index.ts');

  test('apple sign-in uses authorization-code exchange when server credentials are configured', () => {
    expect(authService).toContain(
      'if (AuthService.hasAppleCodeExchangeConfig()) {',
    );
    expect(authService).toContain(
      'exchanged = await AuthService.exchangeAppleAuthorizationCode(',
    );
    expect(authService).toContain('if (decoded.sub !== exchanged.sub)');
    expect(authService).toContain("logger.warn(");
    expect(authService).toContain("const email = decoded.email ?? exchanged?.email;");
    expect(authService).toContain('const normalizedGivenName = givenName?.trim() || undefined;');
    expect(authService).toContain('const normalizedFamilyName = familyName?.trim() || undefined;');
  });

  test('apple oauth configuration includes the private key needed to mint the client secret', () => {
    expect(config).toContain('const appleClientIds = parseEnvList(');
    expect(config).toContain('process.env.APPLE_CLIENT_IDS');
    expect(config).toContain("applePrivateKey: process.env.APPLE_PRIVATE_KEY ?? ''");
    expect(authService).toContain("import { SignJWT, importPKCS8 } from 'jose';");
    expect(authService).toContain("grant_type: 'authorization_code'");
    expect(authService).toContain("setAudience('https://appleid.apple.com')");
    expect(authService).toContain("setExpirationTime('5m')");
    expect(authService).toContain('decoded.audience');
    expect(authService).toContain('AuthService.verifyAppleToken(payload.id_token, appleClientId)');
  });

  test('apple auth treats placeholder exchange credentials as unconfigured', () => {
    expect(authService).toContain("normalized !== 'placeholder'");
    expect(authService).toContain('private static hasAppleCodeExchangeConfig(): boolean');
  });

  test('apple sign-in persists first and last names when Apple provides them', () => {
    expect(authService).toContain('user.firstName = normalizedGivenName;');
    expect(authService).toContain('user.lastName = normalizedFamilyName;');
    expect(authService).toContain('firstName: normalizedGivenName,');
    expect(authService).toContain('lastName: normalizedFamilyName,');
  });
});
