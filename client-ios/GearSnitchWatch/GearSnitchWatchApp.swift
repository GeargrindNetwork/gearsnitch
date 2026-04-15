import SwiftUI
import WatchConnectivity

@main
struct GearSnitchWatchApp: App {

    @StateObject private var syncManager = WatchSessionManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(syncManager)
        }
    }
}
