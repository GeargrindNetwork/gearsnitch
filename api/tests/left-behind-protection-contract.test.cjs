const fs = require('node:fs');
const path = require('node:path');

const apiRoot = path.join(__dirname, '..');
const repoRoot = path.join(apiRoot, '..');

function readFromApi(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

function readFromRepo(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

describe('left-behind protection contract', () => {
  const alertRoutes = readFromApi('src/modules/alerts/routes.ts');
  const apiEndpoints = readFromRepo('client-ios/GearSnitch/Core/Network/APIEndpoint.swift');
  const notificationPreferencesView = readFromRepo(
    'client-ios/GearSnitch/Features/Settings/NotificationPreferencesView.swift',
  );
  const bleManager = readFromRepo('client-ios/GearSnitch/Core/BLE/BLEManager.swift');
  const bleSignalMonitor = readFromRepo('client-ios/GearSnitch/Core/BLE/BLESignalMonitor.swift');
  const panicAlarmManager = readFromRepo('client-ios/GearSnitch/Core/BLE/PanicAlarmManager.swift');
  const pushNotificationHandler = readFromRepo(
    'client-ios/GearSnitch/Core/Notifications/PushNotificationHandler.swift',
  );
  const rootView = readFromRepo('client-ios/GearSnitch/App/RootView.swift');

  test('backend exposes a distinct panic alarm route and queues alert fanout jobs', () => {
    expect(alertRoutes).toContain("router.post('/panic-alarm'");
    expect(alertRoutes).toContain("type: 'panic_alarm'");
    expect(alertRoutes).toContain('enqueueAlertFanout(');
    expect(alertRoutes).toContain("type: 'device_disconnected'");
  });

  test('iOS exposes protection preference APIs and in-app controls', () => {
    expect(apiEndpoints).toContain('static var preferences: APIEndpoint');
    expect(apiEndpoints).toContain('static func updatePreferences(');
    expect(notificationPreferencesView).toContain('Left-Behind Protection');
    expect(notificationPreferencesView).toContain('Disconnect Haptics');
    expect(notificationPreferencesView).toContain('Disconnect Sound');
    expect(notificationPreferencesView).toContain('Flash Screen');
  });

  test('disconnect and panic paths wire local feedback and flash presentation', () => {
    expect(pushNotificationHandler).toContain('func scheduleLocalDisconnectAlert(');
    expect(pushNotificationHandler).toContain('func scheduleLocalPanicAlert(');
    expect(bleManager).toContain('scheduleLocalDisconnectAlert');
    expect(bleSignalMonitor).toContain('ProtectionPreferencesStore.shared');
    expect(panicAlarmManager).toContain('APIEndpoint.Alerts.panicAlarm');
    expect(rootView).toContain('PanicAlarmOverlay');
  });
});
