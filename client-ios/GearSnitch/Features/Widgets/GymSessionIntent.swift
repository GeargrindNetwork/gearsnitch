import AppIntents
import Foundation

// MARK: - App Group

private let appGroupId = "group.com.gearsnitch.app"
private let sessionKey = "activeGymSession"
private let lastGymIdKey = "lastGymId"
private let lastGymNameKey = "lastGymName"

// MARK: - Start Gym Session Intent

struct StartGymSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Gym Session"
    static var description: IntentDescription = "Starts tracking a gym session."
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: appGroupId)

        // Read the last known gym from shared defaults
        let gymId = defaults?.string(forKey: lastGymIdKey) ?? ""
        let gymName = defaults?.string(forKey: lastGymNameKey) ?? "Gym"

        // Write session state so the app picks it up on foreground
        let sessionData: [String: Any] = [
            "pendingAction": "startSession",
            "gymId": gymId,
            "gymName": gymName,
            "requestedAt": Date().timeIntervalSince1970,
        ]
        defaults?.set(sessionData, forKey: "pendingSessionAction")

        return .result()
    }
}

// MARK: - Stop Gym Session Intent

struct StopGymSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Gym Session"
    static var description: IntentDescription = "Ends the current gym session."
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: appGroupId)

        // Write pending action for the app to process on foreground
        let actionData: [String: Any] = [
            "pendingAction": "endSession",
            "requestedAt": Date().timeIntervalSince1970,
        ]
        defaults?.set(actionData, forKey: "pendingSessionAction")

        return .result()
    }
}

// MARK: - App Intent Shortcuts Provider

struct GearSnitchShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartGymSessionIntent(),
            phrases: [
                "Start a gym session in \(.applicationName)",
                "Start tracking my workout in \(.applicationName)",
            ],
            shortTitle: "Start Session",
            systemImageName: "figure.strengthtraining.traditional"
        )
        AppShortcut(
            intent: StopGymSessionIntent(),
            phrases: [
                "Stop my gym session in \(.applicationName)",
                "End my workout in \(.applicationName)",
            ],
            shortTitle: "End Session",
            systemImageName: "stop.circle.fill"
        )
    }
}
