// iOS-26-only: HKLiveWorkoutBuilder on iPhone was added in iOS 26.
// Xcode 16.4 (CI runner) ships iOS 18 SDK and doesn't expose the type
// on iPhone yet. Gate at compile time so the code compiles on both
// Xcode 16 (skip — feature dormant) and Xcode 26+ (include — active).
#if compiler(>=6.2) && os(iOS)

import Combine
import Foundation
import HealthKit
import os

// MARK: - iPhone Workout Session (iOS 26+)
//
// iPhone-side wrapper around `HKWorkoutSession` + `HKLiveWorkoutBuilder` for
// users who do NOT have a paired Apple Watch. Mirrors the Watch-side patterns
// in `WatchHealthManager.swift` (same prepare → start → pause/resume → end
// lifecycle, same `HKLiveWorkoutDataSource`) so downstream code (viewmodels,
// Live Activity, batch HR sync) can handle either transport uniformly.
//
// IMPORTANT — Watch primacy:
//   * When a paired Watch is present and reachable, GearSnitch routes workouts
//     through the Watch. This iPhone-native path is strictly a FALLBACK.
//     See `WorkoutSessionRouter` for the branching decision.
//   * Watch + iPhone sessions never run simultaneously for the same workout.
//     `WorkoutSessionRouter` picks one source per session.
//
// Crash recovery:
//   * iOS 26 adds `HKHealthStore.recoverActiveWorkoutSession(completion:)` so
//     an in-flight session survives an iPhone-app crash. The scene delegate
//     (`SceneDelegate.swift`) calls that on scene reconnection and re-binds
//     the recovered `HKWorkoutSession` to a new `IPhoneWorkoutSession`
//     instance via `attachRecovered(session:)`.

@available(iOS 26.0, *)
@MainActor
final class IPhoneWorkoutSession: NSObject, ObservableObject {

    // MARK: Published state

    @Published private(set) var state: HKWorkoutSessionState = .notStarted
    @Published private(set) var startedAt: Date?
    @Published private(set) var endedAt: Date?
    @Published private(set) var currentBPM: Double?
    @Published private(set) var totalEnergyKcal: Double = 0
    @Published private(set) var totalDistanceMeters: Double = 0
    @Published private(set) var sampleCount: Int = 0

    var statePublisher: Published<HKWorkoutSessionState>.Publisher { $state }

    /// Computed elapsed time. Uses `workoutBuilder.elapsedTime(at:)` while
    /// running so HealthKit's canonical clock (which correctly accounts for
    /// paused intervals) is the source of truth.
    var elapsedTime: TimeInterval {
        if let started = startedAt, let ended = endedAt {
            return ended.timeIntervalSince(started)
        }
        guard let started = startedAt else { return 0 }
        // While running, consult the builder's elapsed time so paused intervals
        // are excluded. Fall back to wall-clock if the builder hasn't begun.
        return workoutBuilder.elapsedTime(at: Date()) == 0
            ? Date().timeIntervalSince(started)
            : workoutBuilder.elapsedTime(at: Date())
    }

    // MARK: Dependencies

    private let healthStore: HKHealthStore
    private let configuration: HKWorkoutConfiguration
    private let logger = Logger(subsystem: "com.gearsnitch", category: "IPhoneWorkoutSession")

    // MARK: Stored state

    private(set) var session: HKWorkoutSession
    private(set) var workoutBuilder: HKLiveWorkoutBuilder

    /// Optional hook the owning viewmodel uses to observe HR samples without
    /// needing to subscribe to `HKLiveWorkoutBuilder` directly.
    var onHeartRateSample: ((Double, Date) -> Void)?

    /// Fires when the workout ends and the builder finishes — the resulting
    /// `HKWorkout` is passed through so the caller can sync it to the backend.
    var onFinish: ((HKWorkout?) -> Void)?

    // MARK: Init

