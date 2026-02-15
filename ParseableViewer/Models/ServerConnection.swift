import Foundation

struct ServerConnection: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var url: String
    var username: String
    /// Password is stored in Keychain, not serialized to UserDefaults.
    var password: String

    private enum CodingKeys: String, CodingKey {
        case id, name, url, username
    }

    init(id: UUID = UUID(), name: String, url: String, username: String, password: String) {
        self.id = id
        self.name = name
        self.url = url
        self.username = username
        self.password = password
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.url = try container.decode(String.self, forKey: .url)
        self.username = try container.decode(String.self, forKey: .username)
        self.password = KeychainService.loadPassword(for: self.id) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(url, forKey: .url)
        try container.encode(username, forKey: .username)
    }

    var baseURL: URL? {
        var urlString = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if urlString.isEmpty { return nil }
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "https://\(urlString)"
        }
        while urlString.hasSuffix("/") {
            urlString.removeLast()
        }
        guard let parsed = URL(string: urlString), parsed.host != nil else {
            return nil
        }
        return parsed
    }
}
