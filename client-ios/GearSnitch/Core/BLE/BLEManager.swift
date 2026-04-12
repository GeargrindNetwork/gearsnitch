import Foundation
import CoreBluetooth
import os
import UIKit

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

/// Central BLE manager handling scanning, connection, reconnection, and
/// state restoration for GearSnitch device peripherals.
@MainActor
final class BLEManager: NSObject, ObservableObject {

    static let shared = BLEManager()

    // MARK: - Constants

    private static let restorationIdentifier = "com.gearsnitch.ble.central"
    private static let reconnectionTimeout: TimeInterval = 30
    private static let reconnectionTimerInterval: TimeInterval = 1

    /// Service UUIDs the app monitors. Register these in Info.plist under
    /// `UIBackgroundModes` -> `bluetooth-central` for background BLE.
    static let registeredServiceUUIDs: [CBUUID] = AppConfig.bleServiceUUIDs

    // MARK: - Published State

    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var discoveredDevices: [BLEDevice] = []
    @Published private(set) var connectedDevices: [BLEDevice] = []
    @Published private(set) var isScanning = false
    @Published private(set) var pendingDisconnectPrompt: DisconnectDecisionPrompt?

    // MARK: - Private Properties

    private var centralManager: CBCentralManager!
    private let scanner = BLEScanner()
    private let logger = Logger(subsystem: "com.gearsnitch", category: "BLEManager")

    /// Tracks reconnection timers per device identifier.
    private var reconnectionTimers: [UUID: ReconnectionState] = [:]
    private var persistedMetadataByIdentifier: [String: PersistedBLEDeviceMetadata] = [:]

    // MARK: - Init

    override init() {
        super.init()

        let options: [String: Any] = [
            CBCentralManagerOptionRestoreIdentifierKey: Self.restorationIdentifier,
            CBCentralManagerOptionShowPowerAlertKey: true,
        ]

        centralManager = CBCentralManager(
            delegate: self,
            queue: nil,
            options: options
        )

        scanner.serviceFilter = Self.registeredServiceUUIDs.isEmpty ? nil : Self.registeredServiceUUIDs
    }

    // MARK: - Scanning

    /// Start scanning for BLE peripherals. Filters by registered service UUIDs
    /// when available, otherwise scans for all devices.
    func startScanning() {
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
                CBCentralManagerScanOptionAllowDuplicatesKey: true,
            ]
        )

        isScanning = true
        logger.info("Started BLE scanning")

        // Schedule periodic stale-device pruning
        scheduleStalePruning()
    }

    /// Stop scanning for BLE peripherals.
    func stopScanning() {
        guard isScanning else { return }
        centralManager.stopScan()
        isScanning = false
        logger.info("Stopped BLE scanning")
    }

    // MARK: - Connection

    /// Connect to a discovered BLE device.
    func connect(to device: BLEDevice) {
        guard let peripheral = device.peripheral else {
            logger.error("Cannot connect: no peripheral reference for \(device.name)")
            return
        }

        device.status = .connecting
        centralManager.connect(peripheral, options: [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
        ])

        logger.info("Connecting to \(device.name)")
    }

    /// Disconnect from a connected BLE device.
    func disconnect(from device: BLEDevice) {
        guard let peripheral = device.peripheral else { return }

        cancelReconnection(for: device.identifier)
        centralManager.cancelPeripheralConnection(peripheral)
        device.status = .disconnected

        connectedDevices.removeAll { $0.identifier == device.identifier }
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
    }

    func upsertPersistedMetadata(_ metadata: PersistedBLEDeviceMetadata) {
        persistedMetadataByIdentifier[Self.normalizedIdentifier(metadata.bluetoothIdentifier)] = metadata
        syncKnownDeviceMetadata()
    }

    func dismissPendingDisconnectPrompt() {
        pendingDisconnectPrompt = nil
    }

    func resolvePendingDisconnectAsEndedSession() {
        guard let prompt = pendingDisconnectPrompt else { return }
        pendingDisconnectPrompt = nil

        if let device = knownDevice(identifier: prompt.deviceIdentifier) {
            cancelReconnection(for: device.identifier)
            device.status = .disconnected
            sortKnownDevices()
        }
    }

    func resolvePendingDisconnectAsLostGear() {
        guard let prompt = pendingDisconnectPrompt else { return }
        pendingDisconnectPrompt = nil

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
        if let peripheral = device.peripheral {
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

            logger.warning("Reconnection timeout for \(device.displayName) — awaiting user decision")
            pendingDisconnectPrompt = DisconnectDecisionPrompt(
                id: device.identifier.uuidString,
                deviceIdentifier: device.identifier,
                deviceName: device.displayName,
                lastSeenAt: device.lastSeenAt
            )
            triggerDisconnectHaptic()
            Task { [weak self] in
                await self?.postDisconnectAlert(for: device)
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
        let body = DeviceDisconnectedBody(
            deviceId: device.persistedId ?? device.identifier.uuidString,
            deviceName: device.displayName,
            lastSeenAt: device.lastSeenAt ?? Date(),
            latitude: nil,
            longitude: nil
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
        Task { [weak self] in
            while let self, self.isScanning {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                let pruned = self.scanner.pruneStaleDevices()
                if !pruned.isEmpty {
                    self.discoveredDevices = self.scanner.discoveredDevices
                }
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
            if device != nil {
                self.discoveredDevices = self.scanner.discoveredDevices
                self.syncKnownDeviceMetadata()
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

            if let device = self.findDevice(for: peripheral) {
                device.status = .connected
                device.lastSeenAt = Date()
                if !self.connectedDevices.contains(device) {
                    self.connectedDevices.append(device)
                }
                self.discoveredDevices.removeAll { $0.identifier == device.identifier }
                self.applyPersistedMetadataIfAvailable(to: device)
                self.sortKnownDevices()

                // Start signal monitoring when first device connects
                if self.connectedDevices.count == 1 {
                    BLESignalMonitor.shared.startMonitoring()
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
                self.sortKnownDevices()
            }
        }
    }
}

private extension BLEManager {
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
