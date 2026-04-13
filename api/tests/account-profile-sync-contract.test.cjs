const fs = require('node:fs');
const path = require('node:path');

const repoRoot = path.join(__dirname, '..', '..');

function read(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

describe('account profile sync regression sweep', () => {
  const userModel = read('api/src/models/User.ts');
  const userRoutes = read('api/src/modules/users/routes.ts');
  const authRoutes = read('api/src/modules/auth/routes.ts');
  const permissionsUtil = read('api/src/utils/permissionsState.ts');
  const responseDecoder = read('client-ios/GearSnitch/Core/Network/ResponseDecoder.swift');
  const sharedUser = read('client-ios/GearSnitch/Shared/Models/User.swift');
  const onboardingViewModel = read('client-ios/GearSnitch/Features/Onboarding/OnboardingViewModel.swift');
  const accountPage = read('web/src/pages/AccountPage.tsx');

  test('backend normalizes and exposes permission, gym, and pinned-device state', () => {
    expect(userModel).toContain('backgroundLocation');
    expect(userModel).toContain('healthKit');
    expect(permissionsUtil).toContain('normalizePermissionsState');
    expect(userRoutes).toContain('permissionsState: z.object({');
    expect(userRoutes).toContain('pinnedDeviceId:');
    expect(userRoutes).toContain('function serializeProfileDeviceSummary');
    expect(userRoutes).toContain('bluetoothIdentifier: device.identifier');
    expect(userRoutes).toContain('isMonitoring: device.monitoringEnabled === true');
    expect(userRoutes).toContain('lastSeenAt: toIsoString(device.lastSeenAt)');
    expect(userRoutes).toContain('exportVersion: 2');
    expect(userRoutes).toContain('gyms: gyms.map(serializeGymSummary)');
    expect(userRoutes).toContain('defaultGym:');
    expect(userRoutes).toContain('onboarding: {');
    expect(authRoutes).toContain('permissionsState: normalizePermissionsState(user.permissionsState)');
    expect(authRoutes).toContain('subscriptionTier:');
    expect(authRoutes).toContain('subscription: buildSubscriptionSummary(subscription)');
  });

  test('iOS auth and onboarding sync server-backed account state', () => {
    expect(responseDecoder).toContain('let defaultGymId: String?');
    expect(responseDecoder).toContain('let onboardingCompletedAt: Date?');
    expect(responseDecoder).toContain('let permissionsState: PermissionsState?');
    expect(sharedUser).toContain('let backgroundLocation: PermissionStatus?');
    expect(sharedUser).toContain('defaultGymId: dto.defaultGymId');
    expect(sharedUser).toContain('onboardingCompletedAt: dto.onboardingCompletedAt');
    expect(onboardingViewModel).toContain('permissionsState: currentPermissionsStatePayload()');
    expect(onboardingViewModel).toContain('private func syncPermissionsState() async');
  });

  test('web account page is typed for the richer synced profile', () => {
    expect(accountPage).toContain("subscriptionTier: 'monthly' | 'annual' | 'lifetime' | 'free';");
    expect(accountPage).toContain('permissionsState?: {');
    expect(accountPage).toContain('purchaseDate?: string | null;');
    expect(accountPage).toContain('pinnedDeviceId?: string | null;');
    expect(accountPage).toContain('name: string;');
    expect(accountPage).toContain('type: string;');
    expect(accountPage).toContain('lastSeenAt?: string | null;');
    expect(accountPage).toContain('device.nickname || device.name');
    expect(accountPage).toContain('gyms?: Array<{');
    expect(accountPage).toContain('App Permissions');
    expect(accountPage).toContain('Gyms');
  });
});
