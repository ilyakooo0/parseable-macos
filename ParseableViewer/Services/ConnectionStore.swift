import Foundation

final class ConnectionStore {
    private static let storageKey = "parseable_connections"
    private static let activeConnectionKey = "parseable_active_connection_id"

    static func loadConnections() -> [ServerConnection] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return []
        }
        return (try? JSONDecoder().decode([ServerConnection].self, from: data)) ?? []
    }

    static func saveConnections(_ connections: [ServerConnection]) {
        for connection in connections {
            if !connection.password.isEmpty {
                KeychainService.savePassword(connection.password, for: connection.id)
            }
        }
        if let data = try? JSONEncoder().encode(connections) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    static func deleteConnection(_ connection: ServerConnection) {
        KeychainService.deletePassword(for: connection.id)
    }

    static func loadActiveConnectionID() -> UUID? {
        guard let string = UserDefaults.standard.string(forKey: activeConnectionKey) else {
            return nil
        }
        return UUID(uuidString: string)
    }

    static func saveActiveConnectionID(_ id: UUID?) {
        UserDefaults.standard.set(id?.uuidString, forKey: activeConnectionKey)
    }
}

final class SavedQueryStore {
    private static let storageKey = "parseable_saved_queries"

    static func load() -> [SavedQuery] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return []
        }
        return (try? JSONDecoder().decode([SavedQuery].self, from: data)) ?? []
    }

    static func save(_ queries: [SavedQuery]) {
        if let data = try? JSONEncoder().encode(queries) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

struct SavedQuery: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var sql: String
    var stream: String
    var createdAt: Date

    init(id: UUID = UUID(), name: String, sql: String, stream: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.sql = sql
        self.stream = stream
        self.createdAt = createdAt
    }
}
