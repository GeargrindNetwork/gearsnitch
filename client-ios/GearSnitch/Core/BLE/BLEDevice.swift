import Foundation
import CoreBluetooth

// MARK: - Device Status

enum BLEDeviceStatus: String, Codable, CaseIterable {
    case discovered
    case connecting
    case connected
    case monitoring
    case disconnected
    case reconnecting
    case lost
}

// MARK: - BLE Device

/// Represents a BLE peripheral discovered or connected by the app.
final class BLEDevice: Identifiable, ObservableObject {

    let id: UUID
    let identifier: UUID
    var persistedId: String?

    @Published var name: String
    @Published var status: BLEDeviceStatus
    @Published var rssi: Int
    @Published var lastSeenAt: Date?
    @Published var preferredName: String?
    @Published var isFavorite: Bool

    /// The underlying CoreBluetooth peripheral. Nil if the device was loaded
    /// from persistence and not yet rediscovered.
    ///
    /// This is held strongly so a discovered device can still be connected
    /// after the discovery callback completes.
    var peripheral: CBPeripheral?

    init(
        id: UUID = UUID(),
        name: String,
        identifier: UUID,
        status: BLEDeviceStatus = .discovered,
        rssi: Int = 0,
        lastSeenAt: Date? = nil,
        persistedId: String? = nil,
        preferredName: String? = nil,
        isFavorite: Bool = false,
        peripheral: CBPeripheral? = nil
    ) {
        self.id = id
        self.name = name
        self.identifier = identifier
        self.status = status
        self.rssi = rssi
        self.lastSeenAt = lastSeenAt
        self.persistedId = persistedId
        self.preferredName = preferredName
        self.isFavorite = isFavorite
        self.peripheral = peripheral
    }

    /// Convenience initializer from a discovered CBPeripheral.
    convenience init(peripheral: CBPeripheral, rssi: Int, name: String? = nil) {
        let resolvedName = name?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? peripheral.name?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? "Unknown Device"

        self.init(
            name: resolvedName,
            identifier: peripheral.identifier,
            status: .discovered,
            rssi: rssi,
            lastSeenAt: Date(),
            peripheral: peripheral
        )
    }

    var displayName: String {
        if let preferredName, !preferredName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return preferredName
        }

        return name
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

// MARK: - Equatable (by identifier)

extension BLEDevice: Equatable {
    static func == (lhs: BLEDevice, rhs: BLEDevice) -> Bool {
        lhs.identifier == rhs.identifier
    }
}

// MARK: - Hashable

extension BLEDevice: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }
}
