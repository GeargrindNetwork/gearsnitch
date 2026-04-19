// TODO(google-signin): re-enable after package re-added
//
// The entire GoogleSignIn integration is temporarily gated out while the
// GoogleSignIn SPM dependency is removed to unblock local iOS builds.
// Apple Sign-In and email/password paths remain active. Server-side
// `POST /api/v1/auth/oauth/google` endpoints are intentionally left in
// place so this file can simply be un-gated once the package is restored.
#if false
import Combine
import Foundation
import GoogleSignIn
import UIKit
import os

/// Handles Google Sign-In via the official GoogleSignIn SDK.
///
/// The native iOS client ID opens the consent flow, while the server client ID
/// becomes the `aud` claim on the returned ID token so the backend can verify
/// the same Google identity across iOS and web.
@MainActor
final class GoogleSignInManager: ObservableObject {

    @Published var isSigningIn = false

    private let logger = Logger(subsystem: "com.gearsnitch", category: "GoogleSignIn")

    private var clientId: String {
        Bundle.main.infoDictionary?["GS_GOOGLE_CLIENT_ID"] as? String ?? ""
    }

    private var serverClientId: String {
        Bundle.main.infoDictionary?["GS_GOOGLE_SERVER_CLIENT_ID"] as? String ?? ""
    }

    private var reversedClientId: String {
        Bundle.main.infoDictionary?["GS_GOOGLE_REVERSED_CLIENT_ID"] as? String ?? ""
    }

    func signIn() async throws -> String {
        guard isConfigurationValid else {
            logger.error("Google Sign-In configuration is incomplete")
            throw AuthError.googleConfigurationMissing
        }

        guard let presentingViewController = Self.presentingViewController() else {
            logger.error("No presenting view controller available for Google Sign-In")
            throw AuthError.missingGoogleToken
        }

        isSigningIn = true
        defer { isSigningIn = false }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: clientId,
            serverClientID: serverClientId
        )

        do {
            let signInResult = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presentingViewController
            )

            guard let idToken = signInResult.user.idToken?.tokenString else {
                logger.error("Google Sign-In completed without an ID token")
                throw AuthError.missingGoogleToken
            }

            logger.info("Google Sign-In succeeded")
            return idToken
        } catch {
            let nsError = error as NSError
            if nsError.domain == kGIDSignInErrorDomain, nsError.code == -5 {
                throw AuthError.signInCancelled
            }

            logger.error("Google Sign-In failed: \(error.localizedDescription)")
            throw error
        }
    }

    private var isConfigurationValid: Bool {
        !clientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !serverClientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !reversedClientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func presentingViewController() -> UIViewController? {
        let windowScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }

        let window = windowScenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
            ?? windowScenes.flatMap(\.windows).first

        return Self.topViewController(from: window?.rootViewController)
    }

    private static func topViewController(from root: UIViewController?) -> UIViewController? {
        if let navigationController = root as? UINavigationController {
            return topViewController(from: navigationController.visibleViewController)
        }

        if let tabBarController = root as? UITabBarController {
            return topViewController(from: tabBarController.selectedViewController)
        }

        if let presentedViewController = root?.presentedViewController {
            return topViewController(from: presentedViewController)
        }

        return root
    }
}
#endif
