import Foundation
import StoreKit
import UIKit
import os

// MARK: - ReviewPromptController (Backlog item #26)
//
// Drives the App Store review prompt via `SKStoreReviewController`. Apple
// throttles to 3 prompts per user per 365 days automatically, but we
// layer additional rules on top so we don't burn a prompt slot on a
// disengaged user:
//
//   - Minimum 14 days since first install (Apple rec: don't prompt too
//     early — the user hasn't earned the "would recommend" mental bar
//     yet).
//   - Minimum 30 days since the last prompt (stacks conservatively on
//     top of Apple's 365d cap).
//   - Trigger when ANY of:
//       * 3+ completed workouts
//       * 5+ successful BLE gear pairs
//       * 7+ app sessions (foreground transitions, 10-min debounce)
//
// All state lives in `UserDefaults` under the `reviewPrompt.*` keys. We
// never reset the counters — they monotonically increase across the
// app's lifetime. The `lastPromptedAt` date is what gates re-prompting.
//
// Testability: the `SKStoreReviewController.requestReview(in:)` call is
// wrapped by a `ReviewPromptPresenter` protocol so tests can inject a
// no-op / recording presenter and verify the trigger logic without a
// real `UIWindowScene`.

// MARK: - UserDefaults Keys

public enum ReviewPromptKey {
    public static let completedWorkouts = "reviewPrompt.completedWorkouts"
    public static let pairedDevices = "reviewPrompt.pairedDevices"
    public static let appSessions = "reviewPrompt.appSessions"
    public static let lastPromptedAt = "reviewPrompt.lastPromptedAt"
    public static let installedAt = "reviewPrompt.installedAt"
    public static let lastSessionAt = "reviewPrompt.lastSessionAt"
}

// MARK: - Thresholds

/// Externally readable so the agent-return contract + the unit tests
/// reference the same numbers.
public struct ReviewPromptThresholds {
    public static let minWorkouts = 3
    public static let minPairedDevices = 5
    public static let minAppSessions = 7
    public static let minDaysSinceInstall = 14
    public static let minDaysSinceLastPrompt = 30
    /// App-session debounce so rapid foreground/background toggles don't
    /// count as independent sessions. 10 minutes matches the behavior
    /// most analytics SDKs use for "new session".
    public static let sessionDebounceSeconds: TimeInterval = 600
}

// MARK: - Presenter Seam (for tests)

@MainActor
public protocol ReviewPromptPresenter {
    func requestReview()
}

/// Production presenter — looks up the first foreground-active
/// `UIWindowScene` and calls `SKStoreReviewController.requestReview(in:)`.
@MainActor
public struct SystemReviewPromptPresenter: ReviewPromptPresenter {
    public init() {}
    public func requestReview() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first
        else {
            return
        }
        SKStoreReviewController.requestReview(in: scene)
    }
}

// MARK: - Controller

@MainActor
public final class ReviewPromptController {

    public static let shared = ReviewPromptController()

    private let defaults: UserDefaults
    private let presenter: ReviewPromptPresenter
    private let now: () -> Date
    private let logger = Logger(subsystem: "com.gearsnitch", category: "ReviewPrompt")

    /// Designated init — exposed for tests (inject a suite-backed
    /// `UserDefaults`, a recording presenter, and a frozen `now` clock).
    /// `presenter` is optional so the default value doesn't reference
    /// the `@MainActor`-isolated `SystemReviewPromptPresenter.init()` —
    /// the shim is constructed inside the init body (which is itself
    /// main-actor-isolated via the class annotation).
    public init(
        defaults: UserDefaults = .standard,
        presenter: ReviewPromptPresenter? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.presenter = presenter ?? SystemReviewPromptPresenter()
        self.now = now
        stampInstallDateIfNeeded()
    }

    // MARK: - Event recorders (public API)

    /// Increment completed-workout counter. Call from
    /// `ActiveWorkoutViewModel.endWorkout()` after a successful save.
    public func recordWorkoutCompleted() {
        increment(key: ReviewPromptKey.completedWorkouts)
    }

