import Foundation
import Combine

// MARK: - RestTimerState (Backlog item #16)
//
// Sub-view-model that owns the countdown for the between-sets rest
// timer. Pure state + timer driver so it can be unit-tested without
// a view hierarchy. The overlay view binds to this via `@Published`.
//
// Design notes:
//  - Tick driver is injectable via `scheduleTimer` so tests can drive
//    the clock manually (`tick()`) without waiting real seconds.
//  - `complete()` is idempotent — the last tick and a manual skip both
//    call it, and we must never fire `onComplete` twice.
//  - Nudge (`+30s`, `-15s`) is clamped to `RestTimerPreferences.validRange`
//    and will not complete the timer via a negative nudge (it floors at 1s).

@MainActor
final class RestTimerState: ObservableObject {

    enum Phase: Equatable {
        case running
        case paused
        case complete
    }

    // MARK: - Published

    @Published private(set) var totalSeconds: Int
    @Published private(set) var remainingSeconds: Int
    @Published private(set) var phase: Phase

    // MARK: - Callbacks

    /// Fired exactly once when the timer hits 0 OR when `skip()` is
    /// called. Re-entrancy / double-fire is guarded by `didFireComplete`.
    var onComplete: ((_ completedNaturally: Bool) -> Void)?

    /// Fired when the timer crosses from 6s → 5s remaining. Used by
    /// the overlay to trigger the pre-warn haptic.
    var onWarning: (() -> Void)?

    // MARK: - Private

    private var didFireComplete = false
    private var timerTask: Timer?
    private let tickInterval: TimeInterval

    // MARK: - Init

    init(duration: Int, tickInterval: TimeInterval = 1.0) {
        let clamped = RestTimerPreferences.clamp(duration)
        self.totalSeconds = clamped
        self.remainingSeconds = clamped
        self.phase = .running
        self.tickInterval = tickInterval
    }

    deinit {
        timerTask?.invalidate()
    }

    // MARK: - Lifecycle

    /// Start the real-time tick driver. Unit tests drive `tick()` directly
    /// and do NOT call this (to avoid flaky 1-second waits).
    func start() {
        guard phase != .complete else { return }
        phase = .running
        scheduleTimer()
    }

    /// Reset to a new duration (called from overlay when the user picks
    /// a preset mid-countdown). No-op if the timer has already completed —
    /// the overlay is expected to be dismissed in that case.
    func setDuration(_ seconds: Int) {
        guard phase != .complete else { return }
        let clamped = RestTimerPreferences.clamp(seconds)
        totalSeconds = clamped
        remainingSeconds = clamped
        phase = .running
        didFireComplete = false
        scheduleTimer()
    }

    func pause() {
        guard phase == .running else { return }
        phase = .paused
        timerTask?.invalidate()
        timerTask = nil
    }

    func resume() {
        guard phase == .paused else { return }
        phase = .running
        scheduleTimer()
    }

    /// Skip: fire completion with `completedNaturally = false`.
    func skip() {
        guard phase != .complete else { return }
        remainingSeconds = 0
        complete(naturally: false)
    }

    /// Nudge the countdown by `delta` seconds (positive = add time,
    /// negative = subtract). Clamped so we never overflow the valid
    /// range and never drop below 1s (nudging does not complete the
    /// timer; only ticking to 0 or tapping Skip does).
    func nudge(by delta: Int) {
        guard phase != .complete else { return }
        let proposed = remainingSeconds + delta
        let clampedFloor = max(1, proposed)
        // Cap at total + delta so the ring doesn't visually overflow:
        // totalSeconds grows with the nudge so the ring stays valid.
        if proposed > totalSeconds {
            totalSeconds = proposed
        }
        remainingSeconds = min(clampedFloor, RestTimerPreferences.validRange.upperBound + totalSeconds)
        remainingSeconds = max(1, remainingSeconds)
    }

    // MARK: - Tick (public so tests can drive manually)

    /// Advance by one tick. Called by the scheduled timer OR directly
    /// by unit tests.
    func tick() {
        guard phase == .running else { return }
        guard remainingSeconds > 0 else {
            complete(naturally: true)
            return
        }

        let next = remainingSeconds - 1
        if remainingSeconds == 6 && next == 5 {
            onWarning?()
        }
        remainingSeconds = next
        if remainingSeconds == 0 {
            complete(naturally: true)
        }
    }

    // MARK: - Derived

    /// Progress 0...1 for the ring. Fills clockwise as time elapses.
    var progress: Double {
        guard totalSeconds > 0 else { return 1.0 }
        return 1.0 - (Double(remainingSeconds) / Double(totalSeconds))
    }

    // MARK: - Private

    private func scheduleTimer() {
        timerTask?.invalidate()
        timerTask = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    private func complete(naturally: Bool) {
        guard !didFireComplete else { return }
        didFireComplete = true
        phase = .complete
        timerTask?.invalidate()
        timerTask = nil
        onComplete?(naturally)
    }
}
