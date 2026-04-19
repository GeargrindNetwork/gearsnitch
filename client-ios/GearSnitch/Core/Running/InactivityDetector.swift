import Foundation
import Combine
import CoreLocation
import CoreMotion
import os

// MARK: - InactivityDetector (Backlog item #18)
//
// Detects when the runner has stopped moving for a configurable window
// (default 60s) so the run can be auto-paused. Apple Fitness does the
// same thing — without it, elapsed time + distance keep accumulating
// while the runner is stopped at a traffic light or tying a shoelace,
// which poisons the pace average.
//
// Three independent signals — ANY one of them firing means "stopped":
//   1. GPS speed        — `CLLocation.speed < minSpeedMPS` sustained
//                         for `inactivitySeconds`.
//   2. Accelerometer    — user-acceleration magnitude stays below
//                         `minAccelG` g for `inactivitySeconds`.
//   3. GPS cluster      — the most-recent three location fixes all sit
//                         within `clusterRadiusMeters` of each other.
//
// The detector is a state machine with two terminal states: `.active`
// and `.paused`. Transitions are driven by time + samples; the caller
// (RunTrackingManager) subscribes to `$state` and pauses / resumes the
// run accordingly.
//
// Testability:
//   - `start(locationPublisher:motionPublisher:)` is the production
//     wiring used by RunTrackingManager.
//   - `ingest(location:at:)`, `ingest(motion:at:)`, and `tick(now:)`
//     are the low-level inputs used by unit tests. They let us drive
//     the detector deterministically without waiting real seconds.
//   - Time is always injected via an explicit `Date` parameter —
//     the detector never calls `Date()` on its own when an override
//     is available, so tests can fast-forward.

@MainActor
final class InactivityDetector: ObservableObject {

    // MARK: - Types

    enum State: Equatable {
        case active
        case paused
    }

    // MARK: - Configurable thresholds

    /// How long the "low motion" condition must hold before we flip to
    /// `.paused`. Matches Apple Fitness (~60s).
    var inactivitySeconds: TimeInterval = 60

    /// Speed below which a GPS fix counts as "not moving". 0.5 m/s is
    /// roughly 1.8 km/h — well below a casual walk.
    var minSpeedMPS: Double = 0.5

    /// User-acceleration magnitude threshold in g. Below this the phone
    /// is effectively stationary (in a pocket on a bench, etc).
    var minAccelG: Double = 0.05

    /// Radius for the GPS-cluster signal. If the last three location
    /// fixes are all within this radius, we treat them as a cluster
    /// (no meaningful movement).
    var clusterRadiusMeters: Double = 10

    /// Number of recent GPS fixes we keep to evaluate the cluster
    /// signal. Three is the minimum that still rejects a lone noisy
    /// outlier.
    var clusterWindowSize: Int = 3

    // MARK: - Resume override

    /// When the user force-resumes via the banner we suppress the
    /// detector for this many seconds so it doesn't immediately
    /// re-pause them. The banner sets this via `suppressUntil(_:)`.
    var forceResumeSuppressionSeconds: TimeInterval = 30

    // MARK: - Published state

    @Published private(set) var state: State = .active

    // MARK: - Private

    /// When the user is enabled = false we ignore all samples.
    /// RunTrackingManager toggles this from the settings switch.
    private(set) var isEnabled: Bool = true

    /// First timestamp at which we saw a "low motion" signal in the
    /// current run. Reset to nil whenever we see motion. When this is
    /// non-nil AND `now - lowMotionSince >= inactivitySeconds` we flip
    /// to `.paused`.
    private var lowMotionSince: Date?

    /// Timestamp until which force-resume suppresses pausing.
    private var suppressPauseUntil: Date?

    private var recentLocations: [CLLocation] = []

    private var locationSub: AnyCancellable?
    private var motionSub: AnyCancellable?

    private let logger = Logger(subsystem: "com.gearsnitch", category: "InactivityDetector")

    // MARK: - Lifecycle

    init() {}

