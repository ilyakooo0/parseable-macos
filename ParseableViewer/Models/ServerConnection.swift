import Foundation

struct ServerConnection: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var url: String
    var username: String
    var password: String

    init(id: UUID = UUID(), name: String, url: String, username: String, password: String) {
        self.id = id
        self.name = name
        self.url = url
        self.username = username
        self.password = password
    }

    var baseURL: URL? {
        var urlString = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "https://\(urlString)"
        }
        // Remove trailing slash
        while urlString.hasSuffix("/") {
            urlString.removeLast()
        }
        return URL(string: urlString)
    }
}
