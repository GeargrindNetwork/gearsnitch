import Foundation

// MARK: - Workout DTO

private let kgPerPound = 0.45359237

struct WorkoutDTO: Identifiable, Decodable {
    let id: String
    let name: String
    let startedAt: Date
    let endedAt: Date?
    let durationMinutes: Double
    let durationSeconds: Int
    let exerciseCount: Int
    let notes: String?
    let exercises: [ExerciseDTO]
    let gymName: String?
    let source: String?
    let createdAt: Date?
    let updatedAt: Date?
    /// Primary GearComponent attached to this workout (backlog item #9).
    let gearId: String?
    let gearIds: [String]?
    let activityType: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, startedAt, endedAt, durationMinutes, durationSeconds
        case exerciseCount, notes, exercises, gymName, source, createdAt, updatedAt
        case gearId, gearIds, activityType
    }

    var duration: TimeInterval {
        if durationSeconds > 0 {
            return TimeInterval(durationSeconds)
        }

        if let endedAt {
            return endedAt.timeIntervalSince(startedAt)
        }

        return durationMinutes * 60
    }

    var durationString: String {
        let minutes = Int(duration / 60)
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }
}

struct ExerciseDTO: Identifiable, Decodable {
    let id = UUID()
    let name: String
    let sets: [SetDTO]

    enum CodingKeys: String, CodingKey {
        case name, sets
    }
}

struct SetDTO: Identifiable, Decodable {
    let id = UUID()
    let reps: Int
    let weightKg: Double

    enum CodingKeys: String, CodingKey {
        case reps, weightKg
    }

    var weightLbs: Double {
        weightKg / kgPerPound
    }
}

// MARK: - ViewModel

@MainActor
final class WorkoutListViewModel: ObservableObject {

    @Published var workouts: [WorkoutDTO] = []
    @Published var isLoading = false
    @Published var error: String?

    private let apiClient = APIClient.shared

    func loadWorkouts() async {
        isLoading = true
        error = nil

        do {
            let fetched: [WorkoutDTO] = try await apiClient.request(APIEndpoint.Workouts.list)
            workouts = fetched.sorted { $0.startedAt > $1.startedAt }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}
