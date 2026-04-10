import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @StateObject private var viewModel = SignInViewModel()
    var onSignInComplete: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo
            VStack(spacing: 16) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 48))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan, .green],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("GearSnitch")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("Sign in to get started")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }

            Spacer()

            // Auth buttons
            VStack(spacing: 14) {
                // Apple Sign In
                appleSignInButton

                // Google Sign In
                Button(action: { viewModel.signInWithGoogle() }) {
                    HStack(spacing: 12) {
                        Image(systemName: "g.circle.fill")
                            .font(.title2)

                        Text("Continue with Google")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 24)

            // Error
            if let error = viewModel.error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.top, 12)
                    .padding(.horizontal, 24)
            }

            // Loading
            if viewModel.isLoading {
                ProgressView()
                    .tint(.cyan)
                    .padding(.top, 16)
            }

            Spacer()
                .frame(height: 40)

            // Legal
            VStack(spacing: 8) {
                Text("By continuing, you agree to our")
                    .font(.caption2)
                    .foregroundColor(.gray)

                HStack(spacing: 4) {
                    Link("Terms of Service", destination: URL(string: "https://gearsnitch.app/terms")!)
                        .font(.caption2.bold())
                        .foregroundColor(.cyan)

                    Text("and")
                        .font(.caption2)
                        .foregroundColor(.gray)

                    Link("Privacy Policy", destination: URL(string: "https://gearsnitch.app/privacy")!)
                        .font(.caption2.bold())
                        .foregroundColor(.cyan)
                }
            }
            .padding(.bottom, 32)
        }
        .background(Color.black.ignoresSafeArea())
        .onChange(of: viewModel.isAuthenticated) { authenticated in
            if authenticated {
                onSignInComplete?()
            }
        }
    }

    // MARK: - Apple Sign-In Button

    private var appleSignInButton: some View {
        SignInWithAppleButtonRepresentable(
            onRequest: { request in
                request.requestedScopes = [.fullName, .email]
            },
            onCompletion: { result in
                viewModel.handleAppleSignIn(result: result)
            }
        )
        .frame(height: 54)
        .cornerRadius(14)
    }
}

// MARK: - Apple Sign In Button (UIViewRepresentable)

struct SignInWithAppleButtonRepresentable: UIViewRepresentable {
    let onRequest: (ASAuthorizationAppleIDRequest) -> Void
    let onCompletion: (Result<ASAuthorization, Error>) -> Void

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .signIn, style: .white)
        button.cornerRadius = 14
        button.addTarget(context.coordinator, action: #selector(Coordinator.handleTap), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onRequest: onRequest, onCompletion: onCompletion)
    }

    class Coordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
        let onRequest: (ASAuthorizationAppleIDRequest) -> Void
        let onCompletion: (Result<ASAuthorization, Error>) -> Void

        init(onRequest: @escaping (ASAuthorizationAppleIDRequest) -> Void,
             onCompletion: @escaping (Result<ASAuthorization, Error>) -> Void) {
            self.onRequest = onRequest
            self.onCompletion = onCompletion
        }

        @objc func handleTap() {
            let request = ASAuthorizationAppleIDProvider().createRequest()
            onRequest(request)

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
            onCompletion(.success(authorization))
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
            onCompletion(.failure(error))
        }

        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = scene.windows.first else {
                return UIWindow()
            }
            return window
        }
    }
}

#Preview {
    SignInView()
}
