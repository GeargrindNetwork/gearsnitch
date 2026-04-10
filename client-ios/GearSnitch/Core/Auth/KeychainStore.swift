import Foundation
import Security

/// Thin wrapper around the iOS Keychain for secure credential storage.
/// Uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — data does not
/// migrate to new devices or iCloud backups.
final class KeychainStore {

    enum Key: String {
        case accessToken = "com.gearsnitch.accessToken"
        case refreshToken = "com.gearsnitch.refreshToken"
        case deviceSessionId = "com.gearsnitch.deviceSessionId"
    }

    enum KeychainError: LocalizedError {
        case saveFailed(OSStatus)
        case loadFailed(OSStatus)
        case deleteFailed(OSStatus)
        case dataConversionFailed

        var errorDescription: String? {
            switch self {
            case .saveFailed(let status):
                return "Keychain save failed: \(status)"
            case .loadFailed(let status):
                return "Keychain load failed: \(status)"
            case .deleteFailed(let status):
                return "Keychain delete failed: \(status)"
            case .dataConversionFailed:
                return "Failed to convert keychain data"
            }
        }
    }

    static let shared = KeychainStore()
    private init() {}

    // MARK: - Save

    func save(_ data: Data, forKey key: String) throws {
        // Delete any existing item first to avoid errSecDuplicateItem
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    /// Convenience: save a UTF-8 string.
    func save(_ string: String, forKey key: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw KeychainError.dataConversionFailed
        }
        try save(data, forKey: key)
    }

    // MARK: - Load

    func load(forKey key: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.loadFailed(status)
        }

        return data
    }

    /// Convenience: load a UTF-8 string, returning nil if not found.
    func loadString(forKey key: String) -> String? {
        guard let data = try? load(forKey: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Delete

    func delete(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    // MARK: - Bulk Operations

    /// Delete all GearSnitch keychain entries.
    func deleteAll() {
        for key in Key.allCases {
            try? delete(forKey: key.rawValue)
        }
    }
}

extension KeychainStore.Key: CaseIterable {}
