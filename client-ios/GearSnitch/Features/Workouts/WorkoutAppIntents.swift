import AppIntents
import Foundation
import HealthKit

// MARK: - Activity Type Enum
//
// A small, user-facing enum surfaced through `@Parameter` so Siri / Shortcuts
// can prompt the user. Each case maps to a common `HKWorkoutActivityType`.

public enum WorkoutIntentActivityType: String, AppEnum, CaseIterable {
    case running
    case cycling
    case walking
    case hiking
    case strength

    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Workout Activity")
    }

    public static var caseDisplayRepresentations: [WorkoutIntentActivityType: DisplayRepresentation] = [
        .running: DisplayRepresentation(title: "Running"),
        .cycling: DisplayRepresentation(title: "Cycling"),
        .walking: DisplayRepresentation(title: "Walking"),
        .hiking: DisplayRepresentation(title: "Hiking"),
        .strength: DisplayRepresentation(title: "Strength Training"),
    ]

    public var healthKitType: HKWorkoutActivityType {
        switch self {
        case .running: return .running
        case .cycling: return .cycling
        case .walking: return .walking
        case .hiking: return .hiking
        case .strength: return .traditionalStrengthTraining
        }
    }

    public init?(healthKitType: HKWorkoutActivityType) {
        switch healthKitType {
        case .running: self = .running
        case .cycling: self = .cycling
        case .walking: self = .walking
        case .hiking: self = .hiking
        case .traditionalStrengthTraining, .functionalStrengthTraining:
            self = .strength
        default:
            return nil
        }
    }

    public var spokenName: String {
        switch self {
        case .running: return "running"
        case .cycling: return "cycling"
        case .walking: return "walking"
        case .hiking: return "hiking"
        case .strength: return "strength"
        }
    }
}

// MARK: - Start Workout

public struct StartWorkoutIntent: AppIntent {
    public static var title: LocalizedStringResource = "Start Workout"
    public static var description: IntentDescription = IntentDescription(
        "Starts a new GearSnitch workout for the chosen activity.",
        categoryName: "Workouts"
    )
    // Opening the app gives HealthKit permission prompts and `HKWorkoutSession`
    // (item #10) the foreground runtime it needs.
    public static var openAppWhenRun: Bool = true

    @Parameter(
        title: "Activity",
        description: "The type of workout to start.",
        default: .strength
    )
    public var activityType: WorkoutIntentActivityType

    public init() {}

    public init(activityType: WorkoutIntentActivityType) {
        self.activityType = activityType
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        try await WorkoutCoordinator.shared.start(activityType: activityType.healthKitType)
        return .result(
            dialog: IntentDialog("Starting a \(activityType.spokenName) workout.")
        )
    }
}

// MARK: - Pause Workout

public struct PauseWorkoutIntent: AppIntent {
    public static var title: LocalizedStringResource = "Pause Workout"
    public static var description: IntentDescription = IntentDescription(
        "Pauses the active GearSnitch workout.",
        categoryName: "Workouts"
    )
    // Background-capable — pause shouldn't yank the user out of Lock Screen.
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        try await WorkoutCoordinator.shared.pause()
        return .result(dialog: IntentDialog("Workout paused."))
    }
}

// MARK: - Resume Workout

public struct ResumeWorkoutIntent: AppIntent {
    public static var title: LocalizedStringResource = "Resume Workout"
    public static var description: IntentDescription = IntentDescription(
        "Resumes a paused GearSnitch workout.",
        categoryName: "Workouts"
    )
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        try await WorkoutCoordinator.shared.resume()
        return .result(dialog: IntentDialog("Workout resumed."))
    }
}

// MARK: - End Workout

public struct EndWorkoutIntent: AppIntent {
    public static var title: LocalizedStringResource = "End Workout"
    public static var description: IntentDescription = IntentDescription(
        "Ends the active GearSnitch workout and saves it.",
        categoryName: "Workouts"
    )
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        try await WorkoutCoordinator.shared.end()
        return .result(dialog: IntentDialog("Ending your workout."))
    }
}
