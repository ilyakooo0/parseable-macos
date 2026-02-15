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

    /// Maps any error into a user-friendly message, handling ParseableError cases
    /// and common NSURLError codes.
    static func userFriendlyMessage(for error: Error) -> String {
        if let parseableError = error as? ParseableError {
            switch parseableError {
            case .unauthorized:
                return "Authentication failed. Check your username and password."
            case .invalidURL:
                return "The server URL is invalid. Check the format (e.g. https://host:port)."
            case .serverError(let code, let message):
                let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    return "Server returned error \(code)."
                }
                return "Server error (\(code)): \(trimmed)"
            default:
                return parseableError.localizedDescription
            }
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                return "No internet connection. Check your network and try again."
            case NSURLErrorCannotFindHost:
                return "Cannot find server. Check the URL and your network connection."
            case NSURLErrorCannotConnectToHost:
                return "Cannot connect to server. Check the URL and that the server is running."
            case NSURLErrorTimedOut:
                return "Connection timed out. The server may be unreachable."
            case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted:
                return "SSL/TLS error. The server certificate may be invalid or untrusted."
            default:
                return "Network error: \(error.localizedDescription)"
            }
        }
        return error.localizedDescription
    }
}

final class ParseableClient: Sendable {
    let baseURL: URL
    let username: String
    let password: String
    private let session: URLSession

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

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

    deinit {
        // Use finishTasksAndInvalidate so in-flight requests (e.g. a query
        // the user just ran) can complete rather than being silently cancelled.
        session.finishTasksAndInvalidate()
    }

    private var authHeader: String {
        let credentials = "\(username):\(password)"
        guard let data = credentials.data(using: .utf8) else {
            return "Basic "
        }
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

    func checkHealth() async throws {
        let request = try buildRequest(method: "HEAD", path: "/api/v1/liveness")
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ParseableError.invalidResponse
        }
        if httpResponse.statusCode == 401 {
            throw ParseableError.unauthorized
        }
        guard httpResponse.statusCode == 200 else {
            throw ParseableError.serverError(httpResponse.statusCode, "Health check failed")
        }
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

    private static func encodePathComponent(_ name: String) throws -> String {
        // Use a restrictive character set for path segments: exclude /?#[]@!$&'()*+,;=
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=")
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: allowed) else {
            throw ParseableError.invalidURL
        }
        return encoded
    }

    func createStream(name: String) async throws {
        let encoded = try Self.encodePathComponent(name)
        _ = try await performRequest(method: "PUT", path: "/api/v1/logstream/\(encoded)")
    }

    func deleteStream(name: String) async throws {
        let encoded = try Self.encodePathComponent(name)
        _ = try await performRequest(method: "DELETE", path: "/api/v1/logstream/\(encoded)")
    }

    func getStreamSchema(stream: String) async throws -> StreamSchema {
        let encoded = try Self.encodePathComponent(stream)
        let data = try await performRequest(method: "GET", path: "/api/v1/logstream/\(encoded)/schema")
        return try JSONDecoder().decode(StreamSchema.self, from: data)
    }

    func getStreamStats(stream: String) async throws -> StreamStats {
        let encoded = try Self.encodePathComponent(stream)
        let data = try await performRequest(method: "GET", path: "/api/v1/logstream/\(encoded)/stats")
        return try JSONDecoder().decode(StreamStats.self, from: data)
    }

    func getStreamInfo(stream: String) async throws -> StreamInfo {
        let encoded = try Self.encodePathComponent(stream)
        let data = try await performRequest(method: "GET", path: "/api/v1/logstream/\(encoded)/info")
        return try JSONDecoder().decode(StreamInfo.self, from: data)
    }

    // MARK: - Query

    func query(sql: String, startTime: Date, endTime: Date) async throws -> [LogRecord] {
        let body: [String: Any] = [
            "query": sql,
            "startTime": Self.isoFormatter.string(from: startTime),
            "endTime": Self.isoFormatter.string(from: endTime)
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let responseData = try await performRequest(method: "POST", path: "/api/v1/query", body: bodyData)

        if responseData.isEmpty {
            return []
        }

        // Handle both response formats:
        // 1. Wrapped: {"records": [...], "fields": [...]}
        // 2. Direct array: [...]
        if let wrapped = try? JSONDecoder().decode(QueryResponse.self, from: responseData) {
            return wrapped.records
        }
        do {
            return try JSONDecoder().decode([LogRecord].self, from: responseData)
        } catch {
            throw ParseableError.decodingError("Unexpected query response format")
        }
    }

    // MARK: - Alerts

    func getAlerts(stream: String) async throws -> AlertConfig {
        // Try new API first; only fall back to legacy per-stream endpoint on 404
        do {
            let data = try await performRequest(method: "GET", path: "/api/v1/alerts")
            return try JSONDecoder().decode(AlertConfig.self, from: data)
        } catch let error as ParseableError {
            if case .serverError(let code, _) = error, code == 404 {
                // New endpoint not available, try legacy below
            } else {
                throw error
            }
        }
        let encoded = try Self.encodePathComponent(stream)
        let data = try await performRequest(method: "GET", path: "/api/v1/logstream/\(encoded)/alert")
        return try JSONDecoder().decode(AlertConfig.self, from: data)
    }

    // MARK: - Retention

    func getRetention(stream: String) async throws -> [RetentionConfig] {
        let encoded = try Self.encodePathComponent(stream)
        let data = try await performRequest(method: "GET", path: "/api/v1/logstream/\(encoded)/retention")
        if data.isEmpty { return [] }
        // Handle both array and single object response
        if let array = try? JSONDecoder().decode([RetentionConfig].self, from: data) {
            return array
        }
        do {
            let single = try JSONDecoder().decode(RetentionConfig.self, from: data)
            return [single]
        } catch {
            throw ParseableError.decodingError("Unexpected retention response format")
        }
    }

    // MARK: - Users

    func listUsers() async throws -> [UserInfo] {
        let data = try await performRequest(method: "GET", path: "/api/v1/user")
        return try JSONDecoder().decode([UserInfo].self, from: data)
    }
}
