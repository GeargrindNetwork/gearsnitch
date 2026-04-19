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
    @StateObject private var referralAttribution = ReferralAttributionStore()

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
                .environmentObject(referralAttribution)
                .onOpenURL { url in
                    if GIDSignIn.sharedInstance.handle(url) {
                        return
                    }
                    referralAttribution.recordIfReferralLink(url)
                    coordinator.handle(url: url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else { return }
                    // Universal Link landed here — attribute first, then route.
                    referralAttribution.recordIfReferralLink(url)
                    coordinator.handle(url: url)
                }
                .overlay(alignment: .top) {
                    if referralAttribution.pendingToast,
                       let code = referralAttribution.attributedCode {
                        ReferralAttributionToast(code: code) {
                            referralAttribution.acknowledgeToast()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: referralAttribution.pendingToast)
                .task {
                    await authManager.restoreSession()
                }
                .preferredColorScheme(.dark)
        }
    }
}
