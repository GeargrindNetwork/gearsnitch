import HealthKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var syncManager: WatchSessionManager
    @EnvironmentObject var health: WatchHealthManager
    @AppStorage("watch.onboardingShown") private var onboardingShown: Bool = false

    var body: some View {
        Group {
            if !onboardingShown && health.authorizationStatus == .notDetermined {
                PermissionsView(onComplete: { onboardingShown = true })
            } else {
                mainTabs
            }
        }
    }

    private var mainTabs: some View {
        TabView {
            HeartRateView()
                .tag(0)

            WorkoutControlView()
                .tag(1)

            SessionView()
                .tag(2)

            AlertsView()
                .tag(3)

            ECGEntryView()
                .tag(4)

            QuickActionsView()
                .tag(5)
        }
        .tabViewStyle(.verticalPage)
    }
}

#Preview {
    ContentView()
        .environmentObject(WatchSessionManager.shared)
        .environmentObject(WatchHealthManager.shared)
}