    /// Designated initializer.
    init(
        activityType: HKWorkoutActivityType,
        locationType: HKWorkoutSessionLocationType,
        healthStore: HKHealthStore = HKHealthStore()
    ) throws {
        let config = HKWorkoutConfiguration()
        config.activityType = activityType
        config.locationType = locationType
        self.configuration = config
        self.healthStore = healthStore

        let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
        self.session = session
        self.workoutBuilder = session.associatedWorkoutBuilder()
        self.workoutBuilder.dataSource = HKLiveWorkoutDataSource(
            healthStore: healthStore,
            workoutConfiguration: config
        )

        super.init()

        session.delegate = self
        workoutBuilder.delegate = self
    }

    /// Rebind this wrapper to a session that was recovered by
    /// `HKHealthStore.recoverActiveWorkoutSession(completion:)`. The new
    /// session retains its associated builder and the HR sample history that
    /// accumulated before the crash — we re-subscribe as delegate.
    init(recovered session: HKWorkoutSession, healthStore: HKHealthStore = HKHealthStore()) {
        self.configuration = session.workoutConfiguration
        self.healthStore = healthStore
        self.session = session
        self.workoutBuilder = session.associatedWorkoutBuilder()
        if self.workoutBuilder.dataSource == nil {
            self.workoutBuilder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: session.workoutConfiguration
            )
        }
        super.init()
        session.delegate = self
        workoutBuilder.delegate = self
        // Pick up whatever state the session is currently in.
        self.state = session.state
        self.startedAt = session.startDate ?? Date()
    }

    // MARK: Lifecycle

    /// Start the workout session and begin builder collection.
    func start() async throws {
        guard state == .notStarted || state == .ended else {
            logger.info("start() ignored — session already in state \(self.state.rawValue)")
            return
        }
        let startDate = Date()
        session.startActivity(with: startDate)
        try await beginCollection(at: startDate)
        startedAt = startDate
        endedAt = nil
        sampleCount = 0
        totalEnergyKcal = 0
        totalDistanceMeters = 0
        logger.info("iPhone workout started at \(startDate, privacy: .public)")
    }

    /// Pause the workout — the session reports back `.paused` via delegate.
    func pause() {
        guard state == .running else { return }
        session.pause()
    }

    /// Resume a paused workout.
    func resume() {
        guard state == .paused else { return }
        session.resume()
    }

    /// End the workout and finish the builder. Returns the persisted
    /// `HKWorkout` on success.
    @discardableResult
    func end() async throws -> HKWorkout? {
        guard state == .running || state == .paused else {
            logger.info("end() ignored — session not running (state=\(self.state.rawValue))")
            return nil
        }
        let endDate = Date()
        session.end()
        try await endCollection(at: endDate)
        endedAt = endDate
        let workout = try await finishWorkout()
        onFinish?(workout)
        return workout
    }

    // MARK: Recovery helpers

    /// Return a best-effort `ActiveWorkoutSnapshot` from the live builder's
    /// statistics. Used by the scene delegate when restoring viewmodel state
    /// after a crash.
    func snapshot() -> ActiveWorkoutSnapshot {
        let hrType = HKQuantityType(.heartRate)
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        let latestBPM = workoutBuilder.statistics(for: hrType)?
            .mostRecentQuantity()?
            .doubleValue(for: bpmUnit)

        return ActiveWorkoutSnapshot(
            activityType: configuration.activityType,
            startedAt: startedAt ?? session.startDate ?? Date(),
            elapsedSeconds: Int(elapsedTime),
            currentBPM: latestBPM.map(Int.init) ?? currentBPM.map(Int.init),
            totalEnergyKcal: totalEnergyKcal,
            totalDistanceMeters: totalDistanceMeters,
            state: state
        )
    }

    // MARK: Private — Builder bridges

    private func beginCollection(at date: Date) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            workoutBuilder.beginCollection(withStart: date) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(
                        throwing: IPhoneWorkoutSessionError.builderBeginFailed
                    )
                }
            }
        }
    }

    private func endCollection(at date: Date) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            workoutBuilder.endCollection(withEnd: date) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func finishWorkout() async throws -> HKWorkout? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HKWorkout?, Error>) in
            workoutBuilder.finishWorkout { workout, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: workout)
                }
            }
        }
    }
}

// MARK: - HKWorkoutSessionDelegate

