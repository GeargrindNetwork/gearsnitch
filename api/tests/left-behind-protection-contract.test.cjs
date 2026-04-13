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
  const notificationRoutes = readFromApi('src/modules/notifications/routes.ts');
  const apiEndpoints = readFromRepo('client-ios/GearSnitch/Core/Network/APIEndpoint.swift');
  const notificationPreferencesView = readFromRepo(
    'client-ios/GearSnitch/Features/Settings/NotificationPreferencesView.swift',
  );
  const bleManager = readFromRepo('client-ios/GearSnitch/Core/BLE/BLEManager.swift');
  const panicAlarmManager = readFromRepo('client-ios/GearSnitch/Core/BLE/PanicAlarmManager.swift');
  const pushNotificationHandler = readFromRepo(
    'client-ios/GearSnitch/Core/Notifications/PushNotificationHandler.swift',
  );

  test('backend exposes disconnect alert ingestion and persisted notification preference routes', () => {
    expect(alertRoutes).toContain("router.post('/device-disconnected'");
    expect(alertRoutes).toContain("type: 'device_disconnected'");
    expect(alertRoutes).toContain("type: { $in: ['disconnect_warning', 'device_disconnected'] }");
    expect(notificationRoutes).toContain("router.get('/preferences', isAuthenticated");
    expect(notificationRoutes).toContain("router.patch('/preferences', isAuthenticated");
    expect(notificationRoutes).toContain('panicAlertsEnabled: z.boolean().optional(),');
    expect(notificationRoutes).toContain('disconnectAlertsEnabled: z.boolean().optional(),');
  });

  test('iOS exposes disconnect alert endpoints and notification controls', () => {
    expect(apiEndpoints).toContain('static func deviceDisconnected(_ body: DeviceDisconnectedBody) -> APIEndpoint');
    expect(apiEndpoints).toContain('path: "/api/v1/alerts/device-disconnected"');
    expect(notificationPreferencesView).toContain('.navigationTitle("Notifications")');
    expect(notificationPreferencesView).toContain('notifToggle("Device Disconnected"');
    expect(notificationPreferencesView).toContain('notifToggle("Left Safe Zone"');
    expect(notificationPreferencesView).toContain('notifToggle("Low Battery"');
    expect(notificationPreferencesView).toContain('UpdateUserBody(preferences: prefs)');
    expect(notificationPreferencesView).toContain('APIEndpoint.Users.updateMe(body)');
  });

  test('disconnect and panic paths wire local feedback, push categories, and backend fanout', () => {
    expect(pushNotificationHandler).toContain('case deviceDisconnect = "DEVICE_DISCONNECT"');
    expect(pushNotificationHandler).toContain('case viewDevice = "VIEW_DEVICE"');
    expect(pushNotificationHandler).toContain('postDeepLink(.device(id: deviceId))');
    expect(bleManager).toContain('triggerDisconnectHaptic()');
    expect(bleManager).toContain('scheduleProtectedDisconnectAlert(for: device)');
    expect(bleManager).toContain('content.categoryIdentifier = NotificationCategory.deviceDisconnect.rawValue');
    expect(bleManager).toContain('APIEndpoint.Alerts.deviceDisconnected(body)');
    expect(panicAlarmManager).toContain('func triggerPanic(device: BLEDevice)');
    expect(panicAlarmManager).toContain('APIEndpoint.Alerts.deviceDisconnected(body)');
    expect(panicAlarmManager).toContain('sendWatchAlarm(deviceName: device.displayName)');
  });
});
