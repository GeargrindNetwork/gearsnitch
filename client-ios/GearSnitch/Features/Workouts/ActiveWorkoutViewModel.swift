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
    /// Backlog item #16 — marked true when the user taps "Log Set",
    /// which also triggers the rest-timer overlay.
    var completed: Bool = false
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

    // Rest timer (backlog item #16) — non-nil when the overlay is showing.
    @Published var restTimer: RestTimerState?

    /// Which (exercise, set) pair should be focused when the rest timer
    /// completes AND the user has `autoAdvance` enabled. The view
    /// observes this and moves focus to the corresponding reps field.
    @Published var autoFocusSetId: UUID?

    private let restTimerPreferences: RestTimerPreferences

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

    init(restTimerPreferences: RestTimerPreferences = RestTimerPreferences()) {
        self.restTimerPreferences = restTimerPreferences
    }

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

    // MARK: - Rest Timer (backlog item #16)

    /// Log-set action: marks the set as complete and (if enabled)
    /// presents the rest timer overlay. The overlay is dismissed by
    /// `dismissRestTimer()` — skip, completion, or explicit "Next set".
    func logSet(exerciseId: UUID, setId: UUID) {
        guard let eIdx = exercises.firstIndex(where: { $0.id == exerciseId }),
              let sIdx = exercises[eIdx].sets.firstIndex(where: { $0.id == setId }) else { return }
        exercises[eIdx].sets[sIdx].completed = true

        guard restTimerPreferences.isEnabled else { return }

        let duration = restTimerPreferences.defaultSeconds
        let state = RestTimerState(duration: duration)
        state.onComplete = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.restTimerPreferences.autoAdvance {
                    self.autoAdvanceToNextSet(after: exerciseId)
                }
            }
        }
        restTimer = state
    }

    /// Dismiss the overlay (called by the view on skip / complete).
    func dismissRestTimer() {
        restTimer = nil
    }

    /// Pick the next empty set on `exerciseId` and focus its reps field.
    /// If no empty set exists, append one and focus it.
    private func autoAdvanceToNextSet(after exerciseId: UUID) {
        guard let eIdx = exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        if let nextSet = exercises[eIdx].sets.first(where: { !$0.completed }) {
            autoFocusSetId = nextSet.id
        } else {
            let newSet = WorkoutSet(reps: 0, weight: 0)
            exercises[eIdx].sets.append(newSet)
            autoFocusSetId = newSet.id
        }
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
