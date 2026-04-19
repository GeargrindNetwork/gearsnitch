import Foundation
import HealthKit

// MARK: - WorkoutCoordinator
//
// Thin singleton that sits between the App Intents framework (Siri / Shortcuts /
// Lock Screen widgets / Action Button) and the app's existing workout entry
// points. Today it writes a pending-action payload to the shared App Group so
// the foreground app picks it up and starts / pauses / resumes / ends a
// workout via `ActiveWorkoutViewModel`.
//
// This is the seam that backlog item #10 (iPhone-native HKWorkoutSession) will
// plug into when it lands — its agent should update the method bodies to route
// through the native session while keeping the public API stable.
//
// Intentionally isolated from `ActiveWorkoutViewModel` so that App Intents
// (which can run out-of-process or without the UI instantiated) don't require
// view-model state.

public let workoutCoordinatorAppGroupId = "group.com.gearsnitch.app"

public enum WorkoutCoordinatorKey {
    public static let pendingAction = "pendingWorkoutAction"
    public static let action = "action"
    public static let activityTypeRawValue = "activityTypeRawValue"
    public static let requestedAt = "requestedAt"
}

public enum WorkoutCoordinatorAction: String {
    case start
    case pause
    case resume
    case end
}

public enum WorkoutCoordinatorError: Error, LocalizedError {
    case appGroupUnavailable

    public var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return "Shared app group is not available; workout action could not be queued."
        }
    }
}

@MainActor
public final class WorkoutCoordinator {
    public static let shared = WorkoutCoordinator()

    private let defaults: UserDefaults?

    // Default init reads from the real app-group defaults.
    public init(defaults: UserDefaults? = UserDefaults(suiteName: workoutCoordinatorAppGroupId)) {
        self.defaults = defaults
    }

    // MARK: - Public API (called by App Intents)

    public func start(activityType: HKWorkoutActivityType) async throws {
        try write(
            action: .start,
            extras: [WorkoutCoordinatorKey.activityTypeRawValue: activityType.rawValue]
        )
    }

    public func pause() async throws {
        try write(action: .pause)
    }

    public func resume() async throws {
        try write(action: .resume)
    }

    public func end() async throws {
        try write(action: .end)
    }

    // MARK: - Pending-action inbox (read side)
    //
    // The foreground app should call `dequeuePendingAction()` on launch /
    // activation to see if an App Intent fired while the app was suspended.
    // The existing `ActiveWorkoutViewModel` or its #10 successor will wire
    // this up; writing is the only thing this coordinator is responsible for
    // today.

    public struct PendingAction: Equatable {
        public let action: WorkoutCoordinatorAction
        public let activityType: HKWorkoutActivityType?
        public let requestedAt: Date
    }

    public func dequeuePendingAction() -> PendingAction? {
        guard let defaults,
              let payload = defaults.dictionary(forKey: WorkoutCoordinatorKey.pendingAction),
              let raw = payload[WorkoutCoordinatorKey.action] as? String,
              let action = WorkoutCoordinatorAction(rawValue: raw) else {
            return nil
        }

        let requestedAt: Date
        if let timestamp = payload[WorkoutCoordinatorKey.requestedAt] as? TimeInterval {
            requestedAt = Date(timeIntervalSince1970: timestamp)
        } else {
            requestedAt = Date()
        }

        var activityType: HKWorkoutActivityType?
        if let raw = payload[WorkoutCoordinatorKey.activityTypeRawValue] as? UInt {
            activityType = HKWorkoutActivityType(rawValue: raw)
        }

        defaults.removeObject(forKey: WorkoutCoordinatorKey.pendingAction)

        return PendingAction(
            action: action,
            activityType: activityType,
            requestedAt: requestedAt
        )
    }

    // MARK: - Private

    private func write(
        action: WorkoutCoordinatorAction,
        extras: [String: Any] = [:]
    ) throws {
        guard let defaults else {
            throw WorkoutCoordinatorError.appGroupUnavailable
        }

        var payload: [String: Any] = [
            WorkoutCoordinatorKey.action: action.rawValue,
            WorkoutCoordinatorKey.requestedAt: Date().timeIntervalSince1970,
        ]
        for (key, value) in extras {
            payload[key] = value
        }

        defaults.set(payload, forKey: WorkoutCoordinatorKey.pendingAction)
    }
}
