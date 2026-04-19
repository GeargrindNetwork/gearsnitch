import SwiftUI

extension Notification.Name {
    static let debugResetOnboarding = Notification.Name("debugResetOnboarding")
}

struct RootView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var referralAttribution: ReferralAttributionStore
    @ObservedObject private var gateManager = PermissionGateManager.shared
    @ObservedObject private var releaseGateManager = ReleaseGateManager.shared

    @AppStorage("debug.forceOnboardingReset") private var forceOnboardingReset = false
    @State private var showFixPermissions = false
    @State private var onboardingComplete = false
    @State private var showPostInstallReferralBridge = false
    @StateObject private var onboardingViewModel = OnboardingViewModel()

    var body: some View {
        content
            .animation(.easeInOut(duration: 0.35), value: authManager.authState)
            .animation(.easeInOut(duration: 0.35), value: showFixPermissions)
            .task {
                onboardingViewModel.syncAuthenticationState(isAuthenticated: authManager.isAuthenticated)
                await gateManager.checkAll()
                await releaseGateManager.refreshIfNeeded()
            }
            .task(id: authManager.isAuthenticated) {
                guard authManager.isAuthenticated else { return }
                await GymSessionManager.shared.processPendingWidgetActionIfNeeded()
                // Post-install referral attribution (item #2): if the user has
                // a stashed code from a Universal Link or post-install bridge,
                // hand it to the API now that we have an auth token. The
                // store internally clears the code on success / hard reject.
                await referralAttribution.sendPendingClaim()
            }
            .task {
                // First-launch post-install fallback: if the user installed
                // from a referral link but never opened the Universal Link
                // (and so we have no code yet), open `/r/claim.html` inside
                // SFSafariViewController so we can inherit the `gs_ref`
                // cookie that survives in Safari's jar.
                triggerPostInstallReferralBridgeIfNeeded()
            }
            .sheet(isPresented: $showPostInstallReferralBridge) {
                PostInstallReferralSafariBridge(url: PostInstallReferralBridge.claimURL) {
                    showPostInstallReferralBridge = false
                }
                .ignoresSafeArea()
            }
            .onChange(of: authManager.authState) { _, _ in
                onboardingViewModel.syncAuthenticationState(isAuthenticated: authManager.isAuthenticated)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                // Re-check permissions when app returns from Settings
                Task { @MainActor in
                    await gateManager.checkAll()
                    await releaseGateManager.forceRefresh()
                    checkRequiredPermissions()
                    if authManager.isAuthenticated {
                        await GymSessionManager.shared.processPendingWidgetActionIfNeeded()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .debugResetOnboarding)) { _ in
                restartOnboarding(startAt: .welcome)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch releaseGateManager.status {
        case .checking:
            splashView
        case .blocked(let blockedState):
            UpdateRequiredView(state: blockedState)
        case .supported:
            authenticatedContent
        }
    }

    @ViewBuilder
    private var authenticatedContent: some View {
        switch authManager.authState {
        case .loading:
            splashView

        case .unauthenticated:
            onboardingFlow

        case .authenticated(let user):
            if shouldShowOnboarding(for: user) {
                onboardingFlow
            } else if showFixPermissions {
                fixPermissionsView
            } else {
                MainTabView()
                    .onAppear {
                        checkRequiredPermissions()
                    }
            }
        }
    }

    private var onboardingFlow: some View {
        NavigationStack {
            OnboardingView(
                viewModel: onboardingViewModel,
                onComplete: {
                    forceOnboardingReset = false
                    onboardingComplete = true
                    showFixPermissions = false
                }
            )
        }
    }

    private func shouldShowOnboarding(for user: GSUser) -> Bool {
        forceOnboardingReset || (!user.hasCompletedOnboarding && !onboardingComplete)
    }

    // MARK: - Post-Install Referral Bridge

    /// Open the SFSafariViewController bridge that consumes the `gs_ref`
    /// cookie set during the original `/r/<code>` Safari landing. We only do
    /// this once per install and only when there is no code already stashed
    /// (otherwise the Universal Link path already handled it).
    private func triggerPostInstallReferralBridgeIfNeeded() {
        guard !referralAttribution.hasAttemptedReferralClaim else { return }
        guard referralAttribution.attributedCode == nil else {
            // We already have a code from a Universal Link — no need to open
            // the bridge. Mark as attempted so we don't second-guess later.
            referralAttribution.markPostInstallClaimAttempted()
            return
        }
        // Mark BEFORE presenting so a crash mid-presentation doesn't loop us.
        referralAttribution.markPostInstallClaimAttempted()
        showPostInstallReferralBridge = true
    }

    // MARK: - Permission Check

    private func checkRequiredPermissions() {
        Task { @MainActor in
            await gateManager.checkAll()

            if gateManager.requiresPermissionRepair {
                showFixPermissions = true
                return
            }

            showFixPermissions = false

            if !gateManager.bluetoothGranted || !gateManager.locationGranted {
                restartOnboarding(startAt: recoveryStep())
            }
        }
    }

    // MARK: - Fix Permissions View

    private var fixPermissionsView: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.gsWarning.opacity(0.15))
                    .frame(width: 120, height: 120)

                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.gsWarning)
            }
            .padding(.bottom, 32)

            Text("Permissions Required")
                .font(.title2.bold())
                .foregroundColor(.gsText)
                .padding(.bottom, 12)

            Text("GearSnitch needs a couple of permissions that were revoked after setup. Re-enable them, then come back here to continue.")
                .font(.body)
                .foregroundColor(.gsTextSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 32)

            // List failing gates
            VStack(alignment: .leading, spacing: 12) {
                if !gateManager.bluetoothGranted {
                    permissionRow(
                        icon: "antenna.radiowaves.left.and.right",
                        title: "Bluetooth",
                        status: "Required",
                        color: .gsDanger
                    )
                }

                if !gateManager.locationGranted {
                    permissionRow(
                        icon: "location.fill",
                        title: "Location",
                        status: "Required",
                        color: .gsDanger
                    )
                }
            }
            .padding(20)
            .background(Color.gsSurface)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.gsBorder, lineWidth: 1)
            )
            .padding(.horizontal, 24)
            .padding(.top, 24)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    openSettings()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "gear")
                        Text("Open Settings")
                    }
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.gsEmerald)
                    .cornerRadius(14)
                }

                Button {
                    handlePermissionsFixed()
                } label: {
                    Text("I've Fixed It")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.gsEmerald)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }

                #if DEBUG
                Button {
                    restartOnboarding(startAt: .welcome)
                } label: {
                    Text("Reset Onboarding")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.gsTextSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                #endif
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color.gsBackground.ignoresSafeArea())
    }

    private func permissionRow(icon: String, title: String, status: String, color: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 32)

            Text(title)
                .font(.subheadline)
                .foregroundColor(.gsText)

            Spacer()

            Text(status)
                .font(.caption.weight(.semibold))
                .foregroundColor(color)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(color.opacity(0.12))
                .cornerRadius(6)
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func handlePermissionsFixed() {
        Task { @MainActor in
            await gateManager.checkAll()

            if gateManager.bluetoothGranted && gateManager.locationGranted {
                showFixPermissions = false
                return
            }

            if !gateManager.requiresPermissionRepair {
                restartOnboarding(startAt: recoveryStep())
            }
        }
    }

    private func recoveryStep() -> OnboardingStep {
        if !gateManager.bluetoothGranted {
            return .bluetoothPrePrompt
        }

        if !gateManager.locationGranted {
            return .locationWhenInUse
        }

        return .welcome
    }

    private func restartOnboarding(startAt step: OnboardingStep) {
        forceOnboardingReset = true
        onboardingComplete = false
        showFixPermissions = false
        // Sign the user out BEFORE syncing onboarding state so the first step
        // evaluates with isAuthenticated=false. Previously this reused the
        // existing Keychain tokens and the user landed mid-flow still signed in.
        Task { @MainActor in
            await authManager.logout()
            onboardingViewModel.syncAuthenticationState(
                isAuthenticated: authManager.isAuthenticated
            )
            onboardingViewModel.resetForTesting(startStep: step)
        }
    }

    // MARK: - Splash

    private var splashView: some View {
        ZStack {
            Color.gsBackground.ignoresSafeArea()

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.gsCyan.opacity(0.3), Color.clear],
                                center: .center,
                                startRadius: 12,
                                endRadius: 54
                            )
                        )
                        .frame(width: 108, height: 108)

                    Image(systemName: "shield.checkered")
                        .font(.system(size: 44))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.gsCyan, .gsEmerald],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                Text("GearSnitch")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.gsText)

                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.gsEmerald)
                    .scaleEffect(1.1)
            }
        }
    }
}

#Preview {
    RootView()
        .environmentObject(AuthManager.shared)
        .environmentObject(AppCoordinator())
        .environmentObject(BLEManager())
        .environmentObject(LocationManager())
        .environmentObject(ReferralAttributionStore.shared)
        .preferredColorScheme(.dark)
}
