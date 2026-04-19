import Combine
import CoreBluetooth
import Foundation
import os

// MARK: - BLE Heart Rate Profile UUIDs

/// Bluetooth SIG assigned UUIDs for the standard Heart Rate Profile.
/// Spec: https://www.bluetooth.com/specifications/specs/heart-rate-profile-1-0/
enum BLEHeartRateProfile {
    /// Heart Rate Service (0x180D).
    static let serviceUUID = CBUUID(string: "180D")
    /// Heart Rate Measurement characteristic (0x2A37) — notify-only.
    static let heartRateMeasurementCharacteristicUUID = CBUUID(string: "2A37")
    /// Body Sensor Location characteristic (0x2A38) — read-only, optional.
    static let bodySensorLocationCharacteristicUUID = CBUUID(string: "2A38")
}

// MARK: - HR Measurement Decoder

/// Parsed contents of a single BLE Heart Rate Measurement notification
/// (characteristic 0x2A37). Follows the Heart Rate Profile flags layout:
///
/// Flags (1 byte)
///   bit 0: HR value format (0 = UInt8, 1 = UInt16)
///   bit 1: Sensor Contact Status bit 1
///   bit 2: Sensor Contact Support bit
///   bit 3: Energy Expended present
///   bit 4: RR-Interval present
///   bits 5-7: reserved
///
/// Layout (little-endian): [flags][hr][energy?][rr*]
struct HeartRateMeasurement: Equatable {
    let bpm: Int
    let energyExpendedKJ: Int?
    /// RR intervals in seconds. BLE wire format is 1/1024s resolution per spec.
    let rrIntervals: [Double]
    let sensorContactSupported: Bool
    let sensorContactDetected: Bool

    /// Decode a raw 0x2A37 Heart Rate Measurement payload. Returns `nil` if the
    /// buffer is truncated or the flag bits request data that isn't present.
    static func decode(_ data: Data) -> HeartRateMeasurement? {
        guard data.count >= 2 else { return nil }

        let bytes = [UInt8](data)
        let flags = bytes[0]
        let isUInt16 = (flags & 0x01) != 0
        let contactStatus = (flags & 0x02) != 0
        let contactSupport = (flags & 0x04) != 0
        let hasEnergy = (flags & 0x08) != 0
        let hasRR = (flags & 0x10) != 0

        var offset = 1
        let bpm: Int
        if isUInt16 {
            guard bytes.count >= offset + 2 else { return nil }
            bpm = Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
            offset += 2
        } else {
            guard bytes.count >= offset + 1 else { return nil }
            bpm = Int(bytes[offset])
            offset += 1
        }

        var energy: Int?
        if hasEnergy {
            guard bytes.count >= offset + 2 else { return nil }
            energy = Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
            offset += 2
        }

        var rrs: [Double] = []
        if hasRR {
            while bytes.count >= offset + 2 {
                let raw = UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
                // BLE RR interval unit = 1/1024 second.
                rrs.append(Double(raw) / 1024.0)
                offset += 2
            }
        }

        return HeartRateMeasurement(
            bpm: bpm,
            energyExpendedKJ: energy,
            rrIntervals: rrs,
            sensorContactSupported: contactSupport,
            sensorContactDetected: contactSupport ? contactStatus : true
        )
    }
}

// MARK: - External HR Sensor Descriptor

/// User-facing snapshot of a BLE HR sensor that has advertised service 0x180D
/// (and therefore can feed HR into the app).
struct ExternalHRSensor: Identifiable, Equatable {
    let id: UUID
    let displayName: String
    let isConnected: Bool
    let isStreaming: Bool
    let lastBPM: Int?
    let lastSeenAt: Date?

    static func == (lhs: ExternalHRSensor, rhs: ExternalHRSensor) -> Bool {
        lhs.id == rhs.id
            && lhs.displayName == rhs.displayName
            && lhs.isConnected == rhs.isConnected
            && lhs.isStreaming == rhs.isStreaming
            && lhs.lastBPM == rhs.lastBPM
            && lhs.lastSeenAt == rhs.lastSeenAt
    }
}

// MARK: - Adapter Protocols (for tests)

