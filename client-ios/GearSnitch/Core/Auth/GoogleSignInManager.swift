import Foundation
import AuthenticationServices
import CryptoKit
import os

/// Handles Google Sign-In using ASWebAuthenticationSession (no Google SDK dependency).
///
/// Flow:
/// 1. Opens Google's OAuth consent page in a system browser sheet
/// 2. User authenticates and grants consent
/// 3. Google redirects back with an authorization code via the custom URL scheme
/// 4. We exchange the authorization code for tokens at Google's token endpoint
/// 5. Return the `id_token` to the caller for backend verification
@MainActor
final class GoogleSignInManager: NSObject, ObservableObject {

    @Published var isSigningIn = false

    private let logger = Logger(subsystem: "com.gearsnitch", category: "GoogleSignIn")

    // MARK: - Configuration

    /// Google OAuth client ID for iOS.
    /// Must be set in Info.plist as `GS_GOOGLE_CLIENT_ID` or overridden here.
    private var clientId: String {
        Bundle.main.infoDictionary?["GS_GOOGLE_CLIENT_ID"] as? String ?? ""
    }

    /// The redirect URI registered in Google Cloud Console for this iOS client.
    /// Uses the reversed client ID scheme that Google provides.
    private var redirectURI: String {
        "\(AppConfig.appScheme)://oauth/google/callback"
    }

    private static let authorizationEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    private static let tokenEndpoint = "https://oauth2.googleapis.com/token"

    // MARK: - Sign In

    /// Initiates Google Sign-In and returns the ID token on success.
    ///
    /// - Returns: The Google `id_token` string to send to the backend.
    /// - Throws: `AuthError.missingGoogleToken` if the flow fails or is cancelled.
    func signIn() async throws -> String {
        guard !clientId.isEmpty else {
            logger.error("Google OAuth client ID is not configured")
            throw AuthError.missingGoogleToken
        }

        isSigningIn = true
        defer { isSigningIn = false }

        // Generate PKCE code verifier + challenge
        let codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)

        // Generate nonce for ID token binding
        let nonce = UUID().uuidString

        // Build authorization URL
        guard let authURL = buildAuthorizationURL(
            codeChallenge: codeChallenge,
            nonce: nonce
        ) else {
            logger.error("Failed to build Google authorization URL")
            throw AuthError.missingGoogleToken
        }

        // Present the authentication session
        let callbackURL = try await presentAuthSession(url: authURL)

        // Extract the authorization code from the callback
        guard let code = extractAuthorizationCode(from: callbackURL) else {
            logger.error("No authorization code in Google callback URL")
            throw AuthError.missingGoogleToken
        }

        // Exchange authorization code for tokens
        let idToken = try await exchangeCodeForTokens(
            code: code,
            codeVerifier: codeVerifier
        )

        logger.info("Google Sign-In successful")
        return idToken
    }

    // MARK: - Authorization URL

    private func buildAuthorizationURL(
        codeChallenge: String,
        nonce: String
    ) -> URL? {
        var components = URLComponents(string: Self.authorizationEndpoint)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        return components?.url
    }

    // MARK: - ASWebAuthenticationSession

    private func presentAuthSession(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: AppConfig.appScheme
            ) { callbackURL, error in
                if let error = error {
                    let nsError = error as NSError
                    if nsError.domain == ASWebAuthenticationSessionErrorDomain,
                       nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: AuthError.signInCancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }

                guard let callbackURL = callbackURL else {
                    continuation.resume(throwing: AuthError.missingGoogleToken)
                    return
                }

                continuation.resume(returning: callbackURL)
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }

    // MARK: - Code Exchange

    private func extractAuthorizationCode(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        return components.queryItems?.first(where: { $0.name == "code" })?.value
    }

    private func exchangeCodeForTokens(
        code: String,
        codeVerifier: String
    ) async throws -> String {
        guard let url = URL(string: Self.tokenEndpoint) else {
            throw AuthError.missingGoogleToken
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "code": code,
            "client_id": clientId,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": codeVerifier,
        ]

        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            logger.error("Google token exchange failed with status \(statusCode)")
            if let body = String(data: data, encoding: .utf8) {
                logger.error("Response body: \(body)")
            }
            throw AuthError.missingGoogleToken
        }

        struct TokenResponse: Decodable {
            let id_token: String   // swiftlint:disable:this identifier_name
            let access_token: String  // swiftlint:disable:this identifier_name
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        return tokenResponse.id_token
    }

    // MARK: - PKCE Helpers

    /// Generate a cryptographically random code verifier (43-128 chars, unreserved URL chars).
    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Generate the S256 code challenge from the verifier.
    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension GoogleSignInManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return ASPresentationAnchor()
        }
        return window
    }
}
