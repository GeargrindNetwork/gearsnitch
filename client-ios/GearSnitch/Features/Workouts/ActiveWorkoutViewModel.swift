import Foundation

private let workoutKgPerPound = 0.45359237

// MARK: - Exercise Models

struct WorkoutExercise: Identifiable {
    let id = UUID()
    var name: String
    var sets: [WorkoutSet]
}

struct WorkoutSet: Identifiable {
    let id = UUID()
    var reps: Int
    var weight: Double
}

// MARK: - ViewModel

@MainActor
final class ActiveWorkoutViewModel: ObservableObject {

    @Published var isActive = false
    @Published var startTime: Date?
    @Published var exercises: [WorkoutExercise] = []
    @Published var elapsedSeconds: Int = 0
    @Published var isSaving = false
    @Published var error: String?
    @Published var didComplete = false

    // Add exercise sheet
    @Published var showAddExercise = false
    @Published var newExerciseName = ""

    /// Backlog item #9 — default gear pre-fetched for this workout's
    /// activity type. Defaults to the user's `strengthTraining` preference
    /// for the gym workouts this view powers today; the iPhone-native
    /// HKWorkoutSession path (item #10) will plumb the real activity
    /// type through here. User can override before tapping Start.
    @Published var defaultGearId: String?
    @Published var defaultGearName: String?
    @Published var activityType: String = "strengthTraining"

    private var timer: Timer?
    private let apiClient = APIClient.shared

    var elapsedFormatted: String {
        let hours = elapsedSeconds / 3600
        let minutes = (elapsedSeconds % 3600) / 60
        let seconds = elapsedSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Session

    func startWorkout() {
        isActive = true
        startTime = Date()
        elapsedSeconds = 0

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.elapsedSeconds += 1
            }
        }
    }

    /// Pre-fetch the user's default gear for this activity type so the
    /// UI can show "Will auto-attach: <gear name>" before the user taps
    /// Start. Non-fatal — silently leaves defaults nil if the lookup fails.
    func loadDefaultGear() async {
        do {
            let response: DefaultGearForActivityDTO = try await apiClient.request(
                APIEndpoint.Gear.defaultForActivity(type: activityType)
            )
            defaultGearId = response.gear?.id
            defaultGearName = response.gear?.name
        } catch {
            defaultGearId = nil
            defaultGearName = nil
        }
    }

    /// Clear the auto-attach for this workout (user tapped "No gear").
    /// Server-side we send `gearId: null` at create time to disable the
    /// auto-attach override.
    func clearDefaultGear() {
        defaultGearId = nil
        defaultGearName = nil
    }

    func endWorkout() async {
        timer?.invalidate()
        timer = nil

        guard let start = startTime else { return }

        isSaving = true
        error = nil

        let workoutName = exercises.first?.name.isEmpty == false
            ? "\(exercises[0].name) Session"
            : "Strength Workout"
        var body = CreateWorkoutBody(
            name: workoutName,
            gymId: nil,
            startedAt: start,
            endedAt: Date(),
            notes: nil,
            source: "manual",
            exercises: exercises.map { exercise in
                CreateWorkoutExerciseBody(
                    name: exercise.name,
                    sets: exercise.sets.map { workoutSet in
                        CreateWorkoutSetBody(
                            reps: workoutSet.reps,
                            weightKg: workoutSet.weight * workoutKgPerPound
                        )
                    }
                )
            }
        )
        // Backlog item #9 — let the server resolve the default gear from
        // the user's preferences. Passing activityType (without gearId)
        // means "auto-attach the default for this activity". Explicit
        // gearId wins when the user overrode the pre-filled selection.
        body.activityType = activityType
        if let gearId = defaultGearId {
            body.gearId = gearId
        }

        do {
            let _: WorkoutDTO = try await apiClient.request(APIEndpoint.Workouts.create(body))
            didComplete = true
        } catch {
            self.error = error.localizedDescription
        }

        isSaving = false
    }

    // MARK: - Exercises

    func addExercise() {
        guard !newExerciseName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let exercise = WorkoutExercise(name: newExerciseName, sets: [])
        exercises.append(exercise)
        newExerciseName = ""
        showAddExercise = false
    }

    func addSet(to exerciseId: UUID) {
        guard let index = exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        let newSet = WorkoutSet(reps: 0, weight: 0)
        exercises[index].sets.append(newSet)
    }

    func updateSet(exerciseId: UUID, setId: UUID, reps: Int, weight: Double) {
        guard let eIdx = exercises.firstIndex(where: { $0.id == exerciseId }),
              let sIdx = exercises[eIdx].sets.firstIndex(where: { $0.id == setId }) else { return }
        exercises[eIdx].sets[sIdx].reps = reps
        exercises[eIdx].sets[sIdx].weight = weight
    }

    func removeExercise(at offsets: IndexSet) {
        exercises.remove(atOffsets: offsets)
    }

    deinit {
        timer?.invalidate()
    }
}
