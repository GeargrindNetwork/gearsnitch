import HealthKit
import UIKit
import os

private let sceneDelegateLogger = Logger(subsystem: "com.gearsnitch", category: "SceneDelegate")

/// Scene delegate used primarily as the hook for HealthKit workout crash
/// recovery (backlog item #10). iOS 26 introduces
/// `HKHealthStore.recoverActiveWorkoutSession(completion:)` which hands back
/// an in-flight `HKWorkoutSession` if the app crashed mid-workout. We call it
/// here, construct an `IPhoneWorkoutSession` around the recovered session,
/// and post a notification so `ActiveWorkoutViewModel` can rebind its state.
///
/// This delegate is intentionally lightweight — the SwiftUI `App` lifecycle
/// still owns UI. We live alongside `@UIApplicationDelegateAdaptor` purely
/// because the HealthKit recovery API is scene-scoped.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {

    /// Notification posted after a recovered session has been wrapped in
    /// `IPhoneWorkoutSession`. The payload's `.object` is the session itself.
    /// `ActiveWorkoutViewModel` listens for this to call `attachRecovered(_:)`.
    @available(iOS 26.0, *)
    static let recoveredWorkoutNotification = Notification.Name("com.gearsnitch.workout.recovered")

    /// Global store holding the most recent recovered session so any view or
    /// viewmodel that instantiates after the notification fires can still
    /// pick it up. Cleared once the viewmodel takes ownership.
    static let recoveredSessionStore = RecoveredWorkoutStore()

    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        // iOS-26-only: `HKHealthStore.recoverActiveWorkoutSession(completion:)`
        // ships with the iOS 26 SDK. Xcode 16.4 (CI runner) has the iOS 18 SDK
        // and marks that API unavailable, so we gate the call site at compile
        // time. Mirrors the gate in `iPhoneWorkoutSession.swift`.
        #if compiler(>=6.2) && os(iOS)
        if #available(iOS 26.0, *) {
            recoverActiveWorkoutSessionIfNeeded()
        }
        #endif
    }

    #if compiler(>=6.2) && os(iOS)
    @available(iOS 26.0, *)
    private func recoverActiveWorkoutSessionIfNeeded() {
        let healthStore = HKHealthStore()
        guard HKHealthStore.isHealthDataAvailable() else { return }

        healthStore.recoverActiveWorkoutSession { workoutSession, error in
            if let error {
                sceneDelegateLogger.error(
                    "recoverActiveWorkoutSession failed: \(error.localizedDescription)"
                )
                return
            }
            guard let workoutSession else {
                sceneDelegateLogger.info("No active workout to recover")
                return
            }

            Task { @MainActor in
                let wrapper = IPhoneWorkoutSession(
                    recovered: workoutSession,
                    healthStore: healthStore
                )
                Self.recoveredSessionStore.store(wrapper)
                NotificationCenter.default.post(
                    name: SceneDelegate.recoveredWorkoutNotification,
                    object: wrapper
                )
                sceneDelegateLogger.info(
                    "Recovered active workout session (activity=\(workoutSession.workoutConfiguration.activityType.rawValue))"
                )
            }
        }
    }
    #endif
}

/// Thread-safe box for the most recent recovered `IPhoneWorkoutSession`. The
/// `ActiveWorkoutViewModel` may be constructed after the notification has
/// already fired (e.g. because its owning SwiftUI view hasn't rendered yet),
/// so we also stash the session here and the viewmodel's `init` pulls it out
/// via `consume()` on appear.
final class RecoveredWorkoutStore {

    private let lock = NSLock()
    private var stored: AnyObject?

    func store(_ session: AnyObject) {
        lock.lock()
        defer { lock.unlock() }
        stored = session
    }

    /// Atomically remove and return the stored session (if any).
    func consume() -> AnyObject? {
        lock.lock()
        defer { lock.unlock() }
        let value = stored
        stored = nil
        return value
    }

    /// Non-consuming peek, for tests.
    var hasPendingSession: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stored != nil
    }
}
