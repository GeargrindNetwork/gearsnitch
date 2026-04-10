import Foundation
import AuthenticationServices

@MainActor
final class SignInViewModel: ObservableObject {

    @Published var isLoading = false
    @Published var isAuthenticated = false
    @Published var error: String?

    private let authManager = AuthManager.shared
    private let googleSignInManager = GoogleSignInManager()

    // MARK: - Apple Sign-In

    func handleAppleSignIn(result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                error = "Unexpected credential type."
                return
            }
            Task {
                await performAppleSignIn(credential: credential)
            }
        case .failure(let err):
            if (err as NSError).code == ASAuthorizationError.canceled.rawValue {
                // User cancelled — no error shown
                return
            }
            error = err.localizedDescription
        }
    }

    private func performAppleSignIn(credential: ASAuthorizationAppleIDCredential) async {
        isLoading = true
        error = nil

        do {
            try await authManager.signInWithApple(credential: credential)
            isAuthenticated = true
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Google Sign-In

    func signInWithGoogle() {
        Task {
            await performGoogleSignIn()
        }
    }

    private func performGoogleSignIn() async {
        isLoading = true
        error = nil

        do {
            let idToken = try await googleSignInManager.signIn()
            try await authManager.signInWithGoogle(idToken: idToken)
            isAuthenticated = true
        } catch AuthError.signInCancelled {
            // User cancelled — no error shown
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}
