import Foundation

// MARK: - Workout DTO

struct WorkoutDTO: Identifiable, Decodable {
    let id: String
    let type: String
    let startDate: Date
    let endDate: Date
    let caloriesBurned: Double?
    let heartRateAvg: Double?
    let notes: String?
    let exercises: [ExerciseDTO]?
    let gymName: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case type, startDate, endDate, caloriesBurned
        case heartRateAvg, notes, exercises, gymName, createdAt
    }

    var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }

    var durationString: String {
        let minutes = Int(duration / 60)
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }

    var exerciseCount: Int {
        exercises?.count ?? 0
    }
}

struct ExerciseDTO: Identifiable, Decodable {
    let id: String
    let name: String
    let sets: [SetDTO]

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, sets
    }
}

struct SetDTO: Identifiable, Decodable {
    let id: String
    let reps: Int
    let weight: Double?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case reps, weight
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
            workouts = fetched.sorted { $0.startDate > $1.startDate }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}
