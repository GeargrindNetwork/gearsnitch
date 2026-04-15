import Foundation
import WidgetKit

enum PendingSessionActionKind: String {
    case startSession
    case endSession
    case disarmProtection
}

struct PendingSessionAction {
    let kind: PendingSessionActionKind
    let gymId: String
    let gymName: String
}

@MainActor
final class WidgetSyncStore {
    static let shared = WidgetSyncStore()

    static let appGroupId = "group.com.gearsnitch.app"

    private enum Key {
        static let activeSession = "activeGymSession"
        static let connectedDeviceCount = "connectedDeviceCount"
        static let totalDeviceCount = "totalDeviceCount"
        static let dailyCalories = "dailyCalories"
        static let calorieGoal = "dailyCalorieGoal"
        static let lastGymId = "lastGymId"
        static let lastGymName = "lastGymName"
        static let pendingSessionAction = "pendingSessionAction"
    }

    private init() {}

    private var defaults: UserDefaults? {
        UserDefaults(suiteName: Self.appGroupId)
    }

    func restoredSession() -> GymSession? {
        guard let defaults,
              let data = defaults.data(forKey: Key.activeSession) else {
            return nil
        }

        return try? JSONDecoder().decode(GymSession.self, from: data)
    }

    func storeSession(_ session: GymSession) {
        guard let defaults,
              let data = try? JSONEncoder().encode(session) else {
            return
        }

        defaults.set(data, forKey: Key.activeSession)
        storeLastGym(id: session.gymId, name: session.gymName)
        reloadWidgets()
    }

    func clearSession() {
        defaults?.removeObject(forKey: Key.activeSession)
        reloadWidgets()
    }

    func storeLastGym(id: String, name: String) {
        defaults?.set(id, forKey: Key.lastGymId)
        defaults?.set(name, forKey: Key.lastGymName)
    }

    func storeDeviceSnapshot(connectedCount: Int, totalCount: Int) {
        defaults?.set(connectedCount, forKey: Key.connectedDeviceCount)
        defaults?.set(totalCount, forKey: Key.totalDeviceCount)
        reloadWidgets()
    }

    func storeCalories(consumed: Double, goal: Double) {
        defaults?.set(consumed, forKey: Key.dailyCalories)
        defaults?.set(goal, forKey: Key.calorieGoal)
        reloadWidgets()
    }

    func consumePendingSessionAction() -> PendingSessionAction? {
        guard let defaults,
              let payload = defaults.dictionary(forKey: Key.pendingSessionAction),
              let rawKind = payload["pendingAction"] as? String,
              let kind = PendingSessionActionKind(rawValue: rawKind) else {
            return nil
        }

        defaults.removeObject(forKey: Key.pendingSessionAction)

        return PendingSessionAction(
            kind: kind,
            gymId: payload["gymId"] as? String ?? "",
            gymName: payload["gymName"] as? String ?? "Gym"
        )
    }

    private func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
