import Combine
import Foundation
import HealthKit
import os

private let workoutKgPerPound = 0.45359237
private let activeWorkoutLogger = Logger(subsystem: "com.gearsnitch", category: "ActiveWorkoutVM")

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

// MARK: - Recovery Toast

/// Surfaced by the scene delegate when `HKHealthStore.recoverActiveWorkoutSession`
/// hands back an in-flight session. The view reads this and shows a one-shot
/// toast ("Recovered active workout from before crash"). Purely cosmetic — the
/// real state is already restored into `ActiveWorkoutViewModel`.
struct WorkoutRecoveryToast: Equatable {
    let message: String
    let startedAt: Date
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

    // MARK: - Item #10: iPhone-native workout session

    /// Which transport is tracking this workout. Exposed to the UI so the
    /// "Powered by:" tag can render (see `workoutSource.displayTag`).
    @Published private(set) var workoutSource: WorkoutSource = .timerOnly

    /// Live BPM from the active workout source. Used by the Live Activity
    /// pusher and by the UI. `nil` for the timer-only fallback.
    @Published private(set) var currentBPM: Int?

    /// Live distance (meters) from `HKLiveWorkoutBuilder`. `nil` for non-
    /// cardio activities or the timer-only fallback.
    @Published private(set) var currentDistanceMeters: Double?

    /// Transient one-shot toast set by crash recovery.
    @Published var recoveryToast: WorkoutRecoveryToast?

    // MARK: Dependencies / state

    private var timer: Timer?
    private var liveActivityPusher: Task<Void, Never>?
    private let apiClient = APIClient.shared

    /// The iPhone-native session, if that's the branch we took. Held as
    /// `AnyObject?` because the concrete type is `@available(iOS 26.0, *)`
    /// and we don't want to gate the whole viewmodel on that.
    private var iPhoneSession: AnyObject?

    // MARK: - Formatted

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

    /// Start a workout. Routing (Watch / iPhone HK / timer-only) is decided
    /// by `WorkoutSessionRouter`. The Watch-primary path is preserved: if the
    /// Watch is reachable, this viewmodel does NOT spin up an iPhone-native
    /// `HKWorkoutSession` — the Watch handles it and this method just starts
    /// the local wall-clock for UI.
    func startWorkout() {
        let source = WorkoutSessionRouter.resolve(
            watch: WatchSyncManager.shared,
            health: HKHealthStore()
        )
        startWorkout(source: source)
    }

    /// Test-visible entry point that takes a pre-resolved source.
    func startWorkout(source: WorkoutSource) {
        workoutSource = source
        isActive = true
        startTime = Date()
        elapsedSeconds = 0
        currentBPM = nil
        currentDistanceMeters = nil

        startClockTimer()

        switch source {
        case .watch:
            // Watch-primary path — WatchSyncManager is already observing and
            // pushes start/stop to the Watch via session commands. Nothing
            // for us to spin up on iPhone.
            activeWorkoutLogger.info("Workout routed to Apple Watch (primary)")

        case .iPhoneHealthKit:
            if #available(iOS 26.0, *) {
                startIPhoneNativeSession()
            } else {
                // OS gate flipped between resolve() and here — drop to timer-only.
                workoutSource = .timerOnly
            }

        case .timerOnly:
            activeWorkoutLogger.info("Workout using timer-only fallback (no HR)")
        }

