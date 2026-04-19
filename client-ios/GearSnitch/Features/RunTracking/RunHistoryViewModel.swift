import Foundation

@MainActor
final class RunHistoryViewModel: ObservableObject {

    @Published var runs: [RunDTO] = []
    @Published var isLoading = false
    @Published var error: String?
    /// Backed by `.alert` on the view — the run waiting for the user's
    /// confirmation. Nil when no confirmation is outstanding.
    @Published var pendingDeletion: RunDTO?

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

    /// DELETE /api/v1/runs/:id with optimistic local removal. See
    /// `WorkoutListViewModel.deleteWorkout` for the shared pattern — we
    /// re-insert on error so a failed delete doesn't silently drop a run
    /// from the user's history.
    func deleteRun(_ run: RunDTO) async {
        let original = runs
        runs.removeAll { $0.id == run.id }

        do {
            let _: EmptyData = try await apiClient.request(
                APIEndpoint.Runs.delete(id: run.id)
            )
        } catch {
            self.error = error.localizedDescription
            runs = original
        }
    }
}
