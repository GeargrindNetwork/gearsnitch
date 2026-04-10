import Foundation

// MARK: - Gym DTO

struct GymDTO: Identifiable, Decodable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let radiusMeters: Double
    let isDefault: Bool
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, latitude, longitude, radiusMeters, isDefault, createdAt
    }
}

// MARK: - ViewModel

@MainActor
final class GymListViewModel: ObservableObject {

    @Published var gyms: [GymDTO] = []
    @Published var isLoading = false
    @Published var error: String?

    private let apiClient = APIClient.shared

    func loadGyms() async {
        isLoading = true
        error = nil

        do {
            let fetched: [GymDTO] = try await apiClient.request(APIEndpoint.Gyms.list)
            gyms = fetched
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func setDefault(gymId: String) async {
        do {
            let endpoint = APIEndpoint(
                path: "/api/v1/gyms/\(gymId)/default",
                method: .PATCH
            )
            let _: EmptyData = try await apiClient.request(endpoint)
            await loadGyms()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteGym(gymId: String) async {
        do {
            let endpoint = APIEndpoint(path: "/api/v1/gyms/\(gymId)", method: .DELETE)
            let _: EmptyData = try await apiClient.request(endpoint)
            gyms.removeAll { $0.id == gymId }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