        startLiveActivity()
    }

    /// Rebind this viewmodel to a session that was recovered by the scene
    /// delegate. Assumes iOS 26+ because that's the only OS where the
    /// recovery API exists.
    @available(iOS 26.0, *)
    func attachRecovered(_ session: IPhoneWorkoutSession) {
        let snapshot = session.snapshot()
        workoutSource = .iPhoneHealthKit
        isActive = true
        startTime = snapshot.startedAt
        elapsedSeconds = snapshot.elapsedSeconds
        currentBPM = snapshot.currentBPM
        currentDistanceMeters = snapshot.totalDistanceMeters > 0 ? snapshot.totalDistanceMeters : nil

        iPhoneSession = session
        subscribeToIPhoneSession(session)
        startClockTimer()
        startLiveActivity()

        recoveryToast = WorkoutRecoveryToast(
            message: "Recovered active workout from before crash",
            startedAt: snapshot.startedAt
        )
        activeWorkoutLogger.info(
            "Recovered iPhone workout from scene delegate (elapsed=\(snapshot.elapsedSeconds)s)"
        )
    }

    func endWorkout() async {
        timer?.invalidate()
        timer = nil
        liveActivityPusher?.cancel()
        liveActivityPusher = nil

        // End the underlying transport.
        if #available(iOS 26.0, *), let session = iPhoneSession as? IPhoneWorkoutSession {
            do {
                _ = try await session.end()
            } catch {
                activeWorkoutLogger.error(
                    "Failed to end iPhone workout session: \(error.localizedDescription)"
                )
            }
            iPhoneSession = nil
        }

        await LiveActivityManager.shared.endWorkoutActivity(finalElapsedSeconds: elapsedSeconds)

        guard let start = startTime else { return }

        isSaving = true
        error = nil

        let workoutName = exercises.first?.name.isEmpty == false
            ? "\(exercises[0].name) Session"
            : "Strength Workout"
        let body = CreateWorkoutBody(
            name: workoutName,
            gymId: nil,
            startedAt: start,
            endedAt: Date(),
            notes: nil,
            source: apiSourceTag,
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
        liveActivityPusher?.cancel()
    }

    // MARK: - Internal helpers

    private var apiSourceTag: String {
        switch workoutSource {
        case .watch: return "watch"
        case .iPhoneHealthKit: return "iphone_hk"
        case .timerOnly: return "manual"
        }
    }

    private func startClockTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.elapsedSeconds += 1
            }
        }
    }

    @available(iOS 26.0, *)
    private func startIPhoneNativeSession() {
        do {
            let session = try IPhoneWorkoutSession(
                activityType: .traditionalStrengthTraining,
                locationType: .indoor
            )
            iPhoneSession = session
            subscribeToIPhoneSession(session)
            Task { [weak self] in
                do {
                    try await session.start()
                } catch {
                    await MainActor.run {
                        activeWorkoutLogger.error(
                            "iPhone workout start failed: \(error.localizedDescription)"
                        )
                        self?.workoutSource = .timerOnly
                    }
                }
            }
            activeWorkoutLogger.info("Workout routed to iPhone HealthKit (HKWorkoutSession)")
        } catch {
            activeWorkoutLogger.error("Could not construct HKWorkoutSession: \(error.localizedDescription)")
            workoutSource = .timerOnly
        }
    }

    @available(iOS 26.0, *)
    private func subscribeToIPhoneSession(_ session: IPhoneWorkoutSession) {
        session.onHeartRateSample = { [weak self] bpm, _ in
            Task { @MainActor in
                self?.currentBPM = Int(bpm)
            }
        }
    }

    /// Kick off the Live Activity and spin up a 1Hz pusher that forwards the
    /// latest HR/distance snapshot to ActivityKit. Skipped for the Watch
    /// source — the Watch already has its own on-wrist surface and the
    /// iPhone Live Activity would duplicate it.
    private func startLiveActivity() {
        guard workoutSource != .watch else { return }
        guard let start = startTime else { return }

        let name: String
        switch workoutSource {
        case .iPhoneHealthKit: name = "Workout"
        case .timerOnly: name = "Workout"
        case .watch: name = "Workout"
        }

        LiveActivityManager.shared.startWorkoutActivity(
            activityTypeName: name,
            startedAt: start,
            sourceLabel: workoutSource.displayTag
        )

        liveActivityPusher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                await self?.pushLiveActivityTick()
            }
        }
    }

    private func pushLiveActivityTick() async {
        let zone: String? = currentBPM.map { HeartRateZone.from(bpm: $0).rawValue }
        await LiveActivityManager.shared.updateWorkout(
            currentBPM: currentBPM,
            zone: zone,
            elapsedSeconds: elapsedSeconds,
            distanceMeters: currentDistanceMeters,
            isActive: isActive
        )
    }
}
