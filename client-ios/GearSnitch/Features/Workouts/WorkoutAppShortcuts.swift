import AppIntents
import Foundation

// MARK: - Workout Shortcuts Provider
//
// Surfaces the four workout App Intents (start / pause / resume / end) for
// discovery in the Shortcuts app, Siri, and Spotlight. iOS allows exactly one
// `AppShortcutsProvider` per target — this is the main-app target's provider.
// (The widget extension ships its own provider for gym-session shortcuts.)
//
// Invocation phrases follow the `\(.applicationName)` pattern Apple requires.

public struct WorkoutShortcutsProvider: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartWorkoutIntent(),
            phrases: [
                "Start a workout with \(.applicationName)",
                "Start my workout with \(.applicationName)",
                "Start \(\.$activityType) workout with \(.applicationName)",
            ],
            shortTitle: "Start Workout",
            systemImageName: "figure.run"
        )
        AppShortcut(
            intent: PauseWorkoutIntent(),
            phrases: [
                "Pause my \(.applicationName) workout",
                "Pause workout in \(.applicationName)",
            ],
            shortTitle: "Pause Workout",
            systemImageName: "pause.circle.fill"
        )
        AppShortcut(
            intent: ResumeWorkoutIntent(),
            phrases: [
                "Resume my \(.applicationName) workout",
                "Resume workout in \(.applicationName)",
            ],
            shortTitle: "Resume Workout",
            systemImageName: "play.circle.fill"
        )
        AppShortcut(
            intent: EndWorkoutIntent(),
            phrases: [
                "End my \(.applicationName) workout",
                "Finish my \(.applicationName) workout",
                "Stop workout in \(.applicationName)",
            ],
            shortTitle: "End Workout",
            systemImageName: "stop.circle.fill"
        )
    }
}
