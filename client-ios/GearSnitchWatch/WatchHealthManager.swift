import Foundation
import HealthKit
import os
#if os(watchOS)
import WatchKit
#endif

// MARK: - WatchHealthManager
//
// Watch-side HealthKit + workout session orchestrator. Owns:
//
//   * HealthKit read auth for HR (and ECG, workout types)
//   * Anchored HR query against the watch's local HealthKit store (sub-second
//     samples while monitoring, even outside an active workout)
//   * `HKWorkoutSession` + `HKLiveWorkoutBuilder` (when the user starts a
//     workout — gives the watch system priority on HR sampling at 1–5 s cadence)
//   * Publishes the latest BPM, a rolling sparkline buffer, and the workout
//     state machine for the SwiftUI layer.
//
// All forwarding to the iPhone is done by `WatchHRDispatcher` via callbacks so
// this class stays focused on health/workout concerns.

@MainActor
final class WatchHealthManager: NSObject, ObservableObject {

    static let shared = WatchHealthManager()

    // MARK: Published state

    @Published private(set) var authorizationStatus: HKAuthorizationStatus = .notDetermined
    @Published private(set) var isMonitoring = false
    @Published private(set) var workoutState: WatchWorkoutState = .idle
    @Published private(set) var workoutStartedAt: Date?
    @Published private(set) var workoutEndedAt: Date?
    @Published private(set) var totalWorkoutSamples: Int = 0

    @Published private(set) var currentBPM: Double?
    @Published private(set) var lastSampleAt: Date?
    /// Rolling 5-minute window of `(timestamp, bpm)` for the sparkline.
    @Published private(set) var recentSamples: [WatchHRSamplePayload] = []

    // MARK: Dependencies

    private let healthStore = HKHealthStore()
    private let logger = Logger(subsystem: "com.gearsnitch.watch", category: "WatchHealthManager")
    private let sparkWindow: TimeInterval = 5 * 60

    private var anchoredQuery: HKAnchoredObjectQuery?
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?

    /// External handler invoked for every new HR sample (used by the dispatcher).
    var onSample: ((WatchHRSamplePayload) -> Void)?
    /// External handler invoked when the workout state machine transitions.
    var onWorkoutStateChange: ((WatchWorkoutStatePayload) -> Void)?

    // MARK: Init

    override private init() {
        super.init()
    }

    // MARK: Authorization

