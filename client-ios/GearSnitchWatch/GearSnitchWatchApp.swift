import SwiftUI
import WatchConnectivity

@main
struct GearSnitchWatchApp: App {

    @StateObject private var syncManager = WatchSessionManager.shared
    @StateObject private var health = WatchHealthManager.shared

    init() {
        MainActor.assumeIsolated { Self.bootstrap() }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(syncManager)
                .environmentObject(health)
                .task {
                    await WatchHealthManager.shared.requestAuthorization()
                }
        }
    }

    /// Wires the health manager's sample + workout state callbacks into both the
    /// WatchConnectivity dispatcher (phone sync) and the complication center
    /// (timeline reload). Runs once at app launch.
    @MainActor
    private static func bootstrap() {
        WatchHealthManager.shared.onSample = { sample in
            WatchHRDispatcher.shared.send(sample: sample)
            WatchComplicationCenter.shared.recordSample(bpm: sample.bpm, at: sample.timestamp)
        }
        WatchHealthManager.shared.onWorkoutStateChange = { state in
            WatchHRDispatcher.shared.send(workoutState: state)
        }
    }
}
