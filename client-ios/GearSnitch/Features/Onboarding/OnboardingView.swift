import SwiftUI

struct OnboardingView: View {
    @StateObject private var viewModel = OnboardingViewModel()
    let onComplete: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress indicator
                if viewModel.currentStep != .welcome {
                    stepIndicator
                        .padding(.top, 8)
                        .padding(.horizontal, 24)
                }

                // Step content
                TabView(selection: $viewModel.currentStep) {
                    // Step 0: Welcome
                    WelcomeView(onGetStarted: { viewModel.advance() })
                        .tag(OnboardingStep.welcome)

                    // Step 1: Sign In
                    SignInView(onSignInComplete: {
                        viewModel.isSignedIn = true
                        viewModel.advance()
                    })
                    .tag(OnboardingStep.signIn)

                    // Step 2: Bluetooth
                    PermissionsRequestView(
                        icon: "bluetooth",
                        iconColor: .blue,
                        title: "Bluetooth Access",
                        description: "GearSnitch uses Bluetooth to detect and monitor your gym gear in real-time. Without this, we can't track your devices.",
                        allowTitle: "Enable Bluetooth",
                        onAllow: { viewModel.requestBluetoothPermission() },
                        onSkip: { viewModel.skipStep() }
                    )
                    .tag(OnboardingStep.bluetoothPrePrompt)

                    // Step 3: Location When In Use
                    PermissionsRequestView(
                        icon: "location",
                        iconColor: .green,
                        title: "Location Access",
                        description: "We use your location to detect when you're at the gym and record where gear was last seen if it disconnects.",
                        allowTitle: "Share Location",
                        onAllow: { viewModel.requestLocationWhenInUse() },
                        onSkip: { viewModel.skipStep() }
                    )
                    .tag(OnboardingStep.locationWhenInUse)

                    // Step 4: Location Always
                    PermissionsRequestView(
                        icon: "location.fill",
                        iconColor: .green,
                        title: "Background Location",
                        description: "For automatic gym detection and background monitoring, GearSnitch needs 'Always' location access. You can change this anytime in Settings.",
                        allowTitle: "Allow Always",
                        onAllow: { viewModel.requestLocationAlways() },
                        onSkip: { viewModel.skipStep() }
                    )
                    .tag(OnboardingStep.locationAlways)

                    // Step 5: Notifications
                    PermissionsRequestView(
                        icon: "bell.badge.fill",
                        iconColor: .orange,
                        title: "Push Notifications",
                        description: "Get instant alerts when a device disconnects, leaves range, or when your gear needs attention.",
                        allowTitle: "Enable Notifications",
                        onAllow: { viewModel.requestNotifications() },
                        onSkip: { viewModel.skipStep() }
                    )
                    .tag(OnboardingStep.notifications)

                    // Step 6: HealthKit
                    PermissionsRequestView(
                        icon: "heart.text.square",
                        iconColor: .red,
                        title: "Apple Health",
                        description: "Optionally sync your health metrics like weight, steps, and heart rate for a complete fitness picture.",
                        allowTitle: "Connect Health",
                        onAllow: { viewModel.requestHealthKitAuthorization() },
                        onSkip: { viewModel.skipStep() }
                    )
                    .tag(OnboardingStep.healthKit)

                    // Step 7: Add Gym
                    addGymStep
                        .tag(OnboardingStep.addGym)

                    // Step 8: Pair Device
                    pairDeviceStep
                        .tag(OnboardingStep.pairDevice)

                    // Step 9: Complete
                    completionStep
                        .tag(OnboardingStep.complete)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: viewModel.currentStep)
            }
        }
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                Capsule()
                    .fill(step.rawValue <= viewModel.currentStep.rawValue ? Color.cyan : Color.white.opacity(0.15))
                    .frame(height: 3)
            }
        }
    }

    // MARK: - Add Gym Step

    private var addGymStep: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 120, height: 120)

                Image(systemName: "building.2")
                    .font(.system(size: 48))
                    .foregroundColor(.green)
            }
            .padding(.bottom, 32)

            Text("Add Your Gym")
                .font(.title2.bold())
                .foregroundColor(.white)
                .padding(.bottom, 12)

            Text("Set your gym location so GearSnitch knows when you're training and can monitor your gear automatically.")
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                NavigationLink {
                    AddGymView(onGymAdded: { viewModel.advance() })
                } label: {
                    Text("Add Gym")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            LinearGradient(
                                colors: [.cyan, .green],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(14)
                }

                Button(action: { viewModel.skipStep() }) {
                    Text("Skip for Now")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color.black)
    }

    // MARK: - Pair Device Step

    private var pairDeviceStep: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.cyan.opacity(0.15))
                    .frame(width: 120, height: 120)

                Image(systemName: "sensor.tag.radiowaves.forward")
                    .font(.system(size: 48))
                    .foregroundColor(.cyan)
            }
            .padding(.bottom, 32)

            Text("Pair Your First Device")
                .font(.title2.bold())
                .foregroundColor(.white)
                .padding(.bottom, 12)

            Text("Attach a Bluetooth tracker to your gym bag, headphones, or any gear you want to protect.")
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                NavigationLink {
                    DevicePairingView()
                } label: {
                    Text("Pair Device")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            LinearGradient(
                                colors: [.cyan, .green],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(14)
                }

                Button(action: { viewModel.skipStep() }) {
                    Text("Skip for Now")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color.black)
    }

    // MARK: - Completion Step

    private var completionStep: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 140, height: 140)

                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 56))
                    .foregroundColor(.green)
            }
            .padding(.bottom, 32)

            Text("You're All Set!")
                .font(.title.bold())
                .foregroundColor(.white)
                .padding(.bottom, 12)

            Text("GearSnitch is ready to protect your gear. Head to the dashboard to start monitoring.")
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 32)

            Spacer()

            Button {
                Task {
                    await viewModel.completeOnboarding()
                    onComplete()
                }
            } label: {
                HStack {
                    if viewModel.isCompleting {
                        ProgressView()
                            .tint(.black)
                    }
                    Text("Go to Dashboard")
                        .font(.headline)
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    LinearGradient(
                        colors: [.cyan, .green],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(14)
            }
            .disabled(viewModel.isCompleting)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color.black)
    }
}

#Preview {
    NavigationStack {
        OnboardingView(onComplete: {})
    }
}
