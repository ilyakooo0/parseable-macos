import Foundation

enum ParseableError: LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(Int, String)
    case decodingError(String)
    case notConnected
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid server URL"
        case .invalidResponse: return "Invalid response from server"
        case .serverError(let code, let msg): return "Server error (\(code)): \(msg)"
        case .decodingError(let msg): return "Failed to decode response: \(msg)"
        case .notConnected: return "Not connected to server"
        case .unauthorized: return "Authentication failed. Check your credentials."
        }
    }
}

final class ParseableClient: Sendable {
    let baseURL: URL
    let username: String
    let password: String
    private let session: URLSession

    init(url: URL, username: String, password: String) {
        self.baseURL = url
        self.username = username
        self.password = password

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
    }

    convenience init(connection: ServerConnection) throws {
        guard let url = connection.baseURL else {
            throw ParseableError.invalidURL
        }
        self.init(url: url, username: connection.username, password: connection.password)
    }

    private var authHeader: String {
        let credentials = "\(username):\(password)"
        let data = credentials.data(using: .utf8)!
        return "Basic \(data.base64EncodedString())"
    }

    private func buildRequest(method: String, path: String, body: Data? = nil, queryItems: [URLQueryItem]? = nil) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if let queryItems {
            components?.queryItems = queryItems
        }
        guard let url = components?.url else {
            throw ParseableError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
        }
        return request
    }

    private func performRequest(method: String, path: String, body: Data? = nil, queryItems: [URLQueryItem]? = nil) async throws -> Data {
        let request = try buildRequest(method: method, path: path, body: body, queryItems: queryItems)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ParseableError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw ParseableError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ParseableError.serverError(httpResponse.statusCode, message)
        }

        return data
    }

    // MARK: - Health / System

    func checkHealth() async throws -> Bool {
        let request = try buildRequest(method: "HEAD", path: "/api/v1/liveness")
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return false }
        return httpResponse.statusCode == 200
    }

    func getAbout() async throws -> ServerAbout {
        let data = try await performRequest(method: "GET", path: "/api/v1/about")
        return try JSONDecoder().decode(ServerAbout.self, from: data)
    }

    // MARK: - Log Streams

    func listStreams() async throws -> [LogStream] {
        let data = try await performRequest(method: "GET", path: "/api/v1/logstream")
        return try JSONDecoder().decode([LogStream].self, from: data)
    }

    func createStream(name: String) async throws {
        _ = try await performRequest(method: "PUT", path: "/api/v1/logstream/\(name)")
    }

    func deleteStream(name: String) async throws {
        _ = try await performRequest(method: "DELETE", path: "/api/v1/logstream/\(name)")
    }

    func getStreamSchema(stream: String) async throws -> StreamSchema {
        let data = try await performRequest(method: "GET", path: "/api/v1/logstream/\(stream)/schema")
        return try JSONDecoder().decode(StreamSchema.self, from: data)
    }

    func getStreamStats(stream: String) async throws -> StreamStats {
        let data = try await performRequest(method: "GET", path: "/api/v1/logstream/\(stream)/stats")
        return try JSONDecoder().decode(StreamStats.self, from: data)
    }

    func getStreamInfo(stream: String) async throws -> StreamInfo {
        let data = try await performRequest(method: "GET", path: "/api/v1/logstream/\(stream)/info")
        return try JSONDecoder().decode(StreamInfo.self, from: data)
    }

    // MARK: - Query

    func query(sql: String, startTime: Date, endTime: Date) async throws -> [LogRecord] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let body: [String: Any] = [
            "query": sql,
            "startTime": formatter.string(from: startTime),
            "endTime": formatter.string(from: endTime)
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let responseData = try await performRequest(method: "POST", path: "/api/v1/query", body: bodyData)

        if responseData.isEmpty {
            return []
        }

        return try JSONDecoder().decode([LogRecord].self, from: responseData)
    }

    // MARK: - Alerts

    func getAlerts(stream: String) async throws -> AlertConfig {
        let data = try await performRequest(method: "GET", path: "/api/v1/logstream/\(stream)/alert")
        return try JSONDecoder().decode(AlertConfig.self, from: data)
    }

    // MARK: - Retention

    func getRetention(stream: String) async throws -> [RetentionConfig] {
        let data = try await performRequest(method: "GET", path: "/api/v1/logstream/\(stream)/retention")
        // Handle both array and single object response
        if let array = try? JSONDecoder().decode([RetentionConfig].self, from: data) {
            return array
        }
        if let single = try? JSONDecoder().decode(RetentionConfig.self, from: data) {
            return [single]
        }
        return []
    }

    // MARK: - Users

    func listUsers() async throws -> [UserInfo] {
        let data = try await performRequest(method: "GET", path: "/api/v1/user")
        return try JSONDecoder().decode([UserInfo].self, from: data)
    }
}
