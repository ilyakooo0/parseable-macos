import Foundation

final class ConnectionStore {
    private static let storageKey = "parseable_connections"
    private static let activeConnectionKey = "parseable_active_connection_id"

    /// Keychain account keys for connection metadata (not passwords).
    private static let keychainConnectionsKey = "parseable_connections_list"
    private static let keychainActiveIDKey = "parseable_active_connection_id"

    static func loadConnections() -> [ServerConnection] {
        // Primary: load from Keychain (survives ad-hoc re-signing)
        if let data = KeychainService.loadData(for: keychainConnectionsKey),
           let connections = try? JSONDecoder().decode([ServerConnection].self, from: data),
           !connections.isEmpty {
            return connections
        }

        // Fallback: migrate from UserDefaults (one-time, for existing users)
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return []
        }
        let connections = (try? JSONDecoder().decode([ServerConnection].self, from: data)) ?? []
        if !connections.isEmpty {
            // Migrate to Keychain so future upgrades preserve the data
            if let encoded = try? JSONEncoder().encode(connections) {
                KeychainService.saveData(encoded, for: keychainConnectionsKey)
            }
        }
        return connections
    }

    static func saveConnections(_ connections: [ServerConnection]) {
        for connection in connections {
            if !connection.password.isEmpty {
                KeychainService.savePassword(connection.password, for: connection.id)
            } else {
                KeychainService.deletePassword(for: connection.id)
            }
        }
        if let data = try? JSONEncoder().encode(connections) {
            KeychainService.saveData(data, for: keychainConnectionsKey)
            // Also write to UserDefaults for backward compatibility with
            // older versions during the transition period.
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    static func deleteConnection(_ connection: ServerConnection) {
        KeychainService.deletePassword(for: connection.id)
    }

    static func loadActiveConnectionID() -> UUID? {
        // Primary: Keychain
        if let data = KeychainService.loadData(for: keychainActiveIDKey),
           let string = String(data: data, encoding: .utf8) {
            return UUID(uuidString: string)
        }

        // Fallback: UserDefaults (migration)
        guard let string = UserDefaults.standard.string(forKey: activeConnectionKey) else {
            return nil
        }
        let id = UUID(uuidString: string)
        // Migrate to Keychain
        if let id, let data = id.uuidString.data(using: .utf8) {
            KeychainService.saveData(data, for: keychainActiveIDKey)
        }
        return id
    }

    static func saveActiveConnectionID(_ id: UUID?) {
        if let id, let data = id.uuidString.data(using: .utf8) {
            KeychainService.saveData(data, for: keychainActiveIDKey)
        } else {
            KeychainService.deleteData(for: keychainActiveIDKey)
        }
        // Also write to UserDefaults for backward compatibility
        UserDefaults.standard.set(id?.uuidString, forKey: activeConnectionKey)
    }
}