@available(iOS 26.0, *)
extension IPhoneWorkoutSession: HKWorkoutSessionDelegate {

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            self.state = toState
            self.logger.info(
                "iPhone workout state: \(fromState.rawValue) -> \(toState.rawValue)"
            )
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            self.logger.error("iPhone workout session failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

@available(iOS 26.0, *)
extension IPhoneWorkoutSession: HKLiveWorkoutBuilderDelegate {

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // No-op: events surface through `didCollectDataOf:` for our HR-centric flow.
    }

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        let hrType = HKQuantityType(.heartRate)
        let energyType = HKQuantityType(.activeEnergyBurned)
        let distanceType = HKQuantityType(.distanceWalkingRunning)

        Task { @MainActor in
            self.sampleCount += 1

            if collectedTypes.contains(hrType),
               let stats = workoutBuilder.statistics(for: hrType) {
                let unit = HKUnit.count().unitDivided(by: .minute())
                if let latest = stats.mostRecentQuantity()?.doubleValue(for: unit),
                   let at = stats.mostRecentQuantityDateInterval()?.end {
                    self.currentBPM = latest
                    self.onHeartRateSample?(latest, at)
                }
            }

            if collectedTypes.contains(energyType),
               let stats = workoutBuilder.statistics(for: energyType),
               let kcal = stats.sumQuantity()?.doubleValue(for: .kilocalorie()) {
                self.totalEnergyKcal = kcal
            }

            if collectedTypes.contains(distanceType),
               let stats = workoutBuilder.statistics(for: distanceType),
               let meters = stats.sumQuantity()?.doubleValue(for: .meter()) {
                self.totalDistanceMeters = meters
            }
        }
    }
}

// MARK: - Snapshot + Errors

/// Lightweight value used by crash recovery to restore viewmodel state from
/// a live workout session/builder without needing the full HealthKit stack.
struct ActiveWorkoutSnapshot: Equatable {
    let activityType: HKWorkoutActivityType
    let startedAt: Date
    let elapsedSeconds: Int
    let currentBPM: Int?
    let totalEnergyKcal: Double
    let totalDistanceMeters: Double
    let state: HKWorkoutSessionState
}

enum IPhoneWorkoutSessionError: LocalizedError {
    case builderBeginFailed

    var errorDescription: String? {
        switch self {
        case .builderBeginFailed:
            return "HealthKit refused to begin the workout builder."
        }
    }
}

#else

// Stub surface for Xcode <26 (iOS <26 SDK). The feature is dormant at
// runtime (WorkoutSessionRouter never returns .iPhoneHealthKit on iOS <26
// per its #available check), so none of these code paths execute — they
// exist solely to keep callers compiling on the older toolchain.

import Combine
import Foundation
import HealthKit

@MainActor
final class IPhoneWorkoutSession: NSObject, ObservableObject {
    @Published private(set) var state: HKWorkoutSessionState = .notStarted
    @Published private(set) var bpm: Int?
    @Published private(set) var distanceMeters: Double?

    /// Heart-rate callback set by the viewmodel. Stub never invokes it.
    var onHeartRateSample: ((Double, Date) -> Void)?

    init(activityType: HKWorkoutActivityType, locationType: HKWorkoutSessionLocationType) throws {
        throw IPhoneWorkoutSessionError.builderBeginFailed
    }

    init(recovered: HKWorkoutSession, healthStore: HKHealthStore = HKHealthStore()) {
        super.init()
    }

    func start() async throws { throw IPhoneWorkoutSessionError.builderBeginFailed }
    func pause() {}
    func resume() {}
    func end() async throws -> HKWorkout? { nil }
    var elapsedTime: TimeInterval { 0 }
    func snapshot() -> ActiveWorkoutSnapshot { ActiveWorkoutSnapshot() }
}

struct ActiveWorkoutSnapshot: Equatable {
    var startedAt: Date = Date()
    var elapsedSeconds: Int = 0
    var currentBPM: Int? = nil
    var totalDistanceMeters: Double = 0
}

enum IPhoneWorkoutSessionError: LocalizedError {
    case builderBeginFailed
    var errorDescription: String? { "iPhone-native workout requires iOS 26." }
}

#endif // compiler(>=6.2) && os(iOS)
