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
        for connection in connections {
            if !connection.password.isEmpty {
                KeychainService.savePassword(connection.password, for: connection.id)
            } else {
                KeychainService.deletePassword(for: connection.id)
            }
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
