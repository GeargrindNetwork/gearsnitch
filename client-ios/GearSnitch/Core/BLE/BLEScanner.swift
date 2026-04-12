import Foundation
import CoreBluetooth
import os

// MARK: - BLE Scanner

/// Scan filtering and deduplication logic for BLE device discovery.
/// Maintains a deduplicated list of discovered devices, updating RSSI
/// and timestamps for devices seen multiple times.
final class BLEScanner {

    private let logger = Logger(subsystem: "com.gearsnitch", category: "BLEScanner")

    /// Minimum RSSI to consider a device (filters very weak signals).
    var minimumRSSI: Int = -80

    /// How long (seconds) before a discovered device is considered stale
    /// and removed from the list.
    var staleDeviceTimeout: TimeInterval = 30

    /// Service UUIDs to filter for during scanning. Nil scans for all devices.
    var serviceFilter: [CBUUID]?

    /// Current set of deduplicated discovered devices, keyed by peripheral identifier.
    private var deviceMap: [UUID: BLEDevice] = [:]

    // MARK: - Process Discovery

    private func resolvedName(
        peripheral: CBPeripheral,
        advertisementData: [String: Any]
    ) -> String? {
        let advertisedLocalName = advertisementData[CBAdvertisementDataLocalNameKey] as? String

        for candidate in [advertisedLocalName, peripheral.name] {
            guard let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty else {
                continue
            }
            return trimmed
        }

        return nil
    }

    /// Process a newly discovered peripheral. Returns the updated device if it
    /// passes filtering, or nil if filtered out.
    @discardableResult
    func processDiscovery(
        peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi: NSNumber
    ) -> BLEDevice? {
        let rssiValue = rssi.intValue

        // Filter out weak signals
        guard rssiValue >= minimumRSSI, rssiValue != 127 else {
            return nil
        }

        // Many BLE peripherals only expose a local name in advertisement data.
        let name = resolvedName(peripheral: peripheral, advertisementData: advertisementData)
        let hasName = name != nil
        let advertisedServices = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]
        let matchesServiceFilter: Bool = {
            guard let filter = serviceFilter, let advertised = advertisedServices else {
                return false
            }
            return !Set(filter).intersection(Set(advertised)).isEmpty
        }()

        guard hasName || matchesServiceFilter else {
            return nil
        }

        let identifier = peripheral.identifier

        if let existing = deviceMap[identifier] {
            // Update existing device
            if let name, existing.name != name {
                existing.name = name
            }
            existing.rssi = rssiValue
            existing.lastSeenAt = Date()
            existing.peripheral = peripheral
            return existing
        } else {
            // New device
            let device = BLEDevice(
                peripheral: peripheral,
                rssi: rssiValue,
                name: name
            )
            deviceMap[identifier] = device
            logger.debug("Discovered new device: \(device.name) (RSSI: \(rssiValue))")
            return device
        }
    }

    // MARK: - Device List

    /// Returns all currently tracked devices, sorted by signal strength (strongest first).
    var discoveredDevices: [BLEDevice] {
        Array(deviceMap.values).sorted { $0.rssi > $1.rssi }
    }

    /// Remove devices that haven't been seen within the stale timeout.
    func pruneStaleDevices() -> [BLEDevice] {
        let now = Date()
        var pruned: [BLEDevice] = []

        for (identifier, device) in deviceMap {
            guard let lastSeen = device.lastSeenAt else { continue }
            if now.timeIntervalSince(lastSeen) > staleDeviceTimeout {
                deviceMap.removeValue(forKey: identifier)
                pruned.append(device)
                logger.debug("Pruned stale device: \(device.name)")
            }
        }

        return pruned
    }

    /// Clear all discovered devices.
    func reset() {
        deviceMap.removeAll()
    }

    /// Remove a specific device by identifier.
    func removeDevice(identifier: UUID) {
        deviceMap.removeValue(forKey: identifier)
    }

    /// Look up a device by its peripheral identifier.
    func device(for identifier: UUID) -> BLEDevice? {
        deviceMap[identifier]
    }
}
