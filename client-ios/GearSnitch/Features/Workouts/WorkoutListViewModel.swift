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
    /// Server-stored calorie burn when the workout came from HealthKit /
    /// Watch (they provide a precise number from `totalEnergyBurned`). When
    /// `nil`, the iOS client estimates locally from duration × MET × weight.
    let calories: Double?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, startedAt, endedAt, durationMinutes, durationSeconds
        case exerciseCount, notes, exercises, gymName, source, createdAt, updatedAt
        case gearId, gearIds, activityType, calories
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

    // MARK: - Calorie Estimation

    /// Estimated calorie burn, preferring the server value when present and
    /// otherwise computing `kcal = MET × weight_kg × hours`. `weightKg` is
    /// the user's current weight; callers that don't have one available can
    /// pass `nil` to get a neutral 70 kg default so the label still renders
    /// rather than blanking out.
    func estimatedCalories(weightKg: Double?) -> Double? {
        if let calories, calories > 0 {
            return calories
        }

        let hours = duration / 3_600
        guard hours > 0 else { return nil }

        let met = Self.metValue(for: activityType)
        let effectiveWeight = (weightKg ?? 0) > 0 ? (weightKg ?? 70) : 70
        return met * effectiveWeight * hours
    }

    /// Formatted label for the estimated calorie burn. Returns `nil` when the
    /// workout has no duration data.
    func calorieLabel(weightKg: Double?) -> String? {
        guard let calories = estimatedCalories(weightKg: weightKg) else {
            return nil
        }
        return "\(Int(calories.rounded())) cal"
    }

    /// Table of MET values for the activity types surfaced by the picker.
    /// Source: Compendium of Physical Activities (Ainsworth et al., 2011).
    /// Values are intentionally conservative averages — they're used as a
    /// display estimate, not a medical calculation.
    private static func metValue(for activityType: String?) -> Double {
        guard let activityType else { return 5.0 }
        switch activityType.lowercased() {
        case "running":             return 9.8
        case "cycling":             return 7.5
        case "walking":             return 3.5
        case "swimming":            return 8.0
        case "strengthtraining",
             "strength_training":   return 5.0
        case "yoga":                return 2.5
        case "hiit":                return 10.5
        case "padel",
             "paddlesports":        return 7.0
        case "pickleball":          return 5.5
        case "volleyball":          return 4.0
        case "cricket":             return 4.8
        case "dance",
             "socialdance",
             "cardiodance":         return 5.0
        case "crosstraining",
             "cross_training":      return 6.0
        case "elliptical":          return 5.0
        case "rowing":              return 7.0
        case "stairclimbing",
             "stair_climbing":      return 8.8
        default:                    return 5.0
        }
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
    /// Captured once from `/users/me` so calorie estimates can use the user's
    /// real weight instead of the 70 kg fallback. Stored in kilograms.
    @Published var userWeightKg: Double?

    /// Backed by `.alert` on the view — the workout waiting for the user's
    /// confirmation. Nil when no confirmation is outstanding.
    @Published var pendingDeletion: WorkoutDTO?

    private let apiClient = APIClient.shared

    func loadWorkouts() async {
        isLoading = true
        error = nil

        async let userWeight = fetchUserWeightKg()

        do {
            let fetched: [WorkoutDTO] = try await apiClient.request(APIEndpoint.Workouts.list)
            workouts = fetched.sorted { $0.startedAt > $1.startedAt }
        } catch {
            self.error = error.localizedDescription
        }

        userWeightKg = await userWeight
        isLoading = false
    }

    /// Pull the profile payload just to grab `weightLbs`. Kept tolerant of
    /// decode failures (e.g. preview contexts) because the only observable
    /// symptom of an error is falling back to the 70 kg default — not a bug.
    private func fetchUserWeightKg() async -> Double? {
        do {
            let profile: ProfileDTO = try await apiClient.request(APIEndpoint.Users.me)
            if let lbs = profile.weightLbs, lbs > 0 {
                return lbs * kgPerPound
            }
        } catch {
            // Swallow — calorie estimate just falls back to the 70 kg default.
        }
        return nil
    }

    /// POST DELETE /api/v1/workouts/:id and optimistically remove from the
    /// local list. On error the workout is re-inserted so the UI reflects
    /// the true server state.
    func deleteWorkout(_ workout: WorkoutDTO) async {
        let originalWorkouts = workouts
        workouts.removeAll { $0.id == workout.id }

        do {
            let _: EmptyData = try await apiClient.request(
                APIEndpoint.Workouts.delete(id: workout.id)
            )
        } catch {
            self.error = error.localizedDescription
            workouts = originalWorkouts
        }
    }
}
