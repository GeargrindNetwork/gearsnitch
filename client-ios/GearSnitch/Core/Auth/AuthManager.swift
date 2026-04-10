import Foundation
import AuthenticationServices
import os
import Combine

// MARK: - Auth State

enum AuthState: Equatable {
    case unauthenticated
    case authenticated(GSUser)
    case loading

    static func == (lhs: AuthState, rhs: AuthState) -> Bool {
        switch (lhs, rhs) {
        case (.unauthenticated, .unauthenticated): return true
        case (.loading, .loading): return true
        case (.authenticated(let l), .authenticated(let r)): return l.id == r.id
        default: return false
        }
    }
}

// MARK: - Auth Manager

@MainActor
final class AuthManager: ObservableObject {

    static let shared = AuthManager()

    // MARK: Notifications

    static let sessionExpiredNotification = Notification.Name("GearSnitch.sessionExpired")
    static let didSignInNotification = Notification.Name("GearSnitch.didSignIn")
    static let didSignOutNotification = Notification.Name("GearSnitch.didSignOut")

    // MARK: Published State

    @Published private(set) var authState: AuthState = .loading

    var isAuthenticated: Bool {
        if case .authenticated = authState { return true }
        return false
    }

    var currentUser: GSUser? {
        if case .authenticated(let user) = authState { return user }
        return nil
    }

    private let tokenStore = TokenStore.shared
    private let apiClient = APIClient.shared
    private let logger = Logger(subsystem: "com.gearsnitch", category: "AuthManager")
    private var sessionExpiredCancellable: AnyCancellable?

    // MARK: Init

    private init() {
        // Listen for session expiry from APIClient
        sessionExpiredCancellable = NotificationCenter.default
            .publisher(for: AuthManager.sessionExpiredNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleSessionExpired()
                }
            }
    }

    // MARK: - Bootstrap

    /// Called at app launch to restore session from Keychain.
    func restoreSession() async {
        guard tokenStore.hasTokens else {
            authState = .unauthenticated
            return
        }

        authState = .loading

        do {
            let userDTO: UserDTO = try await apiClient.request(APIEndpoint.Auth.me)
            let user = GSUser(from: userDTO)
            authState = .authenticated(user)
            logger.info("Session restored for user \(user.id)")
            NotificationCenter.default.post(name: AuthManager.didSignInNotification, object: user)
        } catch {
            logger.warning("Session restore failed: \(error.localizedDescription)")
            tokenStore.clear()
            authState = .unauthenticated
        }
    }

    // MARK: - Sign In with Apple

    func signInWithApple(credential: ASAuthorizationAppleIDCredential) async throws {
        authState = .loading

        guard let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            authState = .unauthenticated
            throw AuthError.missingAppleToken
        }

        guard let authCodeData = credential.authorizationCode,
              let authorizationCode = String(data: authCodeData, encoding: .utf8) else {
            authState = .unauthenticated
            throw AuthError.missingAppleToken
        }

        // Build full name from Apple credential (only provided on first sign-in)
        var fullName: String?
        if let nameComponents = credential.fullName {
            let parts = [nameComponents.givenName, nameComponents.familyName].compactMap { $0 }
            if !parts.isEmpty {
                fullName = parts.joined(separator: " ")
            }
        }

        let endpoint = APIEndpoint.Auth.appleLogin(
            identityToken: identityToken,
            authorizationCode: authorizationCode,
            fullName: fullName
        )

        do {
            let response: AuthTokenResponse = try await apiClient.request(endpoint)
            completeSignIn(response: response)
        } catch {
            authState = .unauthenticated
            logger.error("Apple sign-in failed: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Sign In with Google

    func signInWithGoogle(idToken: String) async throws {
        authState = .loading

        let endpoint = APIEndpoint.Auth.googleLogin(idToken: idToken)

        do {
            let response: AuthTokenResponse = try await apiClient.request(endpoint)
            completeSignIn(response: response)
        } catch {
            authState = .unauthenticated
            logger.error("Google sign-in failed: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Logout

    func logout() async {
        logger.info("Logging out")

        // Best-effort server logout
        do {
            let _: EmptyData = try await apiClient.request(APIEndpoint.Auth.logout)
        } catch {
            logger.warning("Server logout failed (continuing local cleanup): \(error.localizedDescription)")
        }

        performLocalLogout()
    }

    // MARK: - Token Refresh

    /// Exposed for direct token refresh when needed (e.g. before socket connect).
    func refreshToken() async throws -> String {
        guard let rt = tokenStore.refreshToken else {
            throw NetworkError.tokenRefreshFailed
        }

        let endpoint = APIEndpoint.Auth.refresh
        let response: AuthTokenResponse = try await apiClient.request(endpoint)
        tokenStore.save(accessToken: response.accessToken, refreshToken: response.refreshToken)
        return response.accessToken
    }

    // MARK: - Private

    private func completeSignIn(response: AuthTokenResponse) {
        tokenStore.save(accessToken: response.accessToken, refreshToken: response.refreshToken)
        let user = GSUser(from: response.user)
        authState = .authenticated(user)
        logger.info("Sign-in complete for user \(user.id)")

        AnalyticsClient.shared.identify(userId: user.id, traits: [
            "email": user.email ?? "",
            "displayName": user.displayName ?? "",
            "subscriptionTier": user.roles.first ?? "free",
        ])
        AnalyticsClient.shared.track(event: .signInCompleted(method: "apple"))

        NotificationCenter.default.post(name: AuthManager.didSignInNotification, object: user)
    }

    private func handleSessionExpired() {
        logger.warning("Session expired — forcing logout")
        performLocalLogout()
    }

    private func performLocalLogout() {
        tokenStore.clear()
        KeychainStore.shared.deleteAll()
        authState = .unauthenticated

        NotificationCenter.default.post(name: AuthManager.didSignOutNotification, object: nil)
    }
}

// MARK: - Auth Error

enum AuthError: LocalizedError {
    case missingAppleToken
    case missingGoogleToken
    case signInCancelled

    var errorDescription: String? {
        switch self {
        case .missingAppleToken: return "Apple identity token was not provided."
        case .missingGoogleToken: return "Google ID token was not provided."
        case .signInCancelled: return "Sign-in was cancelled."
        }
    }
}
