import SwiftUI

struct RootView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var coordinator: AppCoordinator
    @ObservedObject private var gateManager = PermissionGateManager.shared
    @ObservedObject private var releaseGateManager = ReleaseGateManager.shared

    @State private var showFixPermissions = false
    @State private var onboardingComplete = false
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
            .onChange(of: authManager.authState) { _, _ in
                onboardingViewModel.syncAuthenticationState(isAuthenticated: authManager.isAuthenticated)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                // Re-check permissions when app returns from Settings
                Task {
                    await gateManager.checkAll()
                    await releaseGateManager.forceRefresh()
                }
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
            if !user.hasCompletedOnboarding && !onboardingComplete {
                // User is authenticated but hasn't completed onboarding
                onboardingFlow
            } else if showFixPermissions {
                // Required permission was revoked -- show fix flow
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
                    onboardingComplete = true
                }
            )
        }
    }

    // MARK: - Permission Check

    private func checkRequiredPermissions() {
        Task {
            await gateManager.checkAll()

            // Only check bluetooth and location -- gym/device are server-side state
            let bluetoothOK = gateManager.bluetoothGranted
            let locationOK = gateManager.locationGranted

            if !bluetoothOK || !locationOK {
                showFixPermissions = true
            } else {
                showFixPermissions = false
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

            Text("GearSnitch needs certain permissions to monitor your gear. Some required permissions have been revoked.")
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
                    // Re-check and dismiss if fixed
                    checkRequiredPermissions()
                } label: {
                    Text("I've Fixed It")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.gsEmerald)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
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
        .preferredColorScheme(.dark)
}
