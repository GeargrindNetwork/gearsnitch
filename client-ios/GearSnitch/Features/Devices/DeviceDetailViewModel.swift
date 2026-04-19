import Foundation

// MARK: - Device Detail DTO

struct DeviceDetailDTO: Identifiable, Decodable {
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
    let isMonitoring: Bool
    let sharedWith: [String]?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, nickname, type, bluetoothIdentifier, status
        case firmwareVersion, signalStrength, lastSeenAt
        case isFavorite, isMonitoring, sharedWith, createdAt
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
    /// Gear components (shoe, chain, ...) linked to this paired BLE device.
    /// Populated lazily after the device payload arrives so the badge renders
    /// without blocking the primary device-detail load.
    @Published var linkedGear: [GearComponentDTO] = []

    let deviceId: String
    private let apiClient = APIClient.shared

    init(deviceId: String) {
        self.deviceId = deviceId
    }

    func loadDevice() async {
        isLoading = true
        error = nil

        do {
            let endpoint = APIEndpoint.Devices.detail(id: deviceId)
            let fetched: DeviceDetailDTO = try await apiClient.request(endpoint)
            device = fetched
            BLEManager.shared.upsertPersistedMetadata(fetched.priorityMetadata)
            DeviceEventSyncService.shared.cacheRegisteredDevice(
                id: fetched.id,
                name: fetched.displayName,
                bluetoothIdentifier: fetched.bluetoothIdentifier,
                status: fetched.status,
                lastSeenAt: fetched.lastSeenAt,
                signalStrength: fetched.signalStrength,
                isSynced: true
            )
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
        // Fire-and-forget — the gear list loads asynchronously and is purely
        // additive UI (a badge). Failures are silent so the primary device
        // experience stays unaffected.
        Task { await loadLinkedGear() }
    }

    /// Loads gear components linked to this device so we can show a small
    /// "Shoes — 312/400mi" badge inline on DeviceDetailView. Silent on
    /// failure — the badge is purely additive.
    func loadLinkedGear() async {
        do {
            let all = try await GearService.shared.list()
            linkedGear = all.filter { $0.deviceId == deviceId }
        } catch {
            // Silent — badge is non-critical.
            linkedGear = []
        }
    }

    func toggleMonitoring() async {
        guard let current = device else { return }
        isUpdating = true

        let newStatus = current.isMonitoring ? "connected" : "monitoring"

        do {
            let endpoint = APIEndpoint.Devices.statusUpdate(
                id: deviceId,
                body: DeviceStatusUpdateBody(status: newStatus)
            )
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

    func updatePriority(nickname: String, isFavorite: Bool) async {
        guard let current = device else { return }
        isUpdating = true

        do {
            let body = UpdateDeviceBody(
                name: nil,
                nickname: nickname,
                type: nil,
                isFavorite: isFavorite
            )
            let endpoint = APIEndpoint.Devices.update(id: deviceId, body: body)
            let updated: DeviceDetailDTO = try await apiClient.request(endpoint)
            device = updated
            BLEManager.shared.upsertPersistedMetadata(updated.priorityMetadata)
        } catch {
            self.error = error.localizedDescription
            device = current
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
