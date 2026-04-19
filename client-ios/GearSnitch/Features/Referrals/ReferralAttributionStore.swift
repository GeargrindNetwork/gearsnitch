import Foundation
import os

// MARK: - Notifications

extension Notification.Name {
    /// Fired after `ReferralAttributionStore.sendPendingClaim()` successfully
    /// hands the stashed referral code off to the API. The userInfo dictionary
    /// carries the `referrer` display name (when the server returned `claimed`)
    /// so listeners can pop a confirmation toast.
    static let referralClaimed = Notification.Name("GearSnitch.referralClaimed")
}

// MARK: - API Client Abstraction

/// Narrow seam over the production `APIClient` so unit tests can inject a
/// double without spinning up URLSession. Mirrors the surface
/// `sendPendingClaim()` actually uses.
protocol ReferralAttributionAPIClient: AnyObject {
    func claimReferral(code: String) async throws -> ClaimReferralResponse
}

extension APIClient: ReferralAttributionAPIClient {
    func claimReferral(code: String) async throws -> ClaimReferralResponse {
        try await self.request(APIEndpoint.Referrals.claim(code: code))
    }
}

// MARK: - Result Type

/// Outcome of a `sendPendingClaim()` attempt. The caller (RootView's boot
/// hook) uses this to decide whether to silence retries or leave the code
/// on disk for a later attempt.
enum ReferralClaimOutcome: Equatable {
    /// Server accepted the code and recorded the attribution.
    case claimed(referrer: String?)
    /// Server returned `already_attributed`; nothing to do.
    case alreadyAttributed
    /// No code on disk to claim — first launch with no Universal Link hit.
    case noPendingCode
    /// Server returned 401 — caller is not signed in yet. Code is preserved
    /// on disk so we can retry after authentication.
    case unauthenticated
    /// Server returned 4xx (other than 401) — typically 404 (code unknown)
    /// or 400 (self-referral). Code is cleared from disk so the user is not
    /// stuck retrying a permanently-bad attribution.
    case rejected(statusCode: Int, message: String?)
    /// Network error or 5xx. Code is preserved so the next launch retries.
    case transientFailure(message: String)
}

// MARK: - Storage Abstraction

/// Minimal slice of `UserDefaults` that the store actually touches. Lets unit
/// tests inject an in-memory double rather than mutating
/// `UserDefaults.standard`, which is process-global and bleeds across tests.
protocol ReferralAttributionDefaults: AnyObject {
    func string(forKey key: String) -> String?
    func bool(forKey key: String) -> Bool
    func set(_ value: Any?, forKey defaultName: String)
    func removeObject(forKey defaultName: String)
}

extension UserDefaults: ReferralAttributionDefaults {}

/// In-memory test double. Keeps the same surface as `UserDefaults` so the
/// store under test cannot tell the difference.
final class InMemoryReferralAttributionDefaults: ReferralAttributionDefaults {
    private var storage: [String: Any] = [:]

    func string(forKey key: String) -> String? {
        storage[key] as? String
    }

    func bool(forKey key: String) -> Bool {
        storage[key] as? Bool ?? false
    }

    func set(_ value: Any?, forKey defaultName: String) {
        if let value {
            storage[defaultName] = value
        } else {
            storage.removeValue(forKey: defaultName)
        }
    }

    func removeObject(forKey defaultName: String) {
        storage.removeValue(forKey: defaultName)
    }
}

// MARK: - URL Parsing

/// Pure function: given an arbitrary URL, return the referral code if and
/// only if it matches the canonical Universal Link pattern
/// `https://gearsnitch.com/r/<code>`. Returns `nil` for everything else so
/// callers can early-return without duplicating validation.
enum ReferralAttributionURLParser {

    static let host = "gearsnitch.com"
    static let pathPrefix = "/r/"

