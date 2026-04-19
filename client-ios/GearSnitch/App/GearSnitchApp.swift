import GoogleSignIn
import SwiftUI

@main
struct GearSnitchApp: App {

    // MARK: - UIKit Bridge

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // MARK: - Scene Phase

    /// Used by backlog item #26 to count app-session starts for the
    /// App Store review prompt. `.active` transitions (debounced by
    /// `ReviewPromptThresholds.sessionDebounceSeconds`) count as one
    /// new session.
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - Environment Objects

    @StateObject private var authManager = AuthManager.shared
    @StateObject private var bleManager = BLEManager()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var eventBus = RealtimeEventBus()
    @StateObject private var featureFlags = FeatureFlags()
    @StateObject private var coordinator = AppCoordinator()
    @StateObject private var referralAttribution = ReferralAttributionStore.shared

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
                .onChange(of: scenePhase) { _, newPhase in
                    // Backlog item #26 — count foreground transitions
                    // for the App Store review-prompt heuristic. The
                    // controller self-debounces so rapid phase toggles
                    // don't over-count.
                    if newPhase == .active {
                        ReviewPromptController.shared.recordAppSessionStart()
                        ReviewPromptController.shared.maybeRequestReview()
                    }
                }
                .preferredColorScheme(.dark)
        }
    }
}
