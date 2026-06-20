import Foundation

final class ConnectionStore {
    private static let keychainConnectionsKey = "parseable_connections_list"
    private static let keychainActiveIDKey = "parseable_active_connection_id"

    static func loadConnections() -> [ServerConnection] {
        guard let data = KeychainService.loadData(for: keychainConnectionsKey) else {
            return []
        }
        return (try? JSONDecoder().decode([ServerConnection].self, from: data)) ?? []
    }

    static func saveConnections(_ connections: [ServerConnection]) {
        for connection in connections where !connection.password.isEmpty {
            // Only upsert non-empty passwords. We must NOT delete on an empty
            // password here: `ServerConnection.init(from:)` decodes the password
            // as "" whenever the Keychain read transiently fails (locked
            // Keychain, errSecInteractionNotAllowed, etc.), so deleting on empty
            // would promote a transient read failure into permanent credential
            // loss on the next save. Credentials are removed only when the
            // connection itself is removed, via `deleteConnection`.
            KeychainService.savePassword(connection.password, for: connection.id)
        }
        if let data = try? JSONEncoder().encode(connections) {
            KeychainService.saveData(data, for: keychainConnectionsKey)
        }
    }

    static func deleteConnection(_ connection: ServerConnection) {
        KeychainService.deletePassword(for: connection.id)
    }

    static func loadActiveConnectionID() -> UUID? {
        guard let data = KeychainService.loadData(for: keychainActiveIDKey),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return UUID(uuidString: string)
    }

    static func saveActiveConnectionID(_ id: UUID?) {
        if let id, let data = id.uuidString.data(using: .utf8) {
            KeychainService.saveData(data, for: keychainActiveIDKey)
        } else {
            KeychainService.deleteData(for: keychainActiveIDKey)
        }
    }
}
