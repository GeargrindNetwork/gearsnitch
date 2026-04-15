const fs = require('node:fs');
const path = require('node:path');

const repoRoot = path.join(__dirname, '..', '..');

function read(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

describe('device priority and disconnect UX regression sweep', () => {
  const deviceModel = read('api/src/models/Device.ts');
  const deviceService = read('api/src/modules/devices/deviceService.ts');
  const deviceRoutes = read('api/src/modules/devices/routes.ts');
  const deviceListViewModel = read('client-ios/GearSnitch/Features/Devices/DeviceListViewModel.swift');
  const deviceDetailViewModel = read('client-ios/GearSnitch/Features/Devices/DeviceDetailViewModel.swift');
  const deviceListView = read('client-ios/GearSnitch/Features/Devices/DeviceListView.swift');
  const deviceDetailView = read('client-ios/GearSnitch/Features/Devices/DeviceDetailView.swift');
  const devicePairingFlowView = read('client-ios/GearSnitch/Features/Devices/DevicePairingFlowView.swift');
  const dashboardView = read('client-ios/GearSnitch/Features/Dashboard/DashboardView.swift');
  const bleDevice = read('client-ios/GearSnitch/Core/BLE/BLEDevice.swift');
  const bleManager = read('client-ios/GearSnitch/Core/BLE/BLEManager.swift');
  const bleSignalMonitor = read('client-ios/GearSnitch/Core/BLE/BLESignalMonitor.swift');
  const gymSessionManager = read('client-ios/GearSnitch/Core/Session/GymSessionManager.swift');

  test('device contract persists nickname and favorite metadata', () => {
    expect(deviceModel).toContain('nickname?: string | null;');
    expect(deviceModel).toContain('isFavorite: boolean;');
    expect(deviceModel).toContain("nickname: { type: String, default: null }");
    expect(deviceModel).toContain("isFavorite: { type: Boolean, default: false }");
    expect(deviceModel).toContain("default: undefined");
    expect(deviceModel).not.toContain("default: 'Point'");
    expect(deviceService).toContain('nickname: device.nickname ?? null,');
    expect(deviceService).toContain('isFavorite: device.isFavorite === true,');
    expect(deviceService).toContain(".sort({ isFavorite: -1, updatedAt: -1, createdAt: -1 });");
    expect(deviceService).toContain('const shouldPinDevice =');
    expect(deviceService).toContain('await this.clearPinnedDevices(normalizedUserId, device._id);');
    expect(deviceRoutes).toContain('nickname: z.preprocess(');
    expect(deviceRoutes).toContain('isFavorite: z.boolean().optional(),');
  });

  test('iOS device surfaces wire priority metadata through DTOs and controls', () => {
    expect(deviceListViewModel).toContain('let nickname: String?');
    expect(deviceListViewModel).toContain('let isFavorite: Bool');
    expect(deviceListViewModel).toContain('var priorityMetadata: PersistedBLEDeviceMetadata');
    expect(deviceDetailViewModel).toContain('func updatePriority(');
    expect(deviceDetailView).toContain('Text(device.displayName)');
    expect(deviceDetailView).toContain('Text("Pinned Device")');
    expect(deviceDetailView).toContain('showRenameSheet = true');
    expect(deviceListView).toContain('device.displayName');
    expect(deviceListView).toContain('if device.isFavorite {');
    expect(devicePairingFlowView).toContain('Toggle(isOn: $pinDevice)');
    expect(devicePairingFlowView).toContain('let savedDevice: DeviceDTO = try await APIClient.shared.request(');
  });

  test('BLE manager uses persisted metadata and an explicit disconnect decision path', () => {
    expect(bleDevice).toContain('var persistedId: String?');
    expect(bleDevice).toContain('@Published var preferredName: String?');
    expect(bleDevice).toContain('@Published var isFavorite: Bool');
    expect(bleDevice).toContain('var displayName: String {');
    expect(bleManager).toContain('struct PersistedBLEDeviceMetadata');
    expect(bleManager).toContain('@Published private(set) var pendingDisconnectPrompt');
    expect(bleManager).toContain('func replacePersistedMetadata(');
    expect(bleManager).toContain('func upsertPersistedMetadata(');
    expect(bleManager).toContain('func resolvePendingDisconnectAsEndedSession()');
    expect(bleManager).toContain('func resolvePendingDisconnectAsLostGear()');
    expect(bleManager).toContain('func startScanning(mode: BLEScanMode = .monitoring)');
    expect(bleManager).toContain('CBCentralManagerScanOptionAllowDuplicatesKey: mode.allowsDuplicates');
    expect(bleManager).toContain('awaiting user decision');
    expect(bleManager).not.toContain('triggering panic');
  });

  test('disconnect UX uses overlay with silence/track/disregard flow', () => {
    expect(dashboardView).toContain('DisconnectAlertOverlay');
    expect(dashboardView).toContain('onTrackItem');
    expect(dashboardView).toContain('onDisregard');
    expect(dashboardView).toContain('onDismissed');
    expect(gymSessionManager).toContain('BLEManager.shared.disconnectAll()');
    expect(bleSignalMonitor).toContain('case -67 ... 0:      return .strong');
    expect(bleSignalMonitor).toContain('case -76 ..< -67:    return .moderate');
    expect(bleSignalMonitor).toContain('return rssi >= -72 ? .moderate : previous');
    expect(bleSignalMonitor).toContain('case .moderate: return nil');
    expect(bleSignalMonitor).toContain('case .critical: return 2.5');
  });
});
