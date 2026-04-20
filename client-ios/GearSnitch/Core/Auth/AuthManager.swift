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

    // MARK: Refresh Coalescing
    //
    // The server rotates refresh tokens on every /auth/refresh call — they
    // are single-use. If two concurrent callers each fire their own refresh,
    // the first succeeds (rotating the token), and the second uses the now-
    // stale token and gets 401 — which the old code interpreted as "session
    // truly expired" and forced a logout, even though we had valid tokens
    // from the first call. We fix this by funnelling every refresh through
    // a single in-flight `Task`. Concurrent callers await the same Task
    // and all see the same new access token.
    //
    // Why `@MainActor` (not an actor / not the APIClient actor): both the
    // APIClient 401-retry path and the SocketClient must share the same
    // coalescer. AuthManager is already the lifecycle owner for auth state,
    // so it's the natural home. The coalescer Task is scoped here and
    // reachable from any caller via the shared instance.
    private var currentRefresh: Task<String, Error>?

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
            _ = await StoreKitManager.shared.syncCurrentEntitlementsToBackend()
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
        let givenName = credential.fullName?.givenName
        let familyName = credential.fullName?.familyName
        if let nameComponents = credential.fullName {
            let parts = [nameComponents.givenName, nameComponents.familyName].compactMap { $0 }
            if !parts.isEmpty {
                fullName = parts.joined(separator: " ")
            }
        }

        let endpoint = APIEndpoint.Auth.appleLogin(
            identityToken: identityToken,
            authorizationCode: authorizationCode,
            fullName: fullName,
            givenName: givenName,
            familyName: familyName
        )

        do {
            let response: AuthTokenResponse = try await apiClient.request(endpoint)
            try await completeSignIn(response: response, method: "apple")
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
            try await completeSignIn(response: response, method: "google")
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

    /// Performs a token refresh, coalescing concurrent callers onto a single
    /// in-flight HTTP request. All concurrent callers receive the same new
    /// access token.
    ///
    /// Exposed for direct token refresh when needed (e.g. before socket connect)
    /// AND used by the APIClient retry-on-401 path. Every refresh MUST flow
    /// through this method so the single-use refresh token is never sent twice.
    func refreshToken() async throws -> String {
        if let inFlight = currentRefresh {
            return try await inFlight.value
        }

        let task = Task<String, Error> { [weak self] in
            guard let self else { throw NetworkError.tokenRefreshFailed }
            defer { self.currentRefresh = nil }
            return try await self.performRefresh()
        }
        currentRefresh = task
        return try await task.value
    }

    /// The actual refresh HTTP call + token persistence. This is intentionally
    /// NOT coalesced — callers must go through `refreshToken()`. Tests may
    /// inject a custom `refreshExecutor` to simulate HTTP behaviour.
    private func performRefresh() async throws -> String {
        guard let existingRefreshToken = tokenStore.refreshToken else {
            throw NetworkError.tokenRefreshFailed
        }

        if let executor = Self.refreshExecutorOverride {
            let response = try await executor(existingRefreshToken)
            tokenStore.save(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken ?? existingRefreshToken
            )
            return response.accessToken
        }

        let endpoint = APIEndpoint.Auth.refresh
        let response: TokenPairResponse = try await apiClient.request(endpoint)
        tokenStore.save(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? existingRefreshToken
        )
        return response.accessToken
    }

    // MARK: - Test Hooks
    //
    // `refreshExecutorOverride` lets tests replace the HTTP round-trip with
    // a local closure so we can deterministically assert coalescing behaviour
    // without touching URLSession. Not for use in production code.
    typealias RefreshExecutor = @Sendable (_ existingRefreshToken: String) async throws -> TokenPairResponse
    static var refreshExecutorOverride: RefreshExecutor?

    // MARK: - Private

    private func completeSignIn(response: AuthTokenResponse, method: String = "unknown") async throws {
        tokenStore.save(accessToken: response.accessToken, refreshToken: response.refreshToken)
        let userDTO: UserDTO
        let syncedEntitlements = await StoreKitManager.shared.syncCurrentEntitlementsToBackend()

        // Task 3 — profile auto-sync on login. We ALWAYS fetch /me after
        // a successful sign-in so local cache never depends on the embedded
        // payload being fresh; the embedded payload is still used as a
        // fallback when the follow-up fetch fails (e.g. transient network).
        do {
            logger.info("Fetching current profile after \(method) sign-in (auto-sync)")
            userDTO = try await apiClient.request(APIEndpoint.Auth.me)
        } catch {
            if let embeddedUser = response.user, !syncedEntitlements {
                logger.warning("Profile auto-sync failed, falling back to embedded user: \(error.localizedDescription)")
                userDTO = embeddedUser
            } else {
                logger.error("Failed to fetch current profile after \(method) sign-in: \(error.localizedDescription)")
                throw error
            }
        }

        let user = GSUser(from: userDTO)
        authState = .authenticated(user)
        logger.info("Sign-in complete for user \(user.id) via \(method)")

        // Task 3 follow-up — once authenticated, reconcile with the
        // iCloud KV store so other devices' preferences show up here.
        let local = ICloudProfilePayload(
            displayName: user.displayName,
            defaultGymId: user.defaultGymId,
            unitSystem: user.preferences?.unitSystem?.rawValue,
            healthKitOptIns: [],
            featureFlags: [:],
            notificationsEnabled: user.preferences?.notificationsEnabled,
            updatedAt: Date()
        )
        _ = ICloudProfileSync.shared.reconcile(local: local)

        AnalyticsClient.shared.identify(userId: user.id, traits: [
            "email": user.email,
            "displayName": user.displayName ?? "",
            "subscriptionTier": user.subscriptionTier ?? "free",
        ])
        AnalyticsClient.shared.track(event: .signInCompleted(method: method))

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
    case googleConfigurationMissing
    case signInCancelled

    var errorDescription: String? {
        switch self {
        case .missingAppleToken: return "Apple identity token was not provided."
        case .missingGoogleToken: return "Google ID token was not provided."
        case .googleConfigurationMissing:
            return "Google Sign-In is not configured. Set GS_GOOGLE_CLIENT_ID, GS_GOOGLE_SERVER_CLIENT_ID, and GS_GOOGLE_REVERSED_CLIENT_ID."
        case .signInCancelled: return "Sign-in was cancelled."
        }
    }
}
