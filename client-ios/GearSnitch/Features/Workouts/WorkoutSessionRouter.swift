import Foundation
import HealthKit

// MARK: - Workout Source

/// Which transport is tracking the active workout. Exposed to the UI so users
/// see a small "Powered by:" tag telling them where their HR/duration data is
/// coming from (Apple Watch / iPhone HealthKit / timer-only).
enum WorkoutSource: String {
    /// Paired Apple Watch running the full `HKWorkoutSession` on-wrist.
    /// This is the PRIMARY path — it takes priority over the iPhone-native
    /// path whenever a paired Watch is reachable.
    case watch

    /// iOS 26+ iPhone-native `HKWorkoutSession` via `IPhoneWorkoutSession`.
    /// Fallback for non-Watch users (or users whose Watch is unreachable and
    /// who have granted HealthKit auth).
    case iPhoneHealthKit

    /// Legacy wall-clock timer. No HR or distance sourcing — just elapsed
    /// time and manual set/rep entry. Final fallback when neither the Watch
    /// nor HealthKit is available.
    case timerOnly

    var displayName: String {
        switch self {
        case .watch: return "Apple Watch"
        case .iPhoneHealthKit: return "iPhone HealthKit"
        case .timerOnly: return "Timer"
        }
    }

    var displayTag: String {
        "Powered by: \(displayName)"
    }
}

// MARK: - Router Inputs (test-injectable)

/// Narrow shim over `WatchSyncManager` reachability state. Tests inject a
/// fake so the routing branch can be exercised without a real WCSession.
///
/// `@MainActor`-isolated to match `WatchSyncManager` (the concrete conformer),
/// so the conformance doesn't cross actor boundaries under Swift 6.
@MainActor
protocol WatchReachabilityProviding: AnyObject {
    var isWatchPaired: Bool { get }
    var isWatchReachable: Bool { get }
}

extension WatchSyncManager: WatchReachabilityProviding {}

/// Narrow shim over `HKHealthStore` so routing tests don't require a real
/// HealthKit auth prompt. Only the bits the router needs.
protocol HealthKitAuthProviding {
    static var isHealthDataAvailableOnDevice: Bool { get }
    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus
}

extension HKHealthStore: HealthKitAuthProviding {
    static var isHealthDataAvailableOnDevice: Bool {
        HKHealthStore.isHealthDataAvailable()
    }
}

// MARK: - Router

/// Decides which workout transport to use when the user taps "Start Workout".
///
/// Decision order — highest priority first:
///
/// 1. **Watch path (PRIMARY).** If the app sees a paired Watch that is
///    currently reachable, return `.watch`. The existing `WatchSyncManager`
///    flow handles start/stop on the Watch side.
/// 2. **iPhone-native HealthKit.** On iOS 26+, if HealthKit is available and
///    the user has authorized the workout type for sharing (which is how you
///    tell whether `HKWorkoutSession` on iPhone will be allowed to persist),
///    return `.iPhoneHealthKit`. We'll construct an `IPhoneWorkoutSession`.
/// 3. **Timer-only.** Everything else — old OS, no HealthKit, denied auth.
///    The session is wall-clock only; no HR or distance sourcing.
///
/// Watch and iPhone never run simultaneously for the same workout: the router
/// returns a single source and the caller is expected to honor it.
@MainActor
enum WorkoutSessionRouter {

    /// Resolve the routing decision. Pure function of the provided inputs —
    /// easy to unit test by injecting fakes.
    ///
    /// - Parameters:
    ///   - watch: Reachability view over `WatchSyncManager`.
    ///   - health: Auth view over `HKHealthStore`.
    ///   - healthStoreType: Static surface for `isHealthDataAvailable`. Swap
    ///     in tests to force the value.
    ///   - isIOS26OrLater: The router does not call `#available` itself so
    ///     tests can pin the OS gate either way.
    static func resolve(
        watch: WatchReachabilityProviding,
        health: HealthKitAuthProviding,
        healthStoreType: HealthKitAuthProviding.Type = HKHealthStore.self,
        isIOS26OrLater: Bool = {
            if #available(iOS 26.0, *) { return true } else { return false }
        }()
    ) -> WorkoutSource {
        // 1. Watch primacy — paired AND currently reachable.
        if watch.isWatchPaired && watch.isWatchReachable {
            return .watch
        }

        // 2. iPhone-native HealthKit — iOS 26+ and HK workout auth granted.
        if isIOS26OrLater,
           healthStoreType.isHealthDataAvailableOnDevice,
           health.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized {
            return .iPhoneHealthKit
        }

        // 3. Fallback.
        return .timerOnly
    }
}
