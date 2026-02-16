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
                if trimmed.isEmpty || trimmed == "Unknown error" {
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
            case NSURLErrorCancelled:
                return "Request cancelled"
            default:
                return "Network error: \(error.localizedDescription)"
            }
        }
        return error.localizedDescription
    }
}

private actor ResponseCache {
    private struct Entry: Sendable {
        let data: any Sendable
        let timestamp: Date
    }

    private var cache: [String: Entry] = [:]
    private let ttl: TimeInterval = 60

    func get<T: Sendable>(_ key: String, as type: T.Type) -> T? {
        guard let entry = cache[key],
              Date().timeIntervalSince(entry.timestamp) < ttl else {
            cache.removeValue(forKey: key)
            return nil
        }
        return entry.data as? T
    }

    func set(_ key: String, value: some Sendable) {
        cache[key] = Entry(data: value, timestamp: Date())
    }

    func invalidate() {
        cache.removeAll()
    }
}

final class ParseableClient: Sendable {
    let baseURL: URL
    let username: String
    let password: String
    private let session: URLSession
    private let authHeader: String
    private let cache = ResponseCache()

    private static nonisolated(unsafe) let jsonDecoder = JSONDecoder()

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    init(url: URL, username: String, password: String) {
        self.baseURL = url
        self.username = username
        self.password = password

        let credentials = "\(username):\(password)"
        if let data = credentials.data(using: .utf8) {
            self.authHeader = "Basic \(data.base64EncodedString())"
        } else {
            self.authHeader = "Basic "
        }

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
        let key = "about"
        if let cached: ServerAbout = await cache.get(key, as: ServerAbout.self) {
            return cached
        }
        let data = try await performRequest(method: "GET", path: "/api/v1/about")
        let result = try Self.jsonDecoder.decode(ServerAbout.self, from: data)
        await cache.set(key, value: result)
        return result
    }

    // MARK: - Log Streams

    func listStreams() async throws -> [LogStream] {
        let data = try await performRequest(method: "GET", path: "/api/v1/logstream")
        return try Self.jsonDecoder.decode([LogStream].self, from: data)
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
        let key = "schema:\(stream)"
        if let cached: StreamSchema = await cache.get(key, as: StreamSchema.self) {
            return cached
        }
        let encoded = try Self.encodePathComponent(stream)
        let data = try await performRequest(method: "GET", path: "/api/v1/logstream/\(encoded)/schema")
        let result = try Self.jsonDecoder.decode(StreamSchema.self, from: data)
        await cache.set(key, value: result)
        return result
    }

    func getStreamStats(stream: String) async throws -> StreamStats {
        let key = "stats:\(stream)"
        if let cached: StreamStats = await cache.get(key, as: StreamStats.self) {
            return cached
        }
        let encoded = try Self.encodePathComponent(stream)
        let data = try await performRequest(method: "GET", path: "/api/v1/logstream/\(encoded)/stats")
        let result = try Self.jsonDecoder.decode(StreamStats.self, from: data)
        await cache.set(key, value: result)
        return result
    }

    func getStreamInfo(stream: String) async throws -> StreamInfo {
        let key = "info:\(stream)"
        if let cached: StreamInfo = await cache.get(key, as: StreamInfo.self) {
            return cached
        }
        let encoded = try Self.encodePathComponent(stream)
        let data = try await performRequest(method: "GET", path: "/api/v1/logstream/\(encoded)/info")
        let result = try Self.jsonDecoder.decode(StreamInfo.self, from: data)
        await cache.set(key, value: result)
        return result
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

        // Peek at the first non-whitespace byte to choose the decoder path:
        // '{' → wrapped response, '[' → direct array.
        let firstByte = responseData.first(where: { $0 != 0x20 && $0 != 0x0A && $0 != 0x0D && $0 != 0x09 })
        if firstByte == 0x7B { // '{'
            do {
                return try Self.jsonDecoder.decode(QueryResponse.self, from: responseData).records
            } catch {
                throw ParseableError.decodingError("Unexpected query response format")
            }
        } else {
            do {
                return try Self.jsonDecoder.decode([LogRecord].self, from: responseData)
            } catch {
                throw ParseableError.decodingError("Unexpected query response format")
            }
        }
    }

    // MARK: - Alerts

    func getAlerts(stream: String) async throws -> AlertConfig {
        // Try new API first; only fall back to legacy per-stream endpoint on 404
        do {
            let data = try await performRequest(method: "GET", path: "/api/v1/alerts")
            return try Self.jsonDecoder.decode(AlertConfig.self, from: data)
        } catch let error as ParseableError {
            if case .serverError(let code, _) = error, code == 404 {
                // New endpoint not available, try legacy below
            } else {
                throw error
            }
        }
        let encoded = try Self.encodePathComponent(stream)
        let data = try await performRequest(method: "GET", path: "/api/v1/logstream/\(encoded)/alert")
        return try Self.jsonDecoder.decode(AlertConfig.self, from: data)
    }

    // MARK: - Retention

    func getRetention(stream: String) async throws -> [RetentionConfig] {
        let encoded = try Self.encodePathComponent(stream)
        let data = try await performRequest(method: "GET", path: "/api/v1/logstream/\(encoded)/retention")
        if data.isEmpty { return [] }
        // Handle both array and single object response
        if let array = try? Self.jsonDecoder.decode([RetentionConfig].self, from: data) {
            return array
        }
        do {
            let single = try Self.jsonDecoder.decode(RetentionConfig.self, from: data)
            return [single]
        } catch {
            throw ParseableError.decodingError("Unexpected retention response format")
        }
    }

    // MARK: - Users

    func listUsers() async throws -> [UserInfo] {
        let data = try await performRequest(method: "GET", path: "/api/v1/user")
        return try Self.jsonDecoder.decode([UserInfo].self, from: data)
    }

    // MARK: - Filters

    func listFilters() async throws -> [ParseableFilter] {
        let data = try await performRequest(method: "GET", path: "/api/v1/filters")
        if data.isEmpty { return [] }
        return try Self.jsonDecoder.decode([ParseableFilter].self, from: data)
    }

    func createFilter(_ filter: ParseableFilter) async throws -> ParseableFilter {
        let body = try JSONEncoder().encode(filter)
        let data = try await performRequest(method: "POST", path: "/api/v1/filters", body: body)
        return try Self.jsonDecoder.decode(ParseableFilter.self, from: data)
    }

    func deleteFilter(id: String) async throws {
        let encoded = try Self.encodePathComponent(id)
        _ = try await performRequest(method: "DELETE", path: "/api/v1/filters/\(encoded)")
    }

    func invalidateCache() async {
        await cache.invalidate()
    }
}
