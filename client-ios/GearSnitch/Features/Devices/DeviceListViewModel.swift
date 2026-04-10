import Foundation
import Combine

// MARK: - Device DTO

struct DeviceDTO: Identifiable, Decodable {
    let id: String
    let name: String
    let type: String
    let bluetoothIdentifier: String
    let status: String
    let firmwareVersion: String?
    let signalStrength: Int?
    let lastSeenAt: Date?
    let isMonitoring: Bool?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, type, bluetoothIdentifier, status
        case firmwareVersion, signalStrength, lastSeenAt
        case isMonitoring, createdAt
    }

    var isConnected: Bool {
        status == "connected" || status == "monitoring"
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
            devices = fetched
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}