/// Narrow protocol over the bits of `HeartRateMonitor` the adapter needs, so
/// unit tests can verify decode → forward without spinning up the full monitor.
protocol ExternalHRSampleSink: AnyObject {
    @MainActor
    func ingestExternalSample(bpm: Int, source: String, timestamp: Date)
}

// MARK: - External HR Sensor Adapter

/// Bridges BLE peripherals advertising the Heart Rate Service (0x180D) into
/// `HeartRateMonitor.ingestExternalSample(...)`. Each enabled peripheral gets
/// a notify subscription on the 0x2A37 Heart Rate Measurement characteristic;
/// every notification is decoded per the BLE HR Profile spec and forwarded
/// with the peripheral's advertised name as the source label.
///
/// This is strictly additive — it does not touch the Watch or AirPods
/// ingestion paths on `HeartRateMonitor`, and it never writes to HealthKit.
@MainActor
final class ExternalHRSensorAdapter: NSObject, ObservableObject {

    static let shared = ExternalHRSensorAdapter()

    // MARK: - Published State

    /// List of peripherals the adapter knows about (discovered, connected, or
    /// restored from CoreBluetooth state). Used by Settings → External Heart
    /// Rate Sensors to render the toggleable list.
    @Published private(set) var sensors: [ExternalHRSensor] = []

    /// Set of peripheral UUIDs the user has opted-in as HR sources.
    @Published private(set) var enabledSensorIDs: Set<UUID> = []

    /// Identifier of the sensor currently streaming HR. Mirrors the value
    /// published to `HeartRateMonitor.currentExternalSource`.
    @Published private(set) var activeSensorID: UUID?

    // MARK: - Private State

    private let logger = Logger(subsystem: "com.gearsnitch", category: "ExternalHRSensorAdapter")
    private weak var sink: ExternalHRSampleSink?

    /// CoreBluetooth central manager. Separate from `BLEManager.shared`'s
    /// central so we can scan on the HR service UUID without interfering with
    /// gear-tracking scan filters.
    private var centralManager: CBCentralManager?
    private var peripheralsByID: [UUID: CBPeripheral] = [:]
    private var lastBPMByID: [UUID: Int] = [:]
    private var lastSeenByID: [UUID: Date] = [:]
    private var streamingIDs: Set<UUID> = []

    private let enabledSensorDefaultsKey = "com.gearsnitch.externalHR.enabledSensors"

    // MARK: - Init

    override init() {
        super.init()
        restoreEnabledSensors()
    }

    // MARK: - Public API

    /// Wire the adapter to the monitor. Call once during app bootstrap.
    func configure(sink: ExternalHRSampleSink) {
        self.sink = sink
    }

