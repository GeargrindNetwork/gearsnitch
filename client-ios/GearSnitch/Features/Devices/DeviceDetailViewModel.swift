import Foundation

// MARK: - Device Detail DTO

struct DeviceDetailDTO: Identifiable, Decodable {
    let id: String
    let name: String
    let type: String
    let bluetoothIdentifier: String
    let status: String
    let firmwareVersion: String?
    let signalStrength: Int?
    let lastSeenAt: Date?
    let isMonitoring: Bool
    let sharedWith: [String]?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, type, bluetoothIdentifier, status
        case firmwareVersion, signalStrength, lastSeenAt
        case isMonitoring, sharedWith, createdAt
    }

    var isConnected: Bool {
        status == "connected" || status == "monitoring"
    }
}

// MARK: - ViewModel

@MainActor
final class DeviceDetailViewModel: ObservableObject {

    @Published var device: DeviceDetailDTO?
    @Published var isLoading = false
    @Published var isUpdating = false
    @Published var error: String?
    @Published var showDeleteConfirm = false
    @Published var didDelete = false

    let deviceId: String
    private let apiClient = APIClient.shared

    init(deviceId: String) {
        self.deviceId = deviceId
    }

    func loadDevice() async {
        isLoading = true
        error = nil

        do {
            let endpoint = APIEndpoint(path: "/api/v1/devices/\(deviceId)")
            let fetched: DeviceDetailDTO = try await apiClient.request(endpoint)
            device = fetched
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func toggleMonitoring() async {
        guard let current = device else { return }
        isUpdating = true

        let newStatus = current.isMonitoring ? "connected" : "monitoring"

        do {
            let endpoint = APIEndpoint.Devices.statusUpdate(id: deviceId, status: newStatus)
            let _: EmptyData = try await apiClient.request(endpoint)
            await loadDevice()
        } catch {
            self.error = error.localizedDescription
        }

        isUpdating = false
    }

    func deleteDevice() async {
        isUpdating = true

        do {
            let endpoint = APIEndpoint(path: "/api/v1/devices/\(deviceId)", method: .DELETE)
            let _: EmptyData = try await apiClient.request(endpoint)
            didDelete = true
        } catch {
            self.error = error.localizedDescription
        }

        isUpdating = false
    }

    func shareDevice(email: String) async {
        isUpdating = true

        do {
            let body = ShareDeviceBody(email: email)
            let endpoint = APIEndpoint(
                path: "/api/v1/devices/\(deviceId)/share",
                method: .POST,
                body: body
            )
            let _: EmptyData = try await apiClient.request(endpoint)
            await loadDevice()
        } catch {
            self.error = error.localizedDescription
        }

        isUpdating = false
    }
}

// MARK: - Share Body

struct ShareDeviceBody: Encodable {
    let email: String
}
