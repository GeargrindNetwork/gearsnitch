import Foundation
import CoreBluetooth
import os
import UIKit
import UserNotifications

// MARK: - BLE Manager

struct PersistedBLEDeviceMetadata {
    let id: String
    let bluetoothIdentifier: String
    let nickname: String?
    let isFavorite: Bool
}

struct DisconnectDecisionPrompt: Identifiable {
    let id: String
    let deviceIdentifier: UUID
    let deviceName: String
    let lastSeenAt: Date?
}

enum BLEScanMode {
    case discovery
    case monitoring

    var allowsDuplicates: Bool {
        switch self {
        case .discovery:
            return false
        case .monitoring:
            return true
        }
    }

    var timeout: TimeInterval? {
        switch self {
        case .discovery:
            return AppConfig.bleScanTimeout
        case .monitoring:
            return nil
        }
    }
}

/// Central BLE manager handling scanning, connection, reconnection, and
/// state restoration for GearSnitch device peripherals.
@MainActor
final class BLEManager: NSObject, ObservableObject {

    static let shared = BLEManager()

    // MARK: - Constants

    private static let restorationIdentifier = "com.gearsnitch.ble.central"
    private static let reconnectionTimeout: TimeInterval = 20
    private static let reconnectionTimerInterval: TimeInterval = 1
    private static let protectedDisconnectNotificationPrefix = "protected-disconnect-"

    /// Service UUIDs the app monitors. Register these in Info.plist under
    /// `UIBackgroundModes` -> `bluetooth-central` for background BLE.
    static let registeredServiceUUIDs: [CBUUID] = AppConfig.bleServiceUUIDs

    // MARK: - Published State

    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var discoveredDevices: [BLEDevice] = []
    @Published private(set) var connectedDevices: [BLEDevice] = []
    @Published private(set) var isScanning = false
    @Published private(set) var pendingDisconnectPrompt: DisconnectDecisionPrompt?
    @Published private(set) var isDisconnectProtectionArmed = false
    @Published private(set) var armedGymId: String?

    // MARK: - Private Properties

    private var centralManager: CBCentralManager?
    private let scanner = BLEScanner()
    private let logger = Logger(subsystem: "com.gearsnitch", category: "BLEManager")

    /// Reads the standard BLE Battery Service (0x180F) on every connected
    /// peripheral and surfaces readings for `DeviceDetailView`. See
    /// `BatteryLevelReader.swift`. Lazily initialised so tests that don't
    /// need BLE don't allocate it.
    let batteryLevelReader = BatteryLevelReader()

    /// Buffers per-device RSSI samples captured during discovery /
    /// reads and POSTs them to the backend in 5-min / 20-sample
    /// batches. See `RssiSampleBuffer.swift` + backlog item #19.
    let rssiSampleBuffer = RssiSampleBuffer()

    /// Tracks reconnection timers per device identifier.
    private var reconnectionTimers: [UUID: ReconnectionState] = [:]
    private var persistedMetadataByIdentifier: [String: PersistedBLEDeviceMetadata] = [:]
    private var scanTimeoutTask: Task<Void, Never>?
    private var stalePruningTask: Task<Void, Never>?

    // MARK: - Init

    override init() {
        super.init()

        scanner.serviceFilter = Self.registeredServiceUUIDs.isEmpty ? nil : Self.registeredServiceUUIDs
        bluetoothState = Self.derivedState(for: CBCentralManager.authorization)

        // Avoid triggering the first-use Bluetooth prompt on app launch. If the
        // user has already made a permission choice, we can safely restore the
        // manager immediately for state observation and restoration.
        if CBCentralManager.authorization != .notDetermined {
            configureCentralManager(showPowerAlert: false)
        }
    }

    // MARK: - Scanning

    /// Start scanning for BLE peripherals. Filters by registered service UUIDs
    /// when available, otherwise scans for all devices.
    func startScanning(mode: BLEScanMode = .monitoring) {
        guard let centralManager = configureCentralManagerIfAuthorized() else {
            logger.info("Skipping BLE scan until Bluetooth permission is explicitly requested")
            return
        }

        guard bluetoothState == .poweredOn else {
            logger.warning("Cannot scan: Bluetooth not powered on (state: \(self.bluetoothState.rawValue))")
            return
        }

        guard !isScanning else { return }

        scanner.reset()

        let services = Self.registeredServiceUUIDs.isEmpty ? nil : Self.registeredServiceUUIDs
        centralManager.scanForPeripherals(
            withServices: services,
            options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: mode.allowsDuplicates,
            ]
        )

