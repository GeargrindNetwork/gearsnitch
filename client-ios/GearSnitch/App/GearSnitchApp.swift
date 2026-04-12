import GoogleSignIn
import SwiftUI

@main
struct GearSnitchApp: App {

    // MARK: - UIKit Bridge

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // MARK: - Environment Objects

    @StateObject private var authManager = AuthManager.shared
    @StateObject private var bleManager = BLEManager()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var eventBus = RealtimeEventBus()
    @StateObject private var featureFlags = FeatureFlags()
    @StateObject private var coordinator = AppCoordinator()

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authManager)
                .environmentObject(bleManager)
                .environmentObject(locationManager)
                .environmentObject(eventBus)
                .environmentObject(featureFlags)
                .environmentObject(coordinator)
                .onOpenURL { url in
                    if GIDSignIn.sharedInstance.handle(url) {
                        return
                    }
                    coordinator.handle(url: url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else { return }
                    coordinator.handle(url: url)
                }
                .task {
                    await authManager.restoreSession()
                }
                .preferredColorScheme(.dark)
        }
    }
}
