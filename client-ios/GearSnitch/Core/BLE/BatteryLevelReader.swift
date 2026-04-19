import Foundation
import CoreBluetooth
import os

// MARK: - BatteryReading

/// A single decoded reading of GATT characteristic 0x2A19 (Battery Level).
///
/// The characteristic is a single `uint8` in the range 0…100. See Bluetooth
/// SIG Battery Service (0x180F) spec — the value is a percentage where 100
/// is a full battery and 0 is empty.
struct BatteryReading: Equatable {
    let level: Int
    let timestamp: Date
}

// MARK: - BatteryLevelReader

/// Reads the standard BLE Battery Service (0x180F) / Battery Level
/// characteristic (0x2A19) on every connected peripheral managed by
/// `BLEManager`, publishes the readings for the UI, and notifies the
/// backend when a low-battery crossing is detected so a push can be
/// enqueued via `PATCH /devices/:id/battery`.
///
/// Behavior:
///  - On each newly-connected peripheral we kick off service +
///    characteristic discovery and `setNotifyValue(true)` on 0x2A19.
///    iOS CoreBluetooth will then push an update on every value change.
///  - Byte 0 of the characteristic's value is decoded as an `Int`
///    percentage (`decodeBatteryLevel(from:)`). Values outside 0…100
///    are clamped and logged.
///  - The previous level per peripheral is tracked. A "crossing"
///    (prev ≥ 20 → current < 20) fires a handler that the feature
///    wires to the POST-to-server path.
///  - Network posts are rate-limited to once every 5 minutes per
///    device to avoid hammering the backend on a chatty peripheral.
@MainActor
final class BatteryLevelReader: NSObject, ObservableObject {

    // MARK: - Constants

    nonisolated static let batteryServiceUUID = CBUUID(string: "180F")
    nonisolated static let batteryLevelCharacteristicUUID = CBUUID(string: "2A19")

    /// Threshold (percent) below which the low-battery handler fires.
    /// `nonisolated` so the default-argument expression on
    /// `crossedLowBattery(threshold:)` (evaluated in a nonisolated call
    /// context) can reference it without Swift 6 concurrency diagnostics.
    nonisolated static let lowBatteryThreshold = 20

    /// Minimum interval between outbound `PATCH /devices/:id/battery`
    /// posts for the same device. Covers chatty peripherals that notify
    /// every few seconds.
    nonisolated static let postRateLimit: TimeInterval = 5 * 60

    // MARK: - Published

    /// Latest reading per connected peripheral (keyed by peripheral UUID).
    @Published private(set) var readings: [UUID: BatteryReading] = [:]

    // MARK: - Collaborators / Closures

    /// Posts `{ level }` to `PATCH /devices/:id/battery`. Injected so
    /// tests can stub the network without spinning up APIClient.
    var postBatteryLevel: (_ persistedDeviceId: String, _ level: Int) async -> Void = { persistedId, level in
        let body = UpdateDeviceBatteryBody(level: level)
        let endpoint = APIEndpoint(
            path: "/api/v1/devices/\(persistedId)/battery",
            method: .PATCH,
            body: body
        )

        do {
            let _: EmptyData = try await APIClient.shared.request(endpoint)
        } catch {
            Logger(subsystem: "com.gearsnitch", category: "BatteryLevelReader")
                .warning("Failed to POST battery level: \(error.localizedDescription)")
        }
    }

    /// Called when a device transitions from ≥ 20% to < 20%. Tests and
    /// feature code can observe low-battery moments here.
    var onLowBatteryCrossing: ((UUID, BatteryReading) -> Void)?

    // MARK: - Private state

    private let logger = Logger(subsystem: "com.gearsnitch", category: "BatteryLevelReader")
    private var previousLevels: [UUID: Int] = [:]
    private var lastPostedAt: [UUID: Date] = [:]

    // MARK: - Public API

    /// Called by `BLEManager` on every `didConnect` callback. Starts
    /// service + characteristic discovery for the Battery Service.
    func observe(peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.batteryServiceUUID])
    }

    /// Called by `BLEManager` on every `didDisconnect` callback. Drops
    /// cached state so a subsequent reconnect re-primes cleanly.
    func stopObserving(peripheralIdentifier: UUID) {
        readings.removeValue(forKey: peripheralIdentifier)
        previousLevels.removeValue(forKey: peripheralIdentifier)
        lastPostedAt.removeValue(forKey: peripheralIdentifier)
    }

    /// Decode the raw value of characteristic 0x2A19. The characteristic
    /// is a single `uint8` with range 0…100 per the Bluetooth SIG
    /// Battery Service spec. Returns `nil` when the payload is empty.
    static func decodeBatteryLevel(from data: Data) -> Int? {
        guard let first = data.first else { return nil }
        let clamped = max(0, min(100, Int(first)))
        return clamped
    }

    /// Crossing helper. Returns `true` when `previous` was at or above
    /// the low-battery threshold and `current` is below it. Exposed
    /// for unit testing.
    static func crossedLowBattery(previous: Int?, current: Int, threshold: Int = lowBatteryThreshold) -> Bool {
        guard current < threshold else { return false }
        guard let previous else {
            // First reading already low — treat as a crossing so the
            // user is notified on app launch / first connect.
            return true
        }
        return previous >= threshold
    }

    /// Entry point called by the peripheral delegate when
    /// characteristic 0x2A19 updates. Decodes, records, optionally
    /// fires crossing handler, and forwards to the backend.
    func handleValue(
        _ data: Data,
        peripheralIdentifier: UUID,
        persistedDeviceId: String?,
        now: Date = Date()
    ) {
        guard let level = Self.decodeBatteryLevel(from: data) else {
            logger.warning("Empty battery level payload for \(peripheralIdentifier.uuidString)")
            return
        }

        let reading = BatteryReading(level: level, timestamp: now)
        let previous = previousLevels[peripheralIdentifier]

        readings[peripheralIdentifier] = reading

        if Self.crossedLowBattery(previous: previous, current: level) {
            onLowBatteryCrossing?(peripheralIdentifier, reading)
        }

        previousLevels[peripheralIdentifier] = level

        if let persistedDeviceId, shouldPost(for: peripheralIdentifier, now: now) {
            lastPostedAt[peripheralIdentifier] = now
            let poster = postBatteryLevel
            Task { await poster(persistedDeviceId, level) }
        }
    }

    // MARK: - Rate-limit

    func shouldPost(for peripheralIdentifier: UUID, now: Date = Date()) -> Bool {
        guard let last = lastPostedAt[peripheralIdentifier] else { return true }
        return now.timeIntervalSince(last) >= Self.postRateLimit
    }
}

// MARK: - Request Body

/// Wire body for `PATCH /api/v1/devices/:id/battery`.
struct UpdateDeviceBatteryBody: Encodable {
    let level: Int
}
