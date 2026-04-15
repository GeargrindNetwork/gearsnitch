const fs = require('node:fs');
const path = require('node:path');

const repoRoot = path.join(__dirname, '..', '..');

function readRepo(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

describe('subscription screen overhaul', () => {
  const subscriptionCards = readRepo('client-ios/GearSnitch/Features/Onboarding/SubscriptionCardsView.swift');

  test('subscription cards use vertical scroll instead of horizontal', () => {
    expect(subscriptionCards).toContain('ScrollView(.vertical');
    expect(subscriptionCards).not.toContain('ScrollView(.horizontal');
  });

  test('subscription tiers are ordered HUSTLE, HWMF, BABY MOMMA', () => {
    expect(subscriptionCards).toContain('[SubscriptionTier.hustle, .hwmf, .babyMomma]');
  });

  test('subscription tier has upgradeOrder property', () => {
    expect(subscriptionCards).toContain('var upgradeOrder: Int');
  });

  test('current plan badge is shown for active tier', () => {
    expect(subscriptionCards).toContain('"Current Plan"');
    expect(subscriptionCards).toContain('storeKit.currentTier == tier');
  });

  test('upgrade button title is used for higher tiers', () => {
    expect(subscriptionCards).toContain('return "Upgrade"');
  });

  test('downgrade buttons are disabled', () => {
    expect(subscriptionCards).toContain('tier.upgradeOrder < current.upgradeOrder');
  });
});

describe('floating hamburger menu', () => {
  const floatingMenu = readRepo('client-ios/GearSnitch/App/FloatingMenuView.swift');
  const mainTabView = readRepo('client-ios/GearSnitch/App/MainTabView.swift');

  test('floating menu exists with hamburger button', () => {
    expect(floatingMenu).toContain('FloatingMenuView');
    expect(floatingMenu).toContain('line.3.horizontal');
    expect(floatingMenu).toContain('xmark');
  });

  test('floating menu includes all 5 standard tabs', () => {
    expect(floatingMenu).toContain('.dashboard');
    expect(floatingMenu).toContain('.workouts');
    expect(floatingMenu).toContain('.health');
    expect(floatingMenu).toContain('.store');
    expect(floatingMenu).toContain('.profile');
  });

  test('floating menu includes hospitals and labs buttons', () => {
    expect(floatingMenu).toContain('Hospitals');
    expect(floatingMenu).toContain('Labs');
    expect(floatingMenu).toContain('cross.case.fill');
    expect(floatingMenu).toContain('staroflife.fill');
  });

  test('MainTabView uses FloatingMenuView instead of TabView', () => {
    expect(mainTabView).toContain('FloatingMenuView');
    expect(mainTabView).not.toMatch(/TabView\(selection:/);
  });

  test('MainTabView shows hospitals and labs as fullScreenCover', () => {
    expect(mainTabView).toContain('NearestHospitalsView');
    expect(mainTabView).toContain('ScheduleLabsView');
    expect(mainTabView).toContain('fullScreenCover');
  });
});

describe('device and gym deduplication', () => {
  const pairingFlow = readRepo('client-ios/GearSnitch/Features/Devices/DevicePairingFlowView.swift');
  const onboardingView = readRepo('client-ios/GearSnitch/Features/Onboarding/OnboardingView.swift');

  test('pairing flow checks for duplicate devices via persistedId', () => {
    expect(pairingFlow).toContain('persistedId != nil');
    expect(pairingFlow).toContain('already saved to your account');
  });

  test('pairing flow loads saved devices from backend', () => {
    expect(pairingFlow).toContain('savedDevices');
    expect(pairingFlow).toContain('APIEndpoint.Devices.list');
  });

  test('pairing flow shows previously saved devices section', () => {
    expect(pairingFlow).toContain('"Previously Saved"');
    expect(pairingFlow).toContain('savedDeviceCard');
  });

  test('onboarding gym save checks for duplicates by proximity', () => {
    expect(onboardingView).toContain('duplicateThresholdMeters');
    expect(onboardingView).toContain('gym.name.lowercased() == name.lowercased()');
  });

  test('onboarding gym screen loads and shows saved gyms', () => {
    expect(onboardingView).toContain('savedGyms');
    expect(onboardingView).toContain('savedGymsCard');
    expect(onboardingView).toContain('"Your Saved Gyms"');
  });
});

describe('dashboard reorganization', () => {
  const dashboard = readRepo('client-ios/GearSnitch/Features/Dashboard/DashboardView.swift');
  const profile = readRepo('client-ios/GearSnitch/Features/Profile/ProfileView.swift');
  const settings = readRepo('client-ios/GearSnitch/Features/Settings/SettingsView.swift');

  test('dashboard body uses HeartRateMonitorCard', () => {
    expect(dashboard).toContain('HeartRateMonitorCard()');
    // The body should reference HeartRateMonitorCard, not deviceStatusSection
    const bodySection = dashboard.split('var body: some View')[1]?.split('// MARK:')[0] || '';
    expect(bodySection).toContain('HeartRateMonitorCard');
    expect(bodySection).not.toContain('deviceStatusSection');
  });

  test('dashboard has disarm button in toolbar', () => {
    expect(dashboard).toContain('isDisconnectProtectionArmed');
    expect(dashboard).toContain('"Disarm"');
    expect(dashboard).toContain('lock.open.fill');
  });

  test('profile screen has devices section with See All', () => {
    expect(profile).toContain('devicesSectionView');
    expect(profile).toContain('"See All"');
    expect(profile).toContain('DeviceListView');
  });

  test('profile auto-imports Apple Health data on load', () => {
    expect(profile).toContain('importFromHealthKit');
    expect(profile).toMatch(/\.task\s*\{[\s\S]*importFromHealthKit/);
  });

  test('settings screen has gym management', () => {
    expect(settings).toContain('"Manage Gyms"');
    expect(settings).toContain('GymListView');
  });

  test('settings screen has lost item scanner', () => {
    expect(settings).toContain('"Lost Item Scanner"');
    expect(settings).toContain('LostItemScannerView');
  });
});

describe('health trends screen', () => {
  const trendsView = readRepo('client-ios/GearSnitch/Features/Health/TrendsView.swift');
  const trendsVM = readRepo('client-ios/GearSnitch/Features/Health/TrendsViewModel.swift');
  const healthDashboard = readRepo('client-ios/GearSnitch/Features/Health/HealthDashboardView.swift');

  test('trends view has 6 chart sections', () => {
    expect(trendsView).toContain('hrScatterChart');
    expect(trendsView).toContain('restingHRChart');
    expect(trendsView).toContain('hrvChart');
    expect(trendsView).toContain('workoutChart');
    expect(trendsView).toContain('weightChart');
    expect(trendsView).toContain('caloriesChart');
  });

  test('trends view has time range picker with 7D/30D/90D', () => {
    expect(trendsView).toContain('TrendsTimeRange');
    expect(trendsView).toContain('timeRangePicker');
  });

  test('trends view model queries HealthKit for all data types', () => {
    expect(trendsVM).toContain('.heartRate');
    expect(trendsVM).toContain('.restingHeartRate');
    expect(trendsVM).toContain('.heartRateVariabilitySDNN');
    expect(trendsVM).toContain('.bodyMass');
    expect(trendsVM).toContain('.activeEnergyBurned');
    expect(trendsVM).toContain('.workoutType()');
  });

  test('health dashboard has tappable trends card', () => {
    expect(healthDashboard).toContain('TrendsView');
    expect(healthDashboard).toContain('trendsCard');
    expect(healthDashboard).toContain('"Trends"');
  });
});

describe('lost item scanner', () => {
  const scanner = readRepo('client-ios/GearSnitch/Features/Devices/LostItemScannerView.swift');

  test('scanner uses NearbyInteraction for UWB direction', () => {
    expect(scanner).toContain('import NearbyInteraction');
    expect(scanner).toContain('NISession');
    expect(scanner).toContain('NISessionDelegate');
  });

  test('scanner has RSSI-based proximity classification', () => {
    expect(scanner).toContain('ProximityLevel');
    expect(scanner).toContain('.immediate');
    expect(scanner).toContain('.near');
    expect(scanner).toContain('.medium');
    expect(scanner).toContain('.far');
  });

  test('scanner has radial edge glow', () => {
    expect(scanner).toContain('RadialGradient');
    expect(scanner).toContain('radialGlow');
    expect(scanner).toContain('proximityColor');
  });

  test('scanner estimates distance from RSSI', () => {
    expect(scanner).toContain('estimatedDistance');
    expect(scanner).toContain('txPower');
    expect(scanner).toContain('path loss');
  });
});

describe('disconnect alert overlay', () => {
  const overlay = readRepo('client-ios/GearSnitch/Features/Devices/DisconnectAlertOverlay.swift');

  test('overlay has 3-phase flow', () => {
    expect(overlay).toContain('DisconnectAlertPhase');
    expect(overlay).toContain('case countdown');
    expect(overlay).toContain('case silencePrompt');
    expect(overlay).toContain('case actionChoice');
  });

  test('overlay has silence, track, and disregard buttons', () => {
    expect(overlay).toContain('"Silence Alarm"');
    expect(overlay).toContain('"Track Item"');
    expect(overlay).toContain('"Disregard"');
  });

  test('overlay auto-clears on device reconnect', () => {
    expect(overlay).toContain('connected.contains(deviceIdentifier)');
    expect(overlay).toContain('onDismissed');
  });

  test('overlay uses PanicAlarmManager with correct method names', () => {
    expect(overlay).toContain('silencePanic()');
    expect(overlay).toContain('triggerPanic(device:');
  });
});

describe('web health components', () => {
  const hrCard = readRepo('web/src/components/metrics/HeartRateSummaryCard.tsx');
  const devicesCard = readRepo('web/src/components/metrics/ConnectedDevicesCard.tsx');
  const sourcesCard = readRepo('web/src/components/metrics/HealthSourcesCard.tsx');
  const trendsSection = readRepo('web/src/components/metrics/HealthTrendsSection.tsx');
  const metricsPage = readRepo('web/src/pages/MetricsPage.tsx');
  const apiLib = readRepo('web/src/lib/api.ts');

  test('web API exports health dashboard and trends functions', () => {
    expect(apiLib).toContain('export async function getHealthDashboard');
    expect(apiLib).toContain('export async function getHealthTrends');
    expect(apiLib).toContain('HealthDashboardResponse');
    expect(apiLib).toContain('HealthTrendsResponse');
  });

  test('MetricsPage imports all health components', () => {
    expect(metricsPage).toContain('HeartRateSummaryCard');
    expect(metricsPage).toContain('ConnectedDevicesCard');
    expect(metricsPage).toContain('HealthSourcesCard');
    expect(metricsPage).toContain('HealthTrendsSection');
  });

  test('HeartRateSummaryCard renders zone distribution', () => {
    expect(hrCard).toContain('zoneDistribution');
    expect(hrCard).toContain('ZONE_CONFIG');
  });

  test('ConnectedDevicesCard renders device type icons', () => {
    expect(devicesCard).toContain('deviceIcon');
    expect(devicesCard).toContain('healthCapable');
  });

  test('HealthTrendsSection has time range picker and scatter plot', () => {
    expect(trendsSection).toContain('ScatterPlot');
    expect(trendsSection).toContain('getHealthTrends');
    expect(trendsSection).toMatch(/\[7, 30, 90\]/);
  });
});
