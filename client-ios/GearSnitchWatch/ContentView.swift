import SwiftUI

struct ContentView: View {
    @EnvironmentObject var syncManager: WatchSessionManager

    var body: some View {
        TabView {
            HeartRateView()
                .tag(0)

            SessionView()
                .tag(1)

            AlertsView()
                .tag(2)

            QuickActionsView()
                .tag(3)
        }
        .tabViewStyle(.verticalPage)
    }
}

#Preview {
    ContentView()
        .environmentObject(WatchSessionManager.shared)
}
