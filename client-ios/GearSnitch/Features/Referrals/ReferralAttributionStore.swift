import Foundation
import os

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
    }

    // MARK: Published State

    /// The last-recorded attribution code, or nil if none has ever been set
    /// or it has already been consumed and cleared.
    @Published private(set) var attributedCode: String?

    /// True for one render after a fresh attribution lands, so the host can
    /// pop the toast. The host calls `acknowledgeToast()` to lower the flag.
    @Published private(set) var pendingToast: Bool = false

    private let defaults: ReferralAttributionDefaults
    private let logger = Logger(subsystem: "com.gearsnitch", category: "ReferralAttribution")

    init(defaults: ReferralAttributionDefaults = UserDefaults.standard) {
        self.defaults = defaults
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
        attributedCode = nil
        pendingToast = false
    }
}
