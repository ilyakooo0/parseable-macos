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
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Failed to save password for \(account): OSStatus \(status)")
        }
        return status == errSecSuccess
    }

    static func loadPassword(for connectionID: UUID) -> String? {
        let account = connectionID.uuidString
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

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
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.error("Failed to delete password for \(account): OSStatus \(status)")
        }
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
