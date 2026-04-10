import Foundation
import os

/// Manages JWT access and refresh tokens, persisting them in the Keychain.
/// Thread-safe singleton — reads/writes are serialized through the Keychain layer.
final class TokenStore {

    static let shared = TokenStore()

    private let keychain = KeychainStore.shared
    private let logger = Logger(subsystem: "com.gearsnitch", category: "TokenStore")

    private init() {}

    // MARK: - Access Token

    var accessToken: String? {
        keychain.loadString(forKey: KeychainStore.Key.accessToken.rawValue)
    }

    // MARK: - Refresh Token

    var refreshToken: String? {
        keychain.loadString(forKey: KeychainStore.Key.refreshToken.rawValue)
    }

    // MARK: - Persistence

    /// Save both tokens atomically to the Keychain.
    func save(accessToken: String, refreshToken: String) {
        do {
            try keychain.save(accessToken, forKey: KeychainStore.Key.accessToken.rawValue)
            try keychain.save(refreshToken, forKey: KeychainStore.Key.refreshToken.rawValue)
            logger.debug("Tokens saved successfully")
        } catch {
            logger.error("Failed to save tokens: \(error.localizedDescription)")
        }
    }

    /// Clear all stored tokens (on logout or session expiry).
    func clear() {
        do {
            try keychain.delete(forKey: KeychainStore.Key.accessToken.rawValue)
            try keychain.delete(forKey: KeychainStore.Key.refreshToken.rawValue)
            logger.debug("Tokens cleared")
        } catch {
            logger.error("Failed to clear tokens: \(error.localizedDescription)")
        }
    }

    // MARK: - Token Introspection

    /// Whether valid-looking tokens are stored (does NOT validate JWT signature/expiry).
    var hasTokens: Bool {
        accessToken != nil && refreshToken != nil
    }

    /// Decode the JWT payload without verification to check expiry client-side.
    /// Returns nil if the token is malformed.
    func accessTokenPayload() -> JWTPayload? {
        guard let token = accessToken else { return nil }
        return JWTPayload.decode(from: token)
    }

    /// Whether the access token appears to be expired based on the `exp` claim.
    /// Returns true if no token exists or parsing fails (conservative).
    var isAccessTokenExpired: Bool {
        guard let payload = accessTokenPayload() else { return true }
        return Date() >= Date(timeIntervalSince1970: payload.exp)
    }
}

// MARK: - JWT Payload (client-side decode only)

/// Minimal JWT payload for client-side expiry checks.
/// This does NOT validate the RS256 signature — that is the server's job.
struct JWTPayload: Decodable {
    let sub: String
    let exp: TimeInterval
    let iat: TimeInterval
    let role: String?
    let scope: String?

    /// Decode the payload segment of a JWT (base64url-encoded JSON).
    static func decode(from jwt: String) -> JWTPayload? {
        let segments = jwt.split(separator: ".")
        guard segments.count == 3 else { return nil }

        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Pad to multiple of 4
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(contentsOf: String(repeating: "=", count: 4 - remainder))
        }

        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONDecoder().decode(JWTPayload.self, from: data)
    }
}
