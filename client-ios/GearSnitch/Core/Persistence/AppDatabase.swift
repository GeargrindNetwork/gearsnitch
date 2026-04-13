import Foundation
import SwiftData

// MARK: - Local Device

/// Persisted BLE device for offline access and sync tracking.
@Model
final class LocalDevice {
    @Attribute(.unique) var id: String
    var name: String
    var bluetoothIdentifier: String
    var status: String
    var lastSeenAt: Date?
    var lastSeenLatitude: Double?
    var lastSeenLongitude: Double?
    var lastSignalStrength: Int?
    var isSynced: Bool

    init(
        id: String,
        name: String,
        bluetoothIdentifier: String,
        status: String = "disconnected",
        lastSeenAt: Date? = nil,
        lastSeenLatitude: Double? = nil,
        lastSeenLongitude: Double? = nil,
        lastSignalStrength: Int? = nil,
        isSynced: Bool = false
    ) {
        self.id = id
        self.name = name
        self.bluetoothIdentifier = bluetoothIdentifier
        self.status = status
        self.lastSeenAt = lastSeenAt
        self.lastSeenLatitude = lastSeenLatitude
        self.lastSeenLongitude = lastSeenLongitude
        self.lastSignalStrength = lastSignalStrength
        self.isSynced = isSynced
    }
}

// MARK: - Local Device Event

/// Persisted connect/disconnect history so device telemetry survives offline use.
@Model
final class LocalDeviceEvent {
    @Attribute(.unique) var id: String
    var deviceId: String
    var deviceName: String
    var bluetoothIdentifier: String
    var action: String
    var occurredAt: Date
    var latitude: Double?
    var longitude: Double?
    var signalStrength: Int?
    var isSynced: Bool
    var syncedAt: Date?

    init(
        id: String = UUID().uuidString,
        deviceId: String,
        deviceName: String,
        bluetoothIdentifier: String,
        action: String,
        occurredAt: Date,
        latitude: Double? = nil,
        longitude: Double? = nil,
        signalStrength: Int? = nil,
        isSynced: Bool = false,
        syncedAt: Date? = nil
    ) {
        self.id = id
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.bluetoothIdentifier = bluetoothIdentifier
        self.action = action
        self.occurredAt = occurredAt
        self.latitude = latitude
        self.longitude = longitude
        self.signalStrength = signalStrength
        self.isSynced = isSynced
        self.syncedAt = syncedAt
    }
}

// MARK: - Local Gym

/// Persisted gym location for offline geofencing.
@Model
final class LocalGym {
    @Attribute(.unique) var id: String
    var name: String
    var latitude: Double
    var longitude: Double
    var radius: Double
    var isDefault: Bool

    init(
        id: String,
        name: String,
        latitude: Double,
        longitude: Double,
        radius: Double = 150,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.isDefault = isDefault
    }
}

// MARK: - Offline Operation

/// Queued API operation for offline-first support.
/// When the device regains connectivity, these are replayed in order.
@Model
final class OfflineOperation {
    @Attribute(.unique) var id: String
    var endpoint: String
    var method: String
    var body: Data?
    var createdAt: Date
    var retryCount: Int
    var lastAttemptAt: Date?
    /// Set to true when the operation has permanently failed (max retries exceeded).
    var isPermanentlyFailed: Bool

    init(
        id: String = UUID().uuidString,
        endpoint: String,
        method: String,
        body: Data? = nil,
        createdAt: Date = Date(),
        retryCount: Int = 0,
        lastAttemptAt: Date? = nil,
        isPermanentlyFailed: Bool = false
    ) {
        self.id = id
        self.endpoint = endpoint
        self.method = method
        self.body = body
        self.createdAt = createdAt
        self.retryCount = retryCount
        self.lastAttemptAt = lastAttemptAt
        self.isPermanentlyFailed = isPermanentlyFailed
    }
}
