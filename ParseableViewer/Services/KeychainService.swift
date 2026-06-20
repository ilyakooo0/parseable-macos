import Foundation
import os
import Security

enum KeychainService {
    private static let service = "com.parseableviewer.app"
    private static let logger = Logger(subsystem: service, category: "Keychain")

    @discardableResult
    static func savePassword(_ password: String, for connectionID: UUID) -> Bool {
        guard let data = password.data(using: .utf8) else { return false }
        return upsert(data, query: baseQuery(for: connectionID), label: connectionID.uuidString)
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
        upsert(data, query: baseQuery(for: key), label: key)
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

    // MARK: - Upsert

    /// Atomically stores `data` for the given query: tries `SecItemAdd` and,
    /// if the item already exists, falls back to `SecItemUpdate`. This avoids
    /// the delete-then-add race that could drop a write (and silently return
    /// `errSecDuplicateItem`) when two saves overlap.
    @discardableResult
    private static func upsert(_ data: Data, query: [String: Any], label: String) -> Bool {
        var addQuery = query
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return true
        }
        if addStatus == errSecDuplicateItem {
            let attributes = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if updateStatus != errSecSuccess {
                logger.error("Failed to update item for \(label): OSStatus \(updateStatus)")
            }
            return updateStatus == errSecSuccess
        }
        logger.error("Failed to save item for \(label): OSStatus \(addStatus)")
        return false
    }

    // MARK: - Base queries

    private static func baseQuery(for connectionID: UUID) -> [String: Any] {
        baseQuery(for: connectionID.uuidString)
    }

    private static func baseQuery(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
