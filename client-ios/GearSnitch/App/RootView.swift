import SwiftUI

struct RootView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        content
            .animation(.easeInOut(duration: 0.35), value: authManager.authState)
    }

    @ViewBuilder
    private var content: some View {
        switch authManager.authState {
        case .loading:
            splashView

        case .unauthenticated:
            NavigationStack {
                OnboardingView(onComplete: {
                    // Auth state change drives navigation automatically
                })
            }

        case .authenticated:
            MainTabView()
        }
    }

    // MARK: - Splash

    private var splashView: some View {
        ZStack {
            Color.gsBackground.ignoresSafeArea()

            VStack(spacing: 20) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)

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
        .preferredColorScheme(.dark)
}
