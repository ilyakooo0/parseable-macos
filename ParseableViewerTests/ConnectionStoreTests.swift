import XCTest
@testable import ParseableViewer

final class ConnectionStoreTests: XCTestCase {
    private let testSuiteKey = "parseable_connections_test"

    override func tearDown() {
        super.tearDown()
        // Clean up any test data from UserDefaults
        UserDefaults.standard.removeObject(forKey: "parseable_connections")
        UserDefaults.standard.removeObject(forKey: "parseable_active_connection_id")
    }

    func testSaveNilActiveConnectionID() {
        let id = UUID()
        ConnectionStore.saveActiveConnectionID(id)
        ConnectionStore.saveActiveConnectionID(nil)
        let loaded = ConnectionStore.loadActiveConnectionID()
        XCTAssertNil(loaded)
    }

    func testLoadActiveConnectionIDWhenEmpty() {
        UserDefaults.standard.removeObject(forKey: "parseable_active_connection_id")
        let loaded = ConnectionStore.loadActiveConnectionID()
        XCTAssertNil(loaded)
    }

    // MARK: - Connection persistence

    func testLoadConnectionsWhenEmpty() {
        UserDefaults.standard.removeObject(forKey: "parseable_connections")
        let connections = ConnectionStore.loadConnections()
        XCTAssertTrue(connections.isEmpty)
    }

    func testSaveAndLoadConnections() {
        let connection = ServerConnection(
            name: "Test Server",
            url: "https://logs.example.com",
            username: "admin",
            password: "secret123"
        )
        ConnectionStore.saveConnections([connection])
        let loaded = ConnectionStore.loadConnections()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].name, "Test Server")
        XCTAssertEqual(loaded[0].url, "https://logs.example.com")
        XCTAssertEqual(loaded[0].username, "admin")
    }

    func testSaveMultipleConnections() {
        let c1 = ServerConnection(name: "Prod", url: "https://prod.example.com", username: "admin", password: "p1")
        let c2 = ServerConnection(name: "Dev", url: "https://dev.example.com", username: "dev", password: "p2")
        ConnectionStore.saveConnections([c1, c2])
        let loaded = ConnectionStore.loadConnections()
        XCTAssertEqual(loaded.count, 2)
    }

    func testPasswordNotInUserDefaults() {
        let connection = ServerConnection(
            name: "Test",
            url: "https://example.com",
            username: "admin",
            password: "supersecret"
        )
        ConnectionStore.saveConnections([connection])

        // Verify password is NOT in the UserDefaults data
        if let data = UserDefaults.standard.data(forKey: "parseable_connections"),
           let jsonString = String(data: data, encoding: .utf8) {
            XCTAssertFalse(jsonString.contains("supersecret"),
                "Password should not be stored in UserDefaults JSON")
        }
    }

}
