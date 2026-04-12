import Foundation
import CoreBluetooth

// MARK: - App Configuration

/// Static configuration constants for the GearSnitch app.
enum AppConfig {

    // MARK: API

    /// Base origin for the REST API. Route definitions include the `/api/v1`
    /// prefix, so this should stay host-only.
    static let apiBaseURL: String = {
        if let override = Bundle.main.infoDictionary?["GS_API_BASE_URL"] as? String,
           !override.isEmpty {
            return override
        }
        return "https://api.gearsnitch.com"
    }()

    /// WebSocket URL for real-time events.
    static let socketURL: String = {
        if let override = Bundle.main.infoDictionary?["GS_SOCKET_URL"] as? String,
           !override.isEmpty {
            return override
        }
        return "wss://ws.gearsnitch.com"
    }()

    // MARK: Deep Links

    /// Custom URL scheme for deep linking.
    static let appScheme = "gearsnitch"

    /// Universal link domain.
    static let universalLinkDomain = "gearsnitch.com"

    // MARK: External URLs

    /// App Store listing URL.
    static let appStoreURL = "https://apps.apple.com/app/gearsnitch/id0000000000"

    /// Website-hosted privacy policy URL.
    static let privacyPolicyURL = "https://\(universalLinkDomain)/privacy"

    /// Website-hosted terms of service URL.
    static let termsURL = "https://\(universalLinkDomain)/terms"

    /// Support page URL.
    static let supportURL = "https://\(universalLinkDomain)/support"

    /// Account deletion page URL.
    static let deleteAccountURL = "https://\(universalLinkDomain)/delete-account"

    /// Support email.
    static let supportEmail = "support@gearsnitch.com"

    // MARK: BLE

    /// Timeout in seconds for BLE device scanning.
    static let bleScanTimeout: TimeInterval = 30

    /// Interval in seconds for BLE reconnection attempts.
    static let bleReconnectInterval: TimeInterval = 5

    /// Optional BLE service UUID allowlist loaded from Info.plist.
    static let bleServiceUUIDs: [CBUUID] = {
        let values = Bundle.main.infoDictionary?["GS_BLE_SERVICE_UUIDS"] as? [String] ?? []
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map(CBUUID.init(string:))
    }()

    // MARK: Keychain

    /// Keychain service identifier for stored credentials.
    static let keychainService = "com.gearsnitch.keychain"

    // MARK: Build Info

    /// Current app version string.
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    /// Current build number.
    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