    /// Begin BLE scanning for peripherals advertising the HR service. Safe to
    /// call multiple times — duplicate scans are coalesced.
    func startScanning() {
        if centralManager == nil {
            centralManager = CBCentralManager(
                delegate: self,
                queue: nil,
                options: [CBCentralManagerOptionShowPowerAlertKey: false]
            )
        }
        guard let manager = centralManager, manager.state == .poweredOn else {
            logger.info("BLE not powered on yet; scan deferred")
            return
        }
        manager.scanForPeripherals(
            withServices: [BLEHeartRateProfile.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        logger.info("Started scanning for BLE HR peripherals (0x180D)")
    }

    /// Stop BLE scanning. Connected peripherals keep streaming.
    func stopScanning() {
        centralManager?.stopScan()
    }

    /// Flip the "use as HR source" toggle for a discovered peripheral. When
    /// enabled, the adapter connects and subscribes to 0x2A37 notifications.
    /// When disabled, it cancels the connection and stops forwarding samples.
    func setSensorEnabled(_ enabled: Bool, sensorID: UUID) {
        if enabled {
            enabledSensorIDs.insert(sensorID)
        } else {
            enabledSensorIDs.remove(sensorID)
            if let peripheral = peripheralsByID[sensorID] {
                centralManager?.cancelPeripheralConnection(peripheral)
            }
            streamingIDs.remove(sensorID)
            if activeSensorID == sensorID {
                activeSensorID = nil
            }
        }
        persistEnabledSensors()
        refreshSnapshot()

        if enabled, let peripheral = peripheralsByID[sensorID] {
            connect(peripheral)
        }
    }

    // MARK: - Visible-For-Tests

    /// Exposed for deterministic unit tests. Feeds a decoded HR measurement
    /// through the same forwarding path a notify callback would take.
    @MainActor
    func handleDecodedMeasurement(
        _ measurement: HeartRateMeasurement,
        sensorID: UUID,
        sourceName: String,
        timestamp: Date = Date()
    ) {
        lastBPMByID[sensorID] = measurement.bpm
        lastSeenByID[sensorID] = timestamp
        streamingIDs.insert(sensorID)
        activeSensorID = sensorID
        refreshSnapshot()

        sink?.ingestExternalSample(
            bpm: measurement.bpm,
            source: sourceName,
            timestamp: timestamp
        )
    }

    /// Returns whether a given peripheral UUID is currently enabled as an HR
    /// source. Used by Settings UI bindings.
    func isEnabled(sensorID: UUID) -> Bool {
        enabledSensorIDs.contains(sensorID)
    }

    // MARK: - Internal

    private func connect(_ peripheral: CBPeripheral) {
        peripheral.delegate = self
        centralManager?.connect(peripheral, options: [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
        ])
        logger.info("Connecting to HR sensor \(peripheral.name ?? peripheral.identifier.uuidString)")
    }

    private func refreshSnapshot() {
        let snapshot: [ExternalHRSensor] = peripheralsByID.map { (id, peripheral) in
            ExternalHRSensor(
                id: id,
                displayName: peripheral.name ?? "Heart Rate Sensor",
                isConnected: peripheral.state == .connected,
                isStreaming: streamingIDs.contains(id),
                lastBPM: lastBPMByID[id],
                lastSeenAt: lastSeenByID[id]
            )
        }
        .sorted { $0.displayName < $1.displayName }
        sensors = snapshot
    }

    private func persistEnabledSensors() {
        let ids = enabledSensorIDs.map { $0.uuidString }
        UserDefaults.standard.set(ids, forKey: enabledSensorDefaultsKey)
    }

    private func restoreEnabledSensors() {
        guard let stored = UserDefaults.standard.array(forKey: enabledSensorDefaultsKey) as? [String] else {
            return
        }
        enabledSensorIDs = Set(stored.compactMap { UUID(uuidString: $0) })
    }
}

// MARK: - CBCentralManagerDelegate

extension ExternalHRSensorAdapter: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if central.state == .poweredOn {
                self.startScanning()
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
            let id = peripheral.identifier
            self.peripheralsByID[id] = peripheral
            self.refreshSnapshot()

            // If this sensor was previously enabled, auto-connect so the user
            // doesn't have to re-toggle after every app relaunch.
            if self.enabledSensorIDs.contains(id), peripheral.state != .connected {
                self.connect(peripheral)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.logger.info("Connected HR sensor \(peripheral.name ?? peripheral.identifier.uuidString)")
            peripheral.delegate = self
            peripheral.discoverServices([BLEHeartRateProfile.serviceUUID])
            self.refreshSnapshot()
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.streamingIDs.remove(peripheral.identifier)
            if self.activeSensorID == peripheral.identifier {
                self.activeSensorID = nil
            }
            self.refreshSnapshot()

            // If the user has this sensor enabled, attempt reconnection.
            if self.enabledSensorIDs.contains(peripheral.identifier) {
                central.connect(peripheral, options: nil)
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension ExternalHRSensorAdapter: CBPeripheralDelegate {

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == BLEHeartRateProfile.serviceUUID {
            peripheral.discoverCharacteristics(
                [BLEHeartRateProfile.heartRateMeasurementCharacteristicUUID],
                for: service
            )
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: (any Error)?
    ) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics
            where characteristic.uuid == BLEHeartRateProfile.heartRateMeasurementCharacteristicUUID {
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        guard error == nil,
              characteristic.uuid == BLEHeartRateProfile.heartRateMeasurementCharacteristicUUID,
              let data = characteristic.value,
              let measurement = HeartRateMeasurement.decode(data) else {
            return
        }

        let sensorID = peripheral.identifier
        let sourceName = peripheral.name ?? "Heart Rate Sensor"

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.handleDecodedMeasurement(
                measurement,
                sensorID: sensorID,
                sourceName: sourceName
            )
        }
    }
}
