import Foundation
import os
import Security

enum KeychainService {
    private static let service = "com.parseableviewer.app"
    private static let logger = Logger(subsystem: service, category: "Keychain")

    @discardableResult
    static func savePassword(_ password: String, for connectionID: UUID) -> Bool {
        let account = connectionID.uuidString
        deletePassword(for: connectionID)

        guard let data = password.data(using: .utf8) else { return false }
        var query = baseQuery(for: connectionID)
        query[kSecValueData as String] = data
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Failed to save password for \(account): OSStatus \(status)")
        }
        return status == errSecSuccess
    }

    static func loadPassword(for connectionID: UUID) -> String? {
        let account = connectionID.uuidString
        var query = baseQuery(for: connectionID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.error("Failed to load password for \(account): OSStatus \(status)")
        }
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func deletePassword(for connectionID: UUID) -> Bool {
        let account = connectionID.uuidString
        let query = baseQuery(for: connectionID)
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.error("Failed to delete password for \(account): OSStatus \(status)")
        }
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Generic data storage (string-keyed)

    @discardableResult
    static func saveData(_ data: Data, for key: String) -> Bool {
        deleteData(for: key)
        var query = baseQuery(for: key)
        query[kSecValueData as String] = data
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Failed to save data for \(key): OSStatus \(status)")
        }
        return status == errSecSuccess
    }

    static func loadData(for key: String) -> Data? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.error("Failed to load data for \(key): OSStatus \(status)")
        }
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }

    @discardableResult
    static func deleteData(for key: String) -> Bool {
        let query = baseQuery(for: key)
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.error("Failed to delete data for \(key): OSStatus \(status)")
        }
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Base queries

    /// Base query targeting the data-protection keychain.
    /// Items stored here are scoped by bundle identifier rather than by
    /// code-signing identity, so they survive ad-hoc re-signing across builds.
    private static func baseQuery(for connectionID: UUID) -> [String: Any] {
        baseQuery(for: connectionID.uuidString)
    }

    private static func baseQuery(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true
        ]
    }
}