    /// Match the same code shape the API enforces (uppercase alnum, 4–32).
    private static let codePattern: NSRegularExpression = {
        // Force-try is safe: pattern is a compile-time literal verified by tests.
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: "^[A-Z0-9]{4,32}$")
    }()

    static func extractCode(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        // Accept https://gearsnitch.com/r/<code> only. We deliberately reject
        // http and other hosts so a deep link spoof cannot inject attribution.
        guard components.scheme?.lowercased() == "https" else { return nil }
        guard components.host?.lowercased() == host else { return nil }

        let path = components.path
        guard path.hasPrefix(pathPrefix) else { return nil }

        let raw = String(path.dropFirst(pathPrefix.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .uppercased()

        guard !raw.isEmpty else { return nil }

        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        guard codePattern.firstMatch(in: raw, options: [], range: range) != nil else {
            return nil
        }

        return raw
    }
}

// MARK: - Store

/// Single-shot, UserDefaults-backed attribution store for the Universal Link
/// referral flow. Records the FIRST referral code observed for the lifetime of
/// the install and ignores every subsequent record attempt — that mirrors the
/// product rule that referral attribution is set once and only once at sign-up.
@MainActor
final class ReferralAttributionStore: ObservableObject {

    // MARK: Storage Keys

    enum Keys {
        static let code = "referral.attribution.code"
        static let recordedAt = "referral.attribution.recordedAt"
        static let consumed = "referral.attribution.consumed"
        /// Raised once the post-install fallback bridge
        /// (`SFSafariViewController` → `/r/claim.html`) has been tried, so we
        /// don't open Safari on every cold start.
        static let hasAttemptedReferralClaim = "referral.attribution.hasAttemptedClaim"
    }

    // MARK: Published State

    /// The last-recorded attribution code, or nil if none has ever been set
    /// or it has already been consumed and cleared.
    @Published private(set) var attributedCode: String?

    /// True for one render after a fresh attribution lands, so the host can
    /// pop the toast. The host calls `acknowledgeToast()` to lower the flag.
    @Published private(set) var pendingToast: Bool = false

    private let defaults: ReferralAttributionDefaults
    private let apiClient: ReferralAttributionAPIClient
    private let notificationCenter: NotificationCenter
    private let logger = Logger(subsystem: "com.gearsnitch", category: "ReferralAttribution")

    /// Shared singleton wired to the production `APIClient` and standard
    /// `UserDefaults`. The `GearSnitchApp` `@StateObject` instance and this
    /// `shared` reference both target the same backing storage, so callers
    /// (e.g. RootView's boot hook) can use `shared` without worrying about
    /// duplicate state.
    static let shared = ReferralAttributionStore()

    init(
        defaults: ReferralAttributionDefaults = UserDefaults.standard,
        apiClient: ReferralAttributionAPIClient = APIClient.shared,
        notificationCenter: NotificationCenter = .default
    ) {
        self.defaults = defaults
        self.apiClient = apiClient
        self.notificationCenter = notificationCenter
        self.attributedCode = defaults.string(forKey: Keys.code)
    }

    // MARK: - Recording (single-shot)

    /// Record an attribution code if and only if no code has previously been
    /// recorded on this install. Returns `true` when the code was accepted,
    /// `false` when it was ignored (already attributed, or the input failed
    /// validation).
    @discardableResult
    func record(code rawCode: String) -> Bool {
        let normalized = rawCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard !normalized.isEmpty else {
            logger.debug("Refusing to record empty referral code")
            return false
        }

        if defaults.string(forKey: Keys.code) != nil {
            logger.info("Referral attribution already set, ignoring \(normalized, privacy: .public)")
            return false
        }

        defaults.set(normalized, forKey: Keys.code)
        defaults.set(Date().timeIntervalSince1970, forKey: Keys.recordedAt)
        defaults.set(false, forKey: Keys.consumed)

        attributedCode = normalized
        pendingToast = true
        logger.info("Recorded referral attribution \(normalized, privacy: .public)")
        return true
    }

    /// Convenience for the `.onContinueUserActivity` path. Returns the code
    /// that was actually recorded (or nil if the URL didn't match or a code
    /// was already on file).
    @discardableResult
    func recordIfReferralLink(_ url: URL) -> String? {
        guard let code = ReferralAttributionURLParser.extractCode(from: url) else {
            return nil
        }
        return record(code: code) ? code : nil
    }

    // MARK: - Toast Acknowledgement

    func acknowledgeToast() {
        pendingToast = false
    }

    // MARK: - Consumption

    /// Mark the recorded code as having been used (e.g. submitted at sign-up).
    /// The code stays on disk for audit but `attributedCode` returns `nil`
    /// afterwards so the toast / chrome do not re-appear.
    func markConsumed() {
        defaults.set(true, forKey: Keys.consumed)
        attributedCode = nil
        pendingToast = false
    }

    /// Test-only / debug-menu hard reset. Wipes every key the store wrote.
    func clearForTests() {
        defaults.removeObject(forKey: Keys.code)
        defaults.removeObject(forKey: Keys.recordedAt)
        defaults.removeObject(forKey: Keys.consumed)
        defaults.removeObject(forKey: Keys.hasAttemptedReferralClaim)
        attributedCode = nil
        pendingToast = false
    }

    // MARK: - Post-Install Claim Bridge

    /// Whether the post-install fallback (SFSafariViewController hitting
    /// `/r/claim.html`) has already been attempted on this install. The host
    /// reads this to decide whether to open the bridge on first launch.
    var hasAttemptedReferralClaim: Bool {
        defaults.bool(forKey: Keys.hasAttemptedReferralClaim)
    }

    /// Mark the post-install claim bridge as attempted. Called by the host
    /// after dismissing the SFSafariViewController so we never re-open it.
    func markPostInstallClaimAttempted() {
        defaults.set(true, forKey: Keys.hasAttemptedReferralClaim)
    }

    /// Attempt to hand the locally-stashed referral code off to the API. The
    /// caller (`RootView`'s boot hook) is responsible for ensuring this runs
    /// AFTER an auth token is in place — without one the request will short
    /// circuit with `.unauthenticated` and the code will be left on disk for
    /// the next attempt.
    @discardableResult
    func sendPendingClaim() async -> ReferralClaimOutcome {
        guard let code = defaults.string(forKey: Keys.code), !code.isEmpty else {
            logger.debug("sendPendingClaim: no pending referral code on disk")
            return .noPendingCode
        }

        do {
            let response = try await apiClient.claimReferral(code: code)
            logger.info("Referral claim succeeded for code \(code, privacy: .public): status=\(response.status, privacy: .public)")

            // Both `claimed` and `already_attributed` are terminal — clear the
            // local code so we stop retrying. We keep the consumed flag set
            // for audit and to preserve the existing single-shot guarantee.
            markConsumed()

            if response.status == "already_attributed" {
                return .alreadyAttributed
            }

            notificationCenter.post(
                name: .referralClaimed,
                object: nil,
                userInfo: response.referrer.map { ["referrer": $0] }
            )
            return .claimed(referrer: response.referrer)
        } catch let error as NetworkError {
            return handleClaimError(error)
        } catch {
            logger.error("sendPendingClaim: unexpected error \(error.localizedDescription, privacy: .public)")
            return .transientFailure(message: error.localizedDescription)
        }
    }

    private func handleClaimError(_ error: NetworkError) -> ReferralClaimOutcome {
        switch error {
        case .unauthorized, .tokenRefreshFailed:
            // No auth — leave the code on disk so we can retry after the
            // user signs in. Do not mark as attempted.
            logger.info("sendPendingClaim: not authenticated yet, will retry after sign-in")
            return .unauthenticated

        case .serverError(let statusCode, let message) where statusCode >= 400 && statusCode < 500:
            // 404 (unknown code) / 400 (self-referral) — the code is bad and
            // will never succeed. Wipe it so the user is not stuck.
            logger.error("sendPendingClaim: server rejected code (\(statusCode)): \(message, privacy: .public)")
            markConsumed()
            return .rejected(statusCode: statusCode, message: message)

        default:
            logger.error("sendPendingClaim: transient network failure: \(error.localizedDescription, privacy: .public)")
            return .transientFailure(message: error.localizedDescription)
        }
    }
}
