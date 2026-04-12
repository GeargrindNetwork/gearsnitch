const fs = require('node:fs');
const path = require('node:path');

const repoRoot = path.join(__dirname, '..', '..');

function read(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

describe('remote config contract regression sweep', () => {
  const configRoutes = read('api/src/modules/config/routes.ts');
  const remoteConfig = read('api/src/modules/config/remoteConfig.ts');
  const remoteConfigClient = read('client-ios/GearSnitch/Core/Config/RemoteConfigClient.swift');
  const featureFlagsClient = read('client-ios/GearSnitch/Core/Config/FeatureFlags.swift');

  test('config routes expose the app, feature, and user endpoints without placeholders', () => {
    expect(configRoutes).toContain("router.get(['/', '/app']");
    expect(configRoutes).toContain("router.get('/features'");
    expect(configRoutes).toContain("router.get('/user'");
    expect(configRoutes).toContain('getRemoteConfigPayload()');
    expect(configRoutes).toContain('getRemoteFeatureFlags()');
    expect(configRoutes).not.toContain('not yet implemented');
    expect(configRoutes).not.toContain('501');
  });

  test('server payload keys align with the iOS remote config client', () => {
    expect(remoteConfig).toContain('featureFlags: RemoteFeatureFlags');
    expect(remoteConfig).toContain('appVersion: RemoteAppVersionConfig');
    expect(remoteConfig).toContain('maintenance: RemoteMaintenanceConfig');
    expect(remoteConfig).toContain('workoutsEnabled');
    expect(remoteConfig).toContain('storeEnabled');
    expect(remoteConfig).toContain('watchCompanionEnabled');
    expect(remoteConfig).toContain('waterTrackingEnabled');
    expect(remoteConfig).toContain('emergencyContactsEnabled');
    expect(remoteConfigClient).toContain('let featureFlags: RemoteFeatureFlags?');
    expect(remoteConfigClient).toContain('let appVersion: AppVersionConfig?');
    expect(remoteConfigClient).toContain('let maintenance: MaintenanceConfig?');
    expect(featureFlagsClient).toContain('workoutsEnabled');
    expect(featureFlagsClient).toContain('waterTrackingEnabled');
  });
});