        isScanning = true
        logger.info("Started BLE scanning in \(String(describing: mode)) mode")

        // Schedule periodic stale-device pruning
        scheduleStalePruning()
        scheduleScanTimeoutIfNeeded(for: mode)
    }

    /// Stop scanning for BLE peripherals.
    func stopScanning() {
        guard isScanning, let centralManager else { return }
        centralManager.stopScan()
        isScanning = false
        scanTimeoutTask?.cancel()
        scanTimeoutTask = nil
        stalePruningTask?.cancel()
        stalePruningTask = nil
        logger.info("Stopped BLE scanning")
    }

    // MARK: - Connection

    /// Connect to a discovered BLE device.
    @discardableResult
    func connect(to device: BLEDevice) -> Bool {
        guard let centralManager = configureCentralManagerIfAuthorized() else {
            logger.error("Cannot connect: Bluetooth manager unavailable before authorization")
            return false
        }

        guard let peripheral = device.peripheral else {
            logger.error("Cannot connect: no peripheral reference for \(device.name)")
            return false
        }

        device.status = .connecting
        centralManager.connect(peripheral, options: [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
        ])

        logger.info("Connecting to \(device.name)")
        return true
    }

    /// Disconnect from a connected BLE device.
    func disconnect(from device: BLEDevice) {
        guard let centralManager else { return }
        guard let peripheral = device.peripheral else { return }

        cancelReconnection(for: device.identifier)
        centralManager.cancelPeripheralConnection(peripheral)
        device.status = .disconnected

        connectedDevices.removeAll { $0.identifier == device.identifier }
        syncWidgetSnapshot()
        logger.info("Disconnected from \(device.name)")
    }

    /// Disconnect from all connected devices.
    func disconnectAll() {
        pendingDisconnectPrompt = nil
        for device in connectedDevices {
            disconnect(from: device)
        }
    }

    func replacePersistedMetadata(_ metadata: [PersistedBLEDeviceMetadata]) {
        persistedMetadataByIdentifier = Dictionary(
            uniqueKeysWithValues: metadata.map {
                (Self.normalizedIdentifier($0.bluetoothIdentifier), $0)
            }
        )
        syncKnownDeviceMetadata()
        syncWidgetSnapshot()
    }

    func upsertPersistedMetadata(_ metadata: PersistedBLEDeviceMetadata) {
        persistedMetadataByIdentifier[Self.normalizedIdentifier(metadata.bluetoothIdentifier)] = metadata
        syncKnownDeviceMetadata()
        syncWidgetSnapshot()
    }

    func dismissPendingDisconnectPrompt() {
        pendingDisconnectPrompt = nil
    }

    func armDisconnectProtection(gymId: String? = nil) {
        isDisconnectProtectionArmed = true
        armedGymId = gymId
        logger.info("Disconnect protection armed\(gymId.map { " for gym \($0)" } ?? "")")

        // Show protection indicator in Dynamic Island
        DisconnectProtectionActivityManager.shared.startActivity(gymName: nil)
    }

    func disarmDisconnectProtection(reason: String? = nil) {
        isDisconnectProtectionArmed = false
        armedGymId = nil
        pendingDisconnectPrompt = nil

        if let reason, !reason.isEmpty {
            logger.info("Disconnect protection disarmed (\(reason))")
        } else {
            logger.info("Disconnect protection disarmed")
        }

        // Remove protection indicator from Dynamic Island
        Task {
            await DisconnectProtectionActivityManager.shared.endActivity()
        }
    }

    func resolvePendingDisconnectAsEndedSession() {
        guard let prompt = pendingDisconnectPrompt else { return }
        pendingDisconnectPrompt = nil
        clearProtectedDisconnectAlert(for: prompt.deviceIdentifier)

        if let device = knownDevice(identifier: prompt.deviceIdentifier) {
            cancelReconnection(for: device.identifier)
            device.status = .disconnected
            sortKnownDevices()
        }
    }

    func resolvePendingDisconnectAsLostGear() {
        guard let prompt = pendingDisconnectPrompt else { return }
        pendingDisconnectPrompt = nil
        clearProtectedDisconnectAlert(for: prompt.deviceIdentifier)

        guard let device = knownDevice(identifier: prompt.deviceIdentifier) else { return }

        cancelReconnection(for: device.identifier)
        device.status = .lost
        sortKnownDevices()
        BLESignalMonitor.shared.reportDeviceLost(device)
        PanicAlarmManager.shared.triggerPanic(device: device)
    }

    // MARK: - Reconnection

    private func startReconnection(for device: BLEDevice) {
        cancelReconnection(for: device.identifier)

        device.status = .reconnecting
        let state = ReconnectionState(startedAt: Date())
        reconnectionTimers[device.identifier] = state

        logger.info("Starting reconnection for \(device.name) (timeout: \(Self.reconnectionTimeout)s)")

        // Schedule a repeating timer to attempt reconnection
        let deviceIdentifier = device.identifier
        state.timer = Timer.scheduledTimer(
            withTimeInterval: Self.reconnectionTimerInterval,
            repeats: true
        ) { [weak self] timer in
            Task { @MainActor [weak self] in
                self?.handleReconnectionTick(deviceIdentifier: deviceIdentifier, timer: timer)
            }
        }

        // Attempt immediate reconnection
        if let centralManager, let peripheral = device.peripheral {
            centralManager.connect(peripheral, options: nil)
        }
    }

    private func handleReconnectionTick(deviceIdentifier: UUID, timer: Timer) {
        guard
            let state = reconnectionTimers[deviceIdentifier],
            let device = connectedDevices.first(where: { $0.identifier == deviceIdentifier })
                ?? discoveredDevices.first(where: { $0.identifier == deviceIdentifier })
        else {
            timer.invalidate()
            return
        }

        let elapsed = Date().timeIntervalSince(state.startedAt)

        if elapsed >= Self.reconnectionTimeout {
            // Timeout reached
            timer.invalidate()
            reconnectionTimers.removeValue(forKey: deviceIdentifier)
            device.status = .disconnected

            if isDisconnectProtectionArmed {
                logger.warning("Reconnection timeout for \(device.displayName) while protection is armed — awaiting user decision")
                pendingDisconnectPrompt = DisconnectDecisionPrompt(
                    id: device.identifier.uuidString,
                    deviceIdentifier: device.identifier,
                    deviceName: device.displayName,
                    lastSeenAt: device.lastSeenAt
                )
                triggerDisconnectHaptic()
                Task { [weak self] in
                    await self?.scheduleProtectedDisconnectAlert(for: device)
                    await self?.postDisconnectAlert(for: device)
                }
            } else {
                logger.info("Reconnection timeout for \(device.displayName) while protection is disarmed")
            }
            sortKnownDevices()
        }
    }

    private func cancelReconnection(for identifier: UUID) {
        if let state = reconnectionTimers.removeValue(forKey: identifier) {
            state.timer?.invalidate()
        }
    }

    private func postDisconnectAlert(for device: BLEDevice) async {
        let coordinate = DeviceEventSyncService.shared.lastKnownCoordinate(for: device)
        let body = DeviceDisconnectedBody(
            deviceId: device.persistedId ?? device.identifier.uuidString,
            deviceName: device.displayName,
            lastSeenAt: device.lastSeenAt ?? Date(),
            latitude: coordinate?.latitude,
            longitude: coordinate?.longitude
        )

        do {
            let _: EmptyData = try await APIClient.shared.request(
                APIEndpoint.Alerts.deviceDisconnected(body)
            )
            logger.info("Posted disconnect alert for \(device.name)")
        } catch {
            logger.error("Failed to post disconnect alert: \(error.localizedDescription)")
        }
    }

    private func triggerDisconnectHaptic() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }

    private func scheduleProtectedDisconnectAlert(for device: BLEDevice) async {
        guard UIApplication.shared.applicationState != .active else { return }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let allowedStatuses: Set<UNAuthorizationStatus> = [.authorized, .provisional, .ephemeral]
        guard allowedStatuses.contains(settings.authorizationStatus) else {
            logger.info("Skipping local disconnect alert because notifications are not authorized")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Device disconnected"
        content.body = "\(device.displayName) disconnected while gym protection was armed."
        content.categoryIdentifier = NotificationCategory.deviceDisconnect.rawValue
        content.threadIdentifier = "ble-disconnect-protection"
        content.userInfo = [
            "type": "device",
            "deviceId": device.persistedId ?? device.identifier.uuidString,
        ]

        if settings.criticalAlertSetting == .enabled {
            content.sound = .defaultCriticalSound(withAudioVolume: 1.0)
            content.interruptionLevel = .critical
        } else {
            content.sound = .default
        }

        let criticalAlertsEnabled = settings.criticalAlertSetting == .enabled
        let deviceName = device.displayName

        let request = UNNotificationRequest(
            identifier: Self.protectedDisconnectNotificationId(for: device.identifier),
            content: content,
            trigger: nil
        )

        await withCheckedContinuation { continuation in
            center.add(request) { [weak self] error in
                if let error {
                    self?.logger.error("Failed to schedule protected disconnect alert: \(error.localizedDescription)")
                } else if criticalAlertsEnabled {
                    self?.logger.info("Scheduled critical disconnect alert for \(deviceName)")
                } else {
                    self?.logger.info("Scheduled standard disconnect alert for \(deviceName) because critical alerts are unavailable")
                }
                continuation.resume()
            }
        }
    }

    private func clearProtectedDisconnectAlert(for identifier: UUID) {
        let requestIdentifier = Self.protectedDisconnectNotificationId(for: identifier)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [requestIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [requestIdentifier])
    }

    private static func protectedDisconnectNotificationId(for identifier: UUID) -> String {
        "\(protectedDisconnectNotificationPrefix)\(identifier.uuidString)"
    }

    /// Called internally to set self as the peripheral delegate for RSSI callbacks.
    private func registerAsPeripheralDelegate(for peripheral: CBPeripheral) {
        peripheral.delegate = self
    }

    // MARK: - RSSI Reading

    /// Request a fresh RSSI reading from a connected device's peripheral.
    func readRSSI(for device: BLEDevice) {
        guard let peripheral = device.peripheral,
              peripheral.state == .connected else { return }
        peripheral.readRSSI()
    }

    // MARK: - Stale Pruning

    private func scheduleStalePruning() {
        stalePruningTask?.cancel()
        stalePruningTask = Task { [weak self] in
            while let self, self.isScanning {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                let pruned = self.scanner.pruneStaleDevices()
                if !pruned.isEmpty {
                    self.discoveredDevices = self.scanner.discoveredDevices
                }
            }
        }
    }

    private func scheduleScanTimeoutIfNeeded(for mode: BLEScanMode) {
        scanTimeoutTask?.cancel()
        scanTimeoutTask = nil

        guard let timeout = mode.timeout else { return }

        scanTimeoutTask = Task { [weak self] in
            let nanoseconds = UInt64(timeout * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.stopScanning()
            }
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.bluetoothState = central.state
            self.logger.info("Bluetooth state: \(central.state.rawValue)")

            if central.state != .poweredOn && self.isScanning {
                self.isScanning = false
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let device = self.scanner.processDiscovery(
                peripheral: peripheral,
                advertisementData: advertisementData,
                rssi: RSSI
            )
            if let device {
                self.discoveredDevices = self.scanner.discoveredDevices
                self.syncKnownDeviceMetadata()

                // Backlog item #19: buffer RSSI samples for paired
                // devices so the 24h signal-history chart has data to
                // render. Unpaired (non-persisted) discoveries are
                // dropped by the buffer.
                self.rssiSampleBuffer.record(
                    rssi: RSSI.intValue,
                    persistedDeviceId: device.persistedId
                )
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.logger.info("Connected to \(peripheral.name ?? peripheral.identifier.uuidString)")

            self.cancelReconnection(for: peripheral.identifier)

            self.registerAsPeripheralDelegate(for: peripheral)
            self.clearProtectedDisconnectAlert(for: peripheral.identifier)

            if let device = self.findDevice(for: peripheral) {
                device.status = .connected
                device.lastSeenAt = Date()
                if !self.connectedDevices.contains(device) {
                    self.connectedDevices.append(device)
                }
                self.discoveredDevices.removeAll { $0.identifier == device.identifier }
                self.applyPersistedMetadataIfAvailable(to: device)
                self.sortKnownDevices()
                self.syncWidgetSnapshot()

                // Start signal monitoring when first device connects
                if self.connectedDevices.count == 1 {
                    BLESignalMonitor.shared.startMonitoring()
                }

                Task {
                    await DeviceEventSyncService.shared.record(action: .connect, for: device)
                }

                // Kick off BLE Battery Service (0x180F) discovery.
                // `BatteryLevelReader` will subscribe to the Battery Level
                // characteristic (0x2A19) once the characteristic surfaces.
                self.batteryLevelReader.observe(peripheral: peripheral)

                // Backlog item #26 — count successful pairs (persisted
                // devices only) toward the App Store review-prompt
                // threshold. We scope to `persistedId != nil` so that
                // one-off scans of nearby broadcast-only peripherals
                // don't inflate the counter.
                if device.persistedId != nil {
                    ReviewPromptController.shared.recordDevicePaired()
                    ReviewPromptController.shared.maybeRequestReview()
                }
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.logger.error("Failed to connect: \(error?.localizedDescription ?? "unknown")")

            if let device = self.findDevice(for: peripheral) {
                device.status = .disconnected
                self.sortKnownDevices()
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.logger.warning("Disconnected from \(peripheral.name ?? "unknown"): \(error?.localizedDescription ?? "clean")")

            if let device = self.findDevice(for: peripheral) {
                self.connectedDevices.removeAll { $0.identifier == device.identifier }

                // Drop any cached battery state for the peripheral so a
                // subsequent reconnect re-primes via the discovery path.
                self.batteryLevelReader.stopObserving(peripheralIdentifier: peripheral.identifier)

                Task {
                    await DeviceEventSyncService.shared.record(action: .disconnect, for: device)
                }

                // Stop signal monitoring when no devices remain connected
                if self.connectedDevices.isEmpty {
                    BLESignalMonitor.shared.stopMonitoring()
                }

                if error != nil {
                    // Unexpected disconnect — begin reconnection
                    self.startReconnection(for: device)
                } else {
                    device.status = .disconnected
                    self.sortKnownDevices()
                }

                self.syncWidgetSnapshot()
            }
        }
    }

    // MARK: - State Restoration

    nonisolated func centralManager(
        _ central: CBCentralManager,
        willRestoreState dict: [String: Any]
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.logger.info("Restoring BLE state")

            if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
                for peripheral in peripherals {
                    let device = BLEDevice(peripheral: peripheral, rssi: 0)
                    device.status = peripheral.state == .connected ? .connected : .reconnecting
                    self.applyPersistedMetadataIfAvailable(to: device)

                    if peripheral.state == .connected {
                        self.connectedDevices.append(device)
                    } else {
                        self.startReconnection(for: device)
                    }
                }

                self.sortKnownDevices()
                self.syncWidgetSnapshot()
            }
        }
    }

    // MARK: - Helpers

    private func findDevice(for peripheral: CBPeripheral) -> BLEDevice? {
        if let device = connectedDevices.first(where: { $0.identifier == peripheral.identifier }) {
            return device
        }
        return scanner.device(for: peripheral.identifier)
    }
}

// MARK: - CBPeripheralDelegate (RSSI)

extension BLEManager: CBPeripheralDelegate {

    // MARK: - Battery Service (0x180F)

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            if let error {
                self.logger.warning("Service discovery failed for \(peripheral.name ?? "unknown"): \(error.localizedDescription)")
                return
            }

            for service in peripheral.services ?? [] where service.uuid == BatteryLevelReader.batteryServiceUUID {
                peripheral.discoverCharacteristics(
                    [BatteryLevelReader.batteryLevelCharacteristicUUID],
                    for: service
                )
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: (any Error)?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            if let error {
                self.logger.warning("Characteristic discovery failed on \(peripheral.name ?? "unknown"): \(error.localizedDescription)")
                return
            }

            guard service.uuid == BatteryLevelReader.batteryServiceUUID else { return }

            for characteristic in service.characteristics ?? []
            where characteristic.uuid == BatteryLevelReader.batteryLevelCharacteristicUUID {
                // Prefer notifications; fall back to a one-shot read for
                // peripherals that only expose the characteristic as Read
                // (some cheap trackers advertise .read but not .notify).
                if characteristic.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
                if characteristic.properties.contains(.read) {
                    peripheral.readValue(for: characteristic)
                }
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            if let error {
                self.logger.warning("Value update failed on \(characteristic.uuid.uuidString): \(error.localizedDescription)")
                return
            }

            guard
                characteristic.uuid == BatteryLevelReader.batteryLevelCharacteristicUUID,
                let value = characteristic.value
            else {
                return
            }

            let device = self.findDevice(for: peripheral)
            self.batteryLevelReader.handleValue(
                value,
                peripheralIdentifier: peripheral.identifier,
                persistedDeviceId: device?.persistedId
            )
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: (any Error)?) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            if let error {
                self.logger.warning("Failed to read RSSI for \(peripheral.name ?? "unknown"): \(error.localizedDescription)")
                return
            }

            let rssiValue = RSSI.intValue

            // Ignore invalid RSSI values (127 means not available)
            guard rssiValue != 127 else { return }

            if let device = self.findDevice(for: peripheral) {
                device.rssi = rssiValue
                device.lastSeenAt = Date()
                BLESignalMonitor.shared.reportRSSI(rssiValue, for: device)
                // Item #19: feed connected-peripheral RSSI reads into
                // the signal-history buffer as well so connected-only
                // devices still produce chart data.
                self.rssiSampleBuffer.record(
                    rssi: rssiValue,
                    persistedDeviceId: device.persistedId
                )
                self.sortKnownDevices()
            }
        }
    }
}

private extension BLEManager {
    @discardableResult
    func configureCentralManager(showPowerAlert: Bool) -> CBCentralManager {
        if let centralManager {
            bluetoothState = centralManager.state
            return centralManager
        }

        let options: [String: Any] = [
            CBCentralManagerOptionRestoreIdentifierKey: Self.restorationIdentifier,
            CBCentralManagerOptionShowPowerAlertKey: showPowerAlert,
        ]

        let manager = CBCentralManager(
            delegate: self,
            queue: nil,
            options: options
        )
        centralManager = manager
        bluetoothState = manager.state
        return manager
    }

    func configureCentralManagerIfAuthorized() -> CBCentralManager? {
        switch CBCentralManager.authorization {
        case .allowedAlways:
            return configureCentralManager(showPowerAlert: false)
        case .denied, .restricted:
            bluetoothState = .unauthorized
            return nil
        case .notDetermined:
            bluetoothState = .unknown
            return nil
        @unknown default:
            bluetoothState = .unknown
            return nil
        }
    }

    static func derivedState(for authorization: CBManagerAuthorization) -> CBManagerState {
        switch authorization {
        case .denied, .restricted:
            return .unauthorized
        case .allowedAlways, .notDetermined:
            return .unknown
        @unknown default:
            return .unknown
        }
    }

    static func normalizedIdentifier(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func applyPersistedMetadataIfAvailable(to device: BLEDevice) {
        let key = Self.normalizedIdentifier(device.identifier.uuidString)
        guard let metadata = persistedMetadataByIdentifier[key] else {
            device.persistedId = nil
            device.preferredName = nil
            device.isFavorite = false
            return
        }

        device.persistedId = metadata.id
        device.preferredName = metadata.nickname
        device.isFavorite = metadata.isFavorite
    }

    func syncKnownDeviceMetadata() {
        for device in connectedDevices {
            applyPersistedMetadataIfAvailable(to: device)
        }

        for device in discoveredDevices {
            applyPersistedMetadataIfAvailable(to: device)
        }

        sortKnownDevices()
    }

    func sortKnownDevices() {
        connectedDevices.sort(by: deviceSort)
        discoveredDevices.sort(by: deviceSort)
    }

    func syncWidgetSnapshot() {
        let totalCount = max(persistedMetadataByIdentifier.count, connectedDevices.count)
        WidgetSyncStore.shared.storeDeviceSnapshot(
            connectedCount: connectedDevices.count,
            totalCount: totalCount
        )
    }

    func deviceSort(_ lhs: BLEDevice, _ rhs: BLEDevice) -> Bool {
        if lhs.isFavorite != rhs.isFavorite {
            return lhs.isFavorite && !rhs.isFavorite
        }

        if lhs.rssi != rhs.rssi {
            return lhs.rssi > rhs.rssi
        }

        if lhs.lastSeenAt != rhs.lastSeenAt {
            return (lhs.lastSeenAt ?? .distantPast) > (rhs.lastSeenAt ?? .distantPast)
        }

        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    func knownDevice(identifier: UUID) -> BLEDevice? {
        connectedDevices.first(where: { $0.identifier == identifier })
        ?? discoveredDevices.first(where: { $0.identifier == identifier })
        ?? scanner.device(for: identifier)
    }
}

// MARK: - Reconnection State

private final class ReconnectionState {
    let startedAt: Date
    var timer: Timer?

    init(startedAt: Date) {
        self.startedAt = startedAt
    }
}
