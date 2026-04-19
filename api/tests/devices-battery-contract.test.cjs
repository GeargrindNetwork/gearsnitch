const fs = require('node:fs');
const path = require('node:path');

const repoRoot = path.join(__dirname, '..', '..');

function read(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

/**
 * Contract test for BLE battery-level support (backlog item #17).
 *
 * Verifies:
 *   - Device model exposes `lastBatteryLevel`, `lastBatteryReadAt`, and
 *     `lastLowBatteryNotifiedAt` with the expected persistence behavior.
 *   - `PATCH /devices/:id/battery` is mounted, authenticated, validated,
 *     and wired to the push-notification queue.
 *   - The 20% threshold and 12h cooldown helpers are exported for the
 *     runtime test to import.
 *   - iOS side exposes the `BatteryLevelReader` + UI treatments.
 */
describe('BLE battery level (item #17) contract', () => {
  const deviceModel = read('api/src/models/Device.ts');
  const deviceRoutes = read('api/src/modules/devices/routes.ts');
  const batteryReader = read('client-ios/GearSnitch/Core/BLE/BatteryLevelReader.swift');
  const deviceDetailView = read('client-ios/GearSnitch/Features/Devices/DeviceDetailView.swift');
  const bleManager = read('client-ios/GearSnitch/Core/BLE/BLEManager.swift');

  test('Device model adds battery telemetry fields', () => {
    expect(deviceModel).toContain('lastBatteryLevel?: number | null;');
    expect(deviceModel).toContain('lastBatteryReadAt?: Date | null;');
    expect(deviceModel).toContain('lastLowBatteryNotifiedAt?: Date | null;');
    expect(deviceModel).toContain('lastBatteryLevel:');
    expect(deviceModel).toContain('lastBatteryReadAt:');
    expect(deviceModel).toContain('lastLowBatteryNotifiedAt:');
    expect(deviceModel).toContain('min: 0,');
    expect(deviceModel).toContain('max: 100,');
  });

  test('PATCH /devices/:id/battery is mounted and authenticated', () => {
    expect(deviceRoutes).toContain("router.patch(\n  '/:id/battery',");
    expect(deviceRoutes).toContain('validateBody(updateBatterySchema)');
    expect(deviceRoutes).toMatch(
      /router\.patch\(\s*'\/\:id\/battery',\s*isAuthenticated/
    );
  });

  test('battery route enqueues low-battery push with 12h cooldown', () => {
    expect(deviceRoutes).toContain('LOW_BATTERY_THRESHOLD');
    expect(deviceRoutes).toContain('LOW_BATTERY_COOLDOWN_MS');
    expect(deviceRoutes).toContain('shouldSendLowBatteryPush');
    expect(deviceRoutes).toContain("type: 'device_low_battery'");
    expect(deviceRoutes).toContain('Low battery on ');
    expect(deviceRoutes).toContain('Tap to dismiss');
    expect(deviceRoutes).toContain('enqueuePushNotification');
    expect(deviceRoutes).toContain('lastLowBatteryNotifiedAt');
  });

  test('shouldSendLowBatteryPush helper is exported', () => {
    expect(deviceRoutes).toContain('export function shouldSendLowBatteryPush');
    expect(deviceRoutes).toContain('export const LOW_BATTERY_THRESHOLD');
    expect(deviceRoutes).toContain('export const LOW_BATTERY_COOLDOWN_MS');
  });

  test('iOS BatteryLevelReader exposes the expected GATT UUIDs', () => {
    expect(batteryReader).toContain('CBUUID(string: "180F")');
    expect(batteryReader).toContain('CBUUID(string: "2A19")');
    expect(batteryReader).toContain('@Published private(set) var readings: [UUID: BatteryReading]');
    expect(batteryReader).toContain('static let lowBatteryThreshold = 20');
    expect(batteryReader).toContain('static let postRateLimit: TimeInterval = 5 * 60');
    expect(batteryReader).toContain('static func decodeBatteryLevel(from data: Data) -> Int?');
    expect(batteryReader).toContain('static func crossedLowBattery(');
  });

  test('DeviceDetailView renders battery icon + percentage', () => {
    expect(deviceDetailView).toContain('batteryReader.readings');
    expect(deviceDetailView).toContain('batteryBadge(');
    expect(deviceDetailView).toContain('batterySymbol(for:');
    expect(deviceDetailView).toContain('"battery.100"');
    expect(deviceDetailView).toContain('"battery.75"');
    expect(deviceDetailView).toContain('"battery.50"');
    expect(deviceDetailView).toContain('"battery.25"');
    expect(deviceDetailView).toContain('"battery.0"');
    expect(deviceDetailView).toContain('"battery.0percent"');
    expect(deviceDetailView).toContain('.gsEmerald');
    expect(deviceDetailView).toContain('.gsWarning');
    expect(deviceDetailView).toContain('.gsDanger');
    expect(deviceDetailView).toContain('Battery last read');
  });

  test('BLEManager wires BatteryLevelReader into connection lifecycle', () => {
    expect(bleManager).toContain('let batteryLevelReader = BatteryLevelReader()');
    expect(bleManager).toContain('self.batteryLevelReader.observe(peripheral: peripheral)');
    expect(bleManager).toContain('self.batteryLevelReader.stopObserving(peripheralIdentifier: peripheral.identifier)');
    expect(bleManager).toContain('didDiscoverServices');
    expect(bleManager).toContain('didDiscoverCharacteristicsFor');
    expect(bleManager).toContain('didUpdateValueFor characteristic');
  });
});