    /// Subscribe to live location + motion publishers. Both are optional
    /// — a caller that can only provide one can pass `Empty()` for the
    /// other and the detector will still work via the remaining signal.
    func start(
        locationPublisher: AnyPublisher<CLLocation, Never>,
        motionPublisher: AnyPublisher<CMDeviceMotion, Never>
    ) {
        stop()
        reset()

        locationSub = locationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] location in
                self?.ingest(location: location)
            }

        motionSub = motionPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] motion in
                self?.ingest(motion: motion)
            }
    }

    func stop() {
        locationSub?.cancel()
        motionSub?.cancel()
        locationSub = nil
        motionSub = nil
    }

    /// Reset all accumulated state to `.active` with no samples. Called
    /// when a new run starts or the feature is toggled.
    func reset() {
        state = .active
        lowMotionSince = nil
        suppressPauseUntil = nil
        recentLocations.removeAll(keepingCapacity: true)
    }

    /// Toggle the whole detector. When `false` the state is forced to
    /// `.active` and no incoming samples will change it.
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled {
            reset()
        }
    }

    /// User tapped the banner / manual resume. Transitions to `.active`
    /// immediately and suppresses re-pause for
    /// `forceResumeSuppressionSeconds`.
    func forceResume(now: Date = Date()) {
        state = .active
        lowMotionSince = nil
        suppressPauseUntil = now.addingTimeInterval(forceResumeSuppressionSeconds)
    }

    // MARK: - Inputs (test-facing)

    /// Feed one GPS fix. `now` defaults to the fix's own timestamp so
    /// tests can drive the clock through the fix stream alone.
    func ingest(location: CLLocation, at now: Date? = nil) {
        guard isEnabled else { return }
        let now = now ?? location.timestamp

        recentLocations.append(location)
        if recentLocations.count > clusterWindowSize {
            recentLocations.removeFirst(recentLocations.count - clusterWindowSize)
        }

        let slowSpeed = location.speed >= 0 && location.speed < minSpeedMPS
        let clustered = isClustered(within: clusterRadiusMeters)

        if slowSpeed || clustered {
            markLowMotion(at: now)
        } else {
            clearLowMotion()
        }

        evaluate(at: now)
    }

    /// Feed one motion sample. `now` defaults to `Date()` because
    /// `CMDeviceMotion.timestamp` is a monotonic device-uptime value,
    /// not a wall-clock Date.
    func ingest(motion: CMDeviceMotion, at now: Date = Date()) {
        let a = motion.userAcceleration
        ingest(accelerationMagnitudeG: sqrt(a.x * a.x + a.y * a.y + a.z * a.z), at: now)
    }

    /// Lower-level motion input: the magnitude of user acceleration
    /// in g. Used by `ingest(motion:at:)` on the hot path and by unit
    /// tests (which can't easily instantiate a `CMDeviceMotion`).
    func ingest(accelerationMagnitudeG magnitude: Double, at now: Date = Date()) {
        guard isEnabled else { return }

        if magnitude < minAccelG {
            markLowMotion(at: now)
        } else {
            clearLowMotion()
        }

        evaluate(at: now)
    }

    /// Wall-clock tick. Call this whenever you want the detector to
    /// re-evaluate without supplying a fresh sample (e.g. a 1Hz timer
    /// keeps the transition responsive even during a dead zone).
    func tick(now: Date = Date()) {
        guard isEnabled else { return }
        evaluate(at: now)
    }

    // MARK: - Core

    private func markLowMotion(at now: Date) {
        if lowMotionSince == nil {
            lowMotionSince = now
        }
    }

    private func clearLowMotion() {
        lowMotionSince = nil
        // Any real motion immediately invalidates the pause.
        if state == .paused {
            state = .active
        }
    }

    private func evaluate(at now: Date) {
        // Suppression window from a manual resume — skip entirely.
        if let until = suppressPauseUntil, now < until {
            return
        }
        suppressPauseUntil = nil

        guard let since = lowMotionSince else {
            if state == .paused { state = .active }
            return
        }

        if now.timeIntervalSince(since) >= inactivitySeconds {
            if state != .paused {
                state = .paused
                logger.info("Inactivity detector flipped to paused after \(self.inactivitySeconds)s of low motion.")
            }
        }
    }

    private func isClustered(within radius: Double) -> Bool {
        guard recentLocations.count >= clusterWindowSize, let first = recentLocations.first else {
            return false
        }
        for other in recentLocations.dropFirst() {
            if other.distance(from: first) > radius {
                return false
            }
        }
        return true
    }
}
