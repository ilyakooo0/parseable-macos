import Foundation
import os
import Security

enum KeychainService {
    private static let service = "com.parseableviewer.app"
    private static let logger = Logger(subsystem: service, category: "Keychain")

    // MARK: - Public API

    @discardableResult
    static func savePassword(_ password: String, for connectionID: UUID) -> Bool {
        let account = connectionID.uuidString
        deletePassword(for: connectionID)

        guard let data = password.data(using: .utf8) else { return false }
        var query = dataProtectionQuery(for: connectionID)
        query[kSecValueData as String] = data
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Failed to save password for \(account): OSStatus \(status)")
        }
        return status == errSecSuccess
    }

    static func loadPassword(for connectionID: UUID) -> String? {
        let account = connectionID.uuidString
        var query = dataProtectionQuery(for: connectionID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }

        // Migration: try loading from the legacy file-based keychain.
        // This may trigger one final system prompt if the code signature has
        // changed since the item was stored, but after migration the password
        // lives in the data-protection keychain and no further prompts occur.
        if let password = loadFromLegacyKeychain(for: connectionID) {
            logger.info("Migrating password for \(account) to data-protection keychain")
            savePassword(password, for: connectionID)
            deleteLegacyPassword(for: connectionID)
            return password
        }

        if status != errSecSuccess && status != errSecItemNotFound {
            logger.error("Failed to load password for \(account): OSStatus \(status)")
        }
        return nil
    }

    @discardableResult
    static func deletePassword(for connectionID: UUID) -> Bool {
        let account = connectionID.uuidString
        let query = dataProtectionQuery(for: connectionID)
        let status = SecItemDelete(query as CFDictionary)
        // Also clean up any leftover legacy keychain entry.
        deleteLegacyPassword(for: connectionID)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.error("Failed to delete password for \(account): OSStatus \(status)")
        }
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Data-protection keychain helpers

    /// Base query targeting the data-protection keychain.
    /// Items stored here are scoped by bundle identifier rather than by
    /// code-signing identity, so they survive ad-hoc re-signing across builds.
    private static func dataProtectionQuery(for connectionID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: connectionID.uuidString,
            kSecUseDataProtectionKeychain as String: true
        ]
    }

    // MARK: - Legacy file-based keychain (migration only)

    private static func legacyQuery(for connectionID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: connectionID.uuidString
        ]
    }

    private static func loadFromLegacyKeychain(for connectionID: UUID) -> String? {
        var query = legacyQuery(for: connectionID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    private static func deleteLegacyPassword(for connectionID: UUID) -> Bool {
        let query = legacyQuery(for: connectionID)
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
