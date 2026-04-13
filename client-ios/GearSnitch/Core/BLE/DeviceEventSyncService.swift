import Foundation
import CoreLocation
import SwiftData
import os

enum DeviceEventAction: String {
    case connect
    case disconnect
}

@MainActor
final class DeviceEventSyncService {

    static let shared = DeviceEventSyncService()

    private let logger = Logger(subsystem: "com.gearsnitch", category: "DeviceEventSync")
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private init() {}

    func cacheRegisteredDevice(
        id: String,
        name: String,
        bluetoothIdentifier: String,
        status: String = "disconnected",
        lastSeenAt: Date? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        signalStrength: Int? = nil,
        isSynced: Bool = true
    ) {
        let context = LocalStore.shared.mainContext
        let device = resolveLocalDevice(
            id: id,
            bluetoothIdentifier: bluetoothIdentifier,
            name: name,
            context: context
        )

        device.name = name
        device.status = status
        device.lastSeenAt = lastSeenAt ?? device.lastSeenAt
        device.lastSeenLatitude = latitude ?? device.lastSeenLatitude
        device.lastSeenLongitude = longitude ?? device.lastSeenLongitude
        device.lastSignalStrength = signalStrength ?? device.lastSignalStrength
        device.isSynced = isSynced

        save(context: context, reason: "cache registered device")
    }

    func record(action: DeviceEventAction, for device: BLEDevice, occurredAt: Date = Date()) async {
        let bluetoothIdentifier = device.identifier.uuidString
        let location = LocationManager.shared.currentLocation
        let persistedId = device.persistedId
        let resolvedId = persistedId ?? bluetoothIdentifier

        let context = LocalStore.shared.mainContext
        let localDevice = resolveLocalDevice(
            id: resolvedId,
            bluetoothIdentifier: bluetoothIdentifier,
            name: device.displayName,
            context: context
        )

        localDevice.name = device.displayName
        localDevice.status = action == .connect ? BLEDeviceStatus.connected.rawValue : BLEDeviceStatus.disconnected.rawValue
        localDevice.lastSeenAt = occurredAt
        localDevice.lastSignalStrength = device.rssi
        localDevice.lastSeenLatitude = location?.coordinate.latitude
        localDevice.lastSeenLongitude = location?.coordinate.longitude
        localDevice.isSynced = false

        let event = LocalDeviceEvent(
            deviceId: resolvedId,
            deviceName: device.displayName,
            bluetoothIdentifier: bluetoothIdentifier,
            action: action.rawValue,
            occurredAt: occurredAt,
            latitude: location?.coordinate.latitude,
            longitude: location?.coordinate.longitude,
            signalStrength: device.rssi,
            isSynced: false
        )
        context.insert(event)
        save(context: context, reason: "persist device \(action.rawValue) event")

        guard let persistedId else {
            logger.info("Skipping backend sync for unsaved device \(device.displayName)")
            return
        }

        let body = DeviceEventBody(
            action: action.rawValue,
            occurredAt: occurredAt,
            latitude: location?.coordinate.latitude,
            longitude: location?.coordinate.longitude,
            signalStrength: device.rssi,
            source: "ios"
        )

        do {
            let _: EmptyData = try await APIClient.shared.request(
                APIEndpoint.Devices.recordEvent(id: persistedId, body: body)
            )
            localDevice.id = persistedId
            localDevice.isSynced = true
            event.deviceId = persistedId
            event.isSynced = true
            event.syncedAt = Date()
            save(context: context, reason: "mark synced device \(action.rawValue) event")
        } catch {
            logger.error("Failed to sync device event for \(device.displayName): \(error.localizedDescription)")
            enqueueOfflineEvent(deviceId: persistedId, body: body)
            save(context: context, reason: "queue offline device \(action.rawValue) event")
        }
    }

    func cachedDevices() -> [LocalDevice] {
        let context = LocalStore.shared.mainContext
        let descriptor = FetchDescriptor<LocalDevice>(
            sortBy: [SortDescriptor(\.lastSeenAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func lastKnownCoordinate(for device: BLEDevice) -> CLLocationCoordinate2D? {
        let context = LocalStore.shared.mainContext
        let descriptor = FetchDescriptor<LocalDevice>()
        let devices = (try? context.fetch(descriptor)) ?? []
        if let match = devices.first(where: {
            $0.id == device.persistedId || $0.bluetoothIdentifier == device.identifier.uuidString
        }), let latitude = match.lastSeenLatitude, let longitude = match.lastSeenLongitude {
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }

        if let location = LocationManager.shared.currentLocation {
            return location.coordinate
        }

        return nil
    }

    private func enqueueOfflineEvent(deviceId: String, body: DeviceEventBody) {
        guard let encodedBody = try? encoder.encode(body) else {
            logger.error("Failed to encode offline device event payload for \(deviceId)")
            return
        }

        OfflineQueue.shared.enqueue(
            endpoint: "/api/v1/devices/\(deviceId)/events",
            method: HTTPMethod.POST.rawValue,
            body: encodedBody
        )
    }

    private func resolveLocalDevice(
        id: String,
        bluetoothIdentifier: String,
        name: String,
        context: ModelContext
    ) -> LocalDevice {
        let descriptor = FetchDescriptor<LocalDevice>()
        let devices = (try? context.fetch(descriptor)) ?? []

        if let existing = devices.first(where: {
            $0.id == id || $0.bluetoothIdentifier.caseInsensitiveCompare(bluetoothIdentifier) == .orderedSame
        }) {
            if existing.id != id {
                existing.id = id
            }
            existing.bluetoothIdentifier = bluetoothIdentifier
            existing.name = name
            return existing
        }

        let created = LocalDevice(
            id: id,
            name: name,
            bluetoothIdentifier: bluetoothIdentifier
        )
        context.insert(created)
        return created
    }

    private func save(context: ModelContext, reason: String) {
        do {
            try context.save()
        } catch {
            logger.error("Failed to \(reason): \(error.localizedDescription)")
        }
    }
}
