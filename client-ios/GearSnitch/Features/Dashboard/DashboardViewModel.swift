import Foundation
import Combine

// MARK: - Dashboard DTOs

struct DashboardDevice: Identifiable, Decodable {
    let id: String
    let name: String
    let nickname: String?
    let type: String
    let bluetoothIdentifier: String
    let status: String
    let isFavorite: Bool
    let lastSeenAt: Date?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, nickname, type, bluetoothIdentifier, status, isFavorite, lastSeenAt
    }

    var isConnected: Bool {
        status == "connected" || status == "monitoring"
    }

    var priorityMetadata: PersistedBLEDeviceMetadata {
        PersistedBLEDeviceMetadata(
            id: id,
            bluetoothIdentifier: bluetoothIdentifier,
            nickname: nickname,
            isFavorite: isFavorite
        )
    }
}

struct DashboardAlert: Identifiable, Decodable {
    let id: String
    let type: String
    let severity: String
    let message: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case type, severity, message, createdAt
    }
}

struct GymSummary: Identifiable, Decodable {
    let id: String
    let name: String
    let isDefault: Bool

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, isDefault
    }
}

// MARK: - ViewModel

@MainActor
final class DashboardViewModel: ObservableObject {

    @Published var devices: [DashboardDevice] = []
    @Published var activeAlerts: [DashboardAlert] = []
    @Published var defaultGym: GymSummary?
    @Published var isLoading = false
    @Published var error: String?

    private let apiClient = APIClient.shared

    var connectedCount: Int {
        devices.filter { $0.isConnected }.count
    }

    var disconnectedCount: Int {
        devices.filter { !$0.isConnected }.count
    }

    var hasActiveAlerts: Bool {
        !activeAlerts.isEmpty
    }

    // MARK: - Fetch

    func loadDashboard() async {
        isLoading = true
        error = nil

        do {
            async let fetchedDevices: [DashboardDevice] = apiClient.request(APIEndpoint.Devices.list)
            async let fetchedAlerts: [DashboardAlert] = apiClient.request(APIEndpoint.Alerts.list)
            async let fetchedGyms: [GymSummary] = apiClient.request(APIEndpoint.Gyms.list)

            let (devs, alerts, gyms) = try await (fetchedDevices, fetchedAlerts, fetchedGyms)
            devices = devs
            BLEManager.shared.replacePersistedMetadata(devs.map(\.priorityMetadata))
            activeAlerts = alerts.filter { $0.severity == "critical" || $0.severity == "high" }
            defaultGym = gyms.first(where: { $0.isDefault }) ?? gyms.first
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}
