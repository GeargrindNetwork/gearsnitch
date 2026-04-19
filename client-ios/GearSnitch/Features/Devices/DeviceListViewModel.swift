import Foundation
import Combine

// MARK: - Device DTO

struct DeviceDTO: Identifiable, Decodable {
    let id: String
    let name: String
    let nickname: String?
    let type: String
    let bluetoothIdentifier: String
    let status: String
    let isFavorite: Bool
    let firmwareVersion: String?
    let signalStrength: Int?
    let lastSeenAt: Date?
    let isMonitoring: Bool?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, nickname, type, bluetoothIdentifier, status
        case firmwareVersion, signalStrength, lastSeenAt
        case isFavorite, isMonitoring, createdAt
    }

    var isConnected: Bool {
        status == "connected" || status == "monitoring"
    }

    var displayName: String {
        if let nickname, !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nickname
        }

        return name
    }

    var priorityMetadata: PersistedBLEDeviceMetadata {
        PersistedBLEDeviceMetadata(
            id: id,
            bluetoothIdentifier: bluetoothIdentifier,
            nickname: nickname,
            isFavorite: isFavorite
        )
    }

    var statusColor: String {
        switch status {
        case "connected", "monitoring": return "green"
        case "disconnected": return "red"
        default: return "gray"
        }
    }
}

// MARK: - ViewModel

@MainActor
final class DeviceListViewModel: ObservableObject {

    @Published var devices: [DeviceDTO] = []
    @Published var isLoading = false
    @Published var error: String?
    /// Backed by `.alert` on the view — the device waiting for the user's
    /// confirmation. Nil when no confirmation is outstanding.
    @Published var pendingDeletion: DeviceDTO?

    private let apiClient = APIClient.shared

    func loadDevices() async {
        isLoading = true
        error = nil

        do {
            let fetched: [DeviceDTO] = try await apiClient.request(APIEndpoint.Devices.list)
            let sorted = fetched.sorted {
                if $0.isFavorite != $1.isFavorite {
                    return $0.isFavorite && !$1.isFavorite
                }

                if $0.isConnected != $1.isConnected {
                    return $0.isConnected && !$1.isConnected
                }

                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            devices = sorted
            BLEManager.shared.replacePersistedMetadata(sorted.map(\.priorityMetadata))
            for device in sorted {
                DeviceEventSyncService.shared.cacheRegisteredDevice(
                    id: device.id,
                    name: device.displayName,
                    bluetoothIdentifier: device.bluetoothIdentifier,
                    status: device.status,
                    lastSeenAt: device.lastSeenAt,
                    signalStrength: device.signalStrength,
                    isSynced: true
                )
            }
            WidgetSyncStore.shared.storeDeviceSnapshot(
                connectedCount: sorted.filter(\.isConnected).count,
                totalCount: sorted.count
            )
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    /// DELETE /api/v1/devices/:id + unpair from BLEManager. Optimistically
    /// removes the row, then rolls back on error. When the device is
    /// currently connected we also drop the live `BLEDevice` so the user
    /// doesn't see a stale "connected" row reappear on the next refresh.
    func deleteDevice(_ device: DeviceDTO) async {
        let original = devices
        devices.removeAll { $0.id == device.id }
        refreshPersistedMetadata()

        let manager = BLEManager.shared
        if let live = (manager.connectedDevices + manager.discoveredDevices)
            .first(where: { $0.persistedId == device.id }) {
            manager.disconnect(from: live)
        }

        do {
            let _: EmptyData = try await apiClient.request(
                APIEndpoint.Devices.delete(id: device.id)
            )
        } catch {
            self.error = error.localizedDescription
            devices = original
            refreshPersistedMetadata()
        }
    }

    /// Re-push the persisted metadata list so BLEManager's known-device
    /// bookkeeping stays in sync after a local mutation. Cheap; the set is
    /// small (a handful of devices at most).
    private func refreshPersistedMetadata() {
        BLEManager.shared.replacePersistedMetadata(devices.map(\.priorityMetadata))
    }
}