    /// Increment paired-device counter. Call from
    /// `BLEManager.centralManager(_:didConnect:)` on a successful connect
    /// to a persisted device.
    public func recordDevicePaired() {
        increment(key: ReviewPromptKey.pairedDevices)
    }

    /// Increment app-session counter, debounced by
    /// `sessionDebounceSeconds`. Call from the SwiftUI App's
    /// `.onChange(of: scenePhase)` when transitioning to `.active`.
    public func recordAppSessionStart() {
        let currentTime = now()
        if let last = defaults.object(forKey: ReviewPromptKey.lastSessionAt) as? Date,
           currentTime.timeIntervalSince(last) < ReviewPromptThresholds.sessionDebounceSeconds {
            return
        }
        defaults.set(currentTime, forKey: ReviewPromptKey.lastSessionAt)
        increment(key: ReviewPromptKey.appSessions)
    }

    /// Evaluate whether we should ask for a review and, if so, request
    /// it. Safe to call unconditionally after any event recorder — the
    /// gating logic here is the source of truth.
    public func maybeRequestReview() {
        guard shouldPrompt() else { return }
        defaults.set(now(), forKey: ReviewPromptKey.lastPromptedAt)
        logger.info("Requesting App Store review (workouts=\(self.completedWorkouts), pairs=\(self.pairedDevices), sessions=\(self.appSessions))")
        presenter.requestReview()
    }

    // MARK: - Introspection (tests + debug)

    public var completedWorkouts: Int {
        defaults.integer(forKey: ReviewPromptKey.completedWorkouts)
    }

    public var pairedDevices: Int {
        defaults.integer(forKey: ReviewPromptKey.pairedDevices)
    }

    public var appSessions: Int {
        defaults.integer(forKey: ReviewPromptKey.appSessions)
    }

    public var installedAt: Date? {
        defaults.object(forKey: ReviewPromptKey.installedAt) as? Date
    }

    public var lastPromptedAt: Date? {
        defaults.object(forKey: ReviewPromptKey.lastPromptedAt) as? Date
    }

    // MARK: - Gate Logic

    /// Exposed internal for unit tests — returns whether all conditions
    /// are met for a prompt right now.
    func shouldPrompt() -> Bool {
        let currentTime = now()

        // Ensure we have an install stamp. `stampInstallDateIfNeeded()`
        // runs in `init` but double-guard here for cases where the
        // defaults suite was reset between events.
        let install = installedAt ?? {
            defaults.set(currentTime, forKey: ReviewPromptKey.installedAt)
            return currentTime
        }()

        // Rule 1: min days since install.
        let daysSinceInstall = daysBetween(install, currentTime)
        guard daysSinceInstall >= ReviewPromptThresholds.minDaysSinceInstall else {
            return false
        }

        // Rule 2: min days since last prompt.
        if let last = lastPromptedAt {
            let daysSincePrompt = daysBetween(last, currentTime)
            guard daysSincePrompt >= ReviewPromptThresholds.minDaysSinceLastPrompt else {
                return false
            }
        }

        // Rule 3: at least one qualifying event threshold crossed.
        let qualifies =
            completedWorkouts >= ReviewPromptThresholds.minWorkouts
            || pairedDevices >= ReviewPromptThresholds.minPairedDevices
            || appSessions >= ReviewPromptThresholds.minAppSessions
        return qualifies
    }

    // MARK: - Private helpers

    private func increment(key: String) {
        let current = defaults.integer(forKey: key)
        // Guard against corruption / negative — treat <0 as 0.
        let next = max(current, 0) + 1
        defaults.set(next, forKey: key)
    }

    private func stampInstallDateIfNeeded() {
        if defaults.object(forKey: ReviewPromptKey.installedAt) == nil {
            defaults.set(now(), forKey: ReviewPromptKey.installedAt)
        }
    }

    private func daysBetween(_ earlier: Date, _ later: Date) -> Int {
        let seconds = later.timeIntervalSince(earlier)
        guard seconds.isFinite else { return 0 }
        return Int(seconds / 86_400)
    }
}
