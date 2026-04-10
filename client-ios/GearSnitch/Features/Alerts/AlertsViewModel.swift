import Foundation

// MARK: - Alert DTO

struct AlertDTO: Identifiable, Decodable {
    let id: String
    let type: String
    let severity: String
    let message: String
    let deviceId: String?
    let deviceName: String?
    let latitude: Double?
    let longitude: Double?
    let acknowledged: Bool
    let acknowledgedAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case type, severity, message, deviceId, deviceName
        case latitude, longitude, acknowledged, acknowledgedAt, createdAt
    }

    var typeIcon: String {
        switch type {
        case "device_disconnected": return "antenna.radiowaves.left.and.right.slash"
        case "device_left_zone": return "location.slash.fill"
        case "low_battery": return "battery.25"
        case "tamper_detected": return "exclamationmark.shield.fill"
        case "motion_detected": return "figure.walk.motion"
        default: return "bell.fill"
        }
    }

    var severityColor: String {
        switch severity {
        case "critical": return "red"
        case "high": return "orange"
        case "medium": return "yellow"
        default: return "gray"
        }
    }
}

// MARK: - ViewModel

@MainActor
final class AlertsViewModel: ObservableObject {

    @Published var alerts: [AlertDTO] = []
    @Published var isLoading = false
    @Published var error: String?

    private let apiClient = APIClient.shared

    var activeAlerts: [AlertDTO] {
        alerts.filter { !$0.acknowledged }
    }

    var acknowledgedAlerts: [AlertDTO] {
        alerts.filter { $0.acknowledged }
    }

    func loadAlerts() async {
        isLoading = true
        error = nil

        do {
            let fetched: [AlertDTO] = try await apiClient.request(APIEndpoint.Alerts.list)
            alerts = fetched
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func acknowledgeAlert(id: String) async {
        do {
            let _: EmptyData = try await apiClient.request(APIEndpoint.Alerts.acknowledge(id: id))
            if let index = alerts.firstIndex(where: { $0.id == id }) {
                // Re-fetch to get updated state
                await loadAlerts()
                _ = index // suppress unused warning
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
