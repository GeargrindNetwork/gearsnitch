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
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}
