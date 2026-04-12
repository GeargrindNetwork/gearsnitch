import Foundation

@MainActor
final class RunHistoryViewModel: ObservableObject {

    @Published var runs: [RunDTO] = []
    @Published var isLoading = false
    @Published var error: String?

    private let apiClient = APIClient.shared

    var completedRuns: [RunDTO] {
        runs.filter { $0.status == "completed" }
    }

    func loadRuns() async {
        isLoading = true
        error = nil

        do {
            let fetched: [RunDTO] = try await apiClient.request(APIEndpoint.Runs.list)
            runs = fetched.sorted { $0.startedAt > $1.startedAt }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func loadDetail(id: String) async throws -> RunDTO {
        try await apiClient.request(APIEndpoint.Runs.detail(id: id))
    }
}