    /// Read-only types we ask the user to grant. ECG is included so the deep-link
    /// to the system Health app can present recordings without re-prompting.
    var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        if let hr = HKObjectType.quantityType(forIdentifier: .heartRate) { types.insert(hr) }
        if let hrv = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) { types.insert(hrv) }
        if let oxy = HKObjectType.quantityType(forIdentifier: .oxygenSaturation) { types.insert(oxy) }
        if let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(energy) }
        if #available(watchOS 10.0, *), let ecg = HKObjectType.electrocardiogramType() as HKObjectType? {
            types.insert(ecg)
        }
        types.insert(HKObjectType.workoutType())
        return types
    }

    /// Types the live workout builder will write back to HealthKit. We must hold
    /// share permission on these so `HKLiveWorkoutBuilder` can persist the workout.
    var shareTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [HKObjectType.workoutType()]
        if let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(energy) }
        return types
    }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            logger.warning("HealthKit not available on this device")
            return
        }
        do {
            try await healthStore.requestAuthorization(toShare: shareTypes, read: readTypes)
            updateAuthorizationStatus()
        } catch {
            logger.error("HK authorization failed: \(error.localizedDescription)")
        }
    }

    func updateAuthorizationStatus() {
        guard let hr = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        authorizationStatus = healthStore.authorizationStatus(for: hr)
    }

    // MARK: HR monitoring (no workout)

    func startMonitoring() {
        guard !isMonitoring else { return }
        guard HKHealthStore.isHealthDataAvailable(),
              let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }

        isMonitoring = true
        logger.info("startMonitoring (anchored HR query)")

        let query = HKAnchoredObjectQuery(
            type: hrType,
            predicate: HKQuery.predicateForSamples(withStart: Date(), end: nil, options: .strictStartDate),
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, _ in
            Task { @MainActor in self?.process(samples: samples) }
        }
        query.updateHandler = { [weak self] _, samples, _, _, _ in
            Task { @MainActor in self?.process(samples: samples) }
        }
        anchoredQuery = query
        healthStore.execute(query)
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        if let q = anchoredQuery { healthStore.stop(q) }
        anchoredQuery = nil
        isMonitoring = false
        logger.info("stopMonitoring")
    }

    // MARK: Workout control

    func startWorkout(activity: HKWorkoutActivityType = .functionalStrengthTraining) {
        guard workoutState == .idle || workoutState == .ended else {
            logger.info("startWorkout ignored — current state \(self.workoutState.rawValue, privacy: .public)")
            return
        }
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let config = HKWorkoutConfiguration()
        config.activityType = activity
        config.locationType = .indoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
            session.delegate = self
            builder.delegate = self

            workoutSession = session
            workoutBuilder = builder

            let startDate = Date()
            session.startActivity(with: startDate)
            builder.beginCollection(withStart: startDate) { [weak self] success, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.logger.error("beginCollection failed: \(error.localizedDescription)")
                    }
                    if success {
                        self.workoutState = .running
                        self.workoutStartedAt = startDate
                        self.workoutEndedAt = nil
                        self.totalWorkoutSamples = 0
                        self.emitWorkoutState()
                    }
                }
            }
        } catch {
            logger.error("startWorkout failed: \(error.localizedDescription)")
        }
    }

    func endWorkout() {
        guard workoutState == .running || workoutState == .paused else { return }
        let endDate = Date()
        workoutSession?.end()
        // Capture builder locally so the Sendable completion closures don't
        // have to reach back through the MainActor-isolated `self` to access
        // `self.workoutBuilder` (Swift 6 strict concurrency warning).
        let builder = workoutBuilder
        builder?.endCollection(withEnd: endDate) { _, _ in
            builder?.finishWorkout { [weak self] _, _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.workoutState = .ended
                    self.workoutEndedAt = endDate
                    self.emitWorkoutState()
                    // Reset to idle on the next tick so the UI can show the
                    // post-workout summary briefly before the start button returns.
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        await MainActor.run {
                            self.workoutState = .idle
                            self.workoutSession = nil
                            self.workoutBuilder = nil
                            self.emitWorkoutState()
                        }
                    }
                }
            }
        }
    }

    // MARK: Sample processing

    private func process(samples: [HKSample]?) {
        guard let qSamples = samples as? [HKQuantitySample], !qSamples.isEmpty else { return }
        let unit = HKUnit.count().unitDivided(by: .minute())
        for s in qSamples {
            let bpm = s.quantity.doubleValue(for: unit)
            let payload = WatchHRSamplePayload(
                bpm: bpm,
                timestamp: s.endDate,
                source: deviceName(for: s),
                withinWorkout: workoutState == .running
            )
            ingest(payload)
        }
    }

    /// Internal entry point so the live workout builder can also push samples.
    func ingest(_ payload: WatchHRSamplePayload) {
        currentBPM = payload.bpm
        lastSampleAt = payload.timestamp

        // Maintain rolling 5-min window.
        let cutoff = Date().addingTimeInterval(-sparkWindow)
        recentSamples.append(payload)
        recentSamples = recentSamples.filter { $0.timestamp >= cutoff }

        if payload.withinWorkout { totalWorkoutSamples += 1 }

        onSample?(payload)
    }

    private func emitWorkoutState() {
        let payload = WatchWorkoutStatePayload(
            state: workoutState,
            startedAt: workoutStartedAt,
            endedAt: workoutEndedAt,
            totalSamples: totalWorkoutSamples
        )
        onWorkoutStateChange?(payload)
    }

    private func deviceName(for sample: HKQuantitySample) -> String {
        if let name = sample.device?.name { return name }
        if let model = sample.device?.model { return model }
        let src = sample.sourceRevision.source.name
        return src.isEmpty ? "Apple Watch" : src
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WatchHealthManager: HKWorkoutSessionDelegate {

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            switch toState {
            case .running:
                self.workoutState = .running
            case .paused:
                self.workoutState = .paused
            case .ended:
                self.workoutState = .ended
            default:
                break
            }
            self.emitWorkoutState()
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.logger.error("HKWorkoutSession error: \(error.localizedDescription)")
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WatchHealthManager: HKLiveWorkoutBuilderDelegate {

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // No-op: events surface as part of `didCollectDataOf:` for our HR-centric flow.
    }

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate),
              collectedTypes.contains(hrType),
              let stats = workoutBuilder.statistics(for: hrType) else {
            return
        }
        let unit = HKUnit.count().unitDivided(by: .minute())
        guard let mostRecent = stats.mostRecentQuantity()?.doubleValue(for: unit),
              let when = stats.mostRecentQuantityDateInterval()?.end else {
            return
        }
        Task { @MainActor in
            let payload = WatchHRSamplePayload(
                bpm: mostRecent,
                timestamp: when,
                source: "Apple Watch",
                withinWorkout: true
            )
            self.ingest(payload)
        }
    }
}
