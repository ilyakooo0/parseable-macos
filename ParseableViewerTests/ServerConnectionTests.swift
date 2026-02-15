import XCTest
@testable import ParseableViewer

final class ServerConnectionTests: XCTestCase {
    // MARK: - URL parsing

    func testBaseURLWithHTTPS() {
        let conn = ServerConnection(name: "test", url: "https://example.com", username: "admin", password: "pass")
        XCTAssertEqual(conn.baseURL?.absoluteString, "https://example.com")
    }

    func testBaseURLWithHTTP() {
        let conn = ServerConnection(name: "test", url: "http://localhost:8000", username: "admin", password: "pass")
        XCTAssertEqual(conn.baseURL?.absoluteString, "http://localhost:8000")
    }

    func testBaseURLAddsHTTPS() {
        let conn = ServerConnection(name: "test", url: "example.com", username: "admin", password: "pass")
        XCTAssertEqual(conn.baseURL?.absoluteString, "https://example.com")
    }

    func testBaseURLStripsTrailingSlashes() {
        let conn = ServerConnection(name: "test", url: "https://example.com///", username: "admin", password: "pass")
        XCTAssertEqual(conn.baseURL?.absoluteString, "https://example.com")
    }

    func testBaseURLTrimsWhitespace() {
        let conn = ServerConnection(name: "test", url: "  https://example.com  ", username: "admin", password: "pass")
        XCTAssertEqual(conn.baseURL?.absoluteString, "https://example.com")
    }

    func testBaseURLWithPort() {
        let conn = ServerConnection(name: "test", url: "localhost:8000", username: "admin", password: "pass")
        XCTAssertEqual(conn.baseURL?.absoluteString, "https://localhost:8000")
    }

    // MARK: - Codable (password excluded)

    func testEncodingExcludesPassword() throws {
        let conn = ServerConnection(name: "test", url: "https://example.com", username: "admin", password: "secret")
        let data = try JSONEncoder().encode(conn)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertFalse(json.contains("secret"), "Password should not be in encoded JSON")
        XCTAssertTrue(json.contains("admin"))
        XCTAssertTrue(json.contains("example.com"))
    }

    // MARK: - Hashable/Equatable

    func testEquality() {
        let id = UUID()
        let a = ServerConnection(id: id, name: "A", url: "url", username: "user", password: "pass")
        let b = ServerConnection(id: id, name: "A", url: "url", username: "user", password: "pass")
        XCTAssertEqual(a, b)
    }

    func testInequality() {
        let a = ServerConnection(name: "A", url: "url", username: "user", password: "pass")
        let b = ServerConnection(name: "B", url: "url", username: "user", password: "pass")
        XCTAssertNotEqual(a, b)
    }

    // MARK: - BaseURL host validation

    func testBaseURLEmptyReturnsNil() {
        let conn = ServerConnection(name: "test", url: "", username: "admin", password: "pass")
        XCTAssertNil(conn.baseURL)
    }

    func testBaseURLWhitespaceOnlyReturnsNil() {
        let conn = ServerConnection(name: "test", url: "   ", username: "admin", password: "pass")
        XCTAssertNil(conn.baseURL)
    }

    func testBaseURLSchemeOnlyReturnsNil() {
        // "https://" has no host, should return nil
        let conn = ServerConnection(name: "test", url: "https://", username: "admin", password: "pass")
        XCTAssertNil(conn.baseURL)
    }
}
