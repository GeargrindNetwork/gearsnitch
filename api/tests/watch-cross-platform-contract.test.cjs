const fs = require('node:fs');
const path = require('node:path');

const apiRoot = path.join(__dirname, '..');
const repoRoot = path.join(apiRoot, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

function readRepo(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

describe('Apple Watch and cross-platform contract', () => {
  const deviceModel = read('src/models/Device.ts');
  const eventLogModel = read('src/models/EventLog.ts');
  const sharedSchemas = readRepo('shared/src/schemas/index.ts');

  test('Device model supports watch type', () => {
    expect(deviceModel).toContain("'watch'");
    expect(deviceModel).toMatch(/enum:.*\[.*'watch'.*\]/s);
  });

  test('EventLog model supports watchos source', () => {
    expect(eventLogModel).toContain("'watchos'");
    expect(eventLogModel).toMatch(/enum:.*\[.*'watchos'.*\]/s);
  });

  test('shared device schema includes watch type', () => {
    expect(sharedSchemas).toMatch(/z\.enum\(\[.*'watch'.*\]\)/s);
  });
});

describe('disconnect protection contract', () => {
  const bleManager = readRepo('client-ios/GearSnitch/Core/BLE/BLEManager.swift');
  const disconnectAttributes = readRepo('client-ios/GearSnitch/Shared/Widgets/DisconnectProtectionAttributes.swift');
  const intentFile = readRepo('client-ios/GearSnitch/Features/Widgets/GymSessionIntent.swift');
  const widgetSyncStore = readRepo('client-ios/GearSnitch/Core/Widgets/WidgetSyncStore.swift');

  test('reconnection timeout is 20 seconds', () => {
    expect(bleManager).toContain('reconnectionTimeout: TimeInterval = 20');
  });

  test('arming protection starts the Dynamic Island Live Activity', () => {
    expect(bleManager).toContain('DisconnectProtectionActivityManager.shared.startActivity');
  });

  test('disarming protection ends the Dynamic Island Live Activity', () => {
    expect(bleManager).toContain('DisconnectProtectionActivityManager.shared.endActivity');
  });

  test('end session does not disarm disconnect protection', () => {
    const gymSessionManager = readRepo('client-ios/GearSnitch/Core/Session/GymSessionManager.swift');
    // The endSession method should NOT call disarmDisconnectProtection
    const endSessionBlock = gymSessionManager.split('func endSession')[1]?.split('func ')[0] || '';
    expect(endSessionBlock).not.toContain('disarmDisconnectProtection');
  });

  test('DisconnectProtectionAttributes includes countdown and device name fields', () => {
    expect(disconnectAttributes).toContain('countdownSeconds: Int?');
    expect(disconnectAttributes).toContain('disconnectedDeviceName: String?');
  });

  test('DisarmProtectionIntent exists for widget-based disarming', () => {
    expect(intentFile).toContain('struct DisarmProtectionIntent: AppIntent');
    expect(intentFile).toContain('disarmProtection');
  });

  test('WidgetSyncStore supports disarmProtection action', () => {
    expect(widgetSyncStore).toContain('case disarmProtection');
  });
});

describe('Watch app structure', () => {
  const watchApp = readRepo('client-ios/GearSnitchWatch/GearSnitchWatchApp.swift');
  const contentView = readRepo('client-ios/GearSnitchWatch/ContentView.swift');
  const watchSessionManager = readRepo('client-ios/GearSnitchWatch/WatchSessionManager.swift');
  const projectYml = readRepo('client-ios/project.yml');

  test('Watch app entry point exists with WatchSessionManager', () => {
    expect(watchApp).toContain('@main');
    expect(watchApp).toContain('WatchSessionManager');
  });

  test('Watch content view has 4 tabs', () => {
    expect(contentView).toContain('HeartRateView()');
    expect(contentView).toContain('SessionView()');
    expect(contentView).toContain('AlertsView()');
    expect(contentView).toContain('QuickActionsView()');
  });

  test('WatchSessionManager uses WatchConnectivity and no iOS-only frameworks', () => {
    expect(watchSessionManager).toContain('import WatchConnectivity');
    expect(watchSessionManager).not.toContain('import UIKit');
    expect(watchSessionManager).not.toContain('import CoreBluetooth');
  });

  test('WatchSessionManager implements WCSessionDelegate', () => {
    expect(watchSessionManager).toContain('WCSessionDelegate');
    expect(watchSessionManager).toContain('func session');
  });

  test('project.yml includes GearSnitchWatch target', () => {
    expect(projectYml).toContain('GearSnitchWatch:');
    expect(projectYml).toContain('platform: watchOS');
    expect(projectYml).toContain('com.gearsnitch.app.watchkitapp');
  });
});
