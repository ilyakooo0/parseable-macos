import XCTest
@testable import ParseableViewer

final class ConnectionStoreTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        KeychainService.deleteData(for: "parseable_connections_list")
        KeychainService.deleteData(for: "parseable_active_connection_id")
    }

    func testSaveNilActiveConnectionID() {
        let id = UUID()
        ConnectionStore.saveActiveConnectionID(id)
        ConnectionStore.saveActiveConnectionID(nil)
        let loaded = ConnectionStore.loadActiveConnectionID()
        XCTAssertNil(loaded)
    }

    func testLoadActiveConnectionIDWhenEmpty() {
        KeychainService.deleteData(for: "parseable_active_connection_id")
        let loaded = ConnectionStore.loadActiveConnectionID()
        XCTAssertNil(loaded)
    }

    // MARK: - Connection persistence

    func testLoadConnectionsWhenEmpty() {
        KeychainService.deleteData(for: "parseable_connections_list")
        let connections = ConnectionStore.loadConnections()
        XCTAssertTrue(connections.isEmpty)
    }

    func testSaveMultipleConnections() {
        let c1 = ServerConnection(name: "Prod", url: "https://prod.example.com", username: "admin", password: "p1")
        let c2 = ServerConnection(name: "Dev", url: "https://dev.example.com", username: "dev", password: "p2")
        ConnectionStore.saveConnections([c1, c2])
        let loaded = ConnectionStore.loadConnections()
        XCTAssertEqual(loaded.count, 2)
    }

    func testPasswordNotInKeychainConnectionData() {
        let connection = ServerConnection(
            name: "Test",
            url: "https://example.com",
            username: "admin",
            password: "supersecret"
        )
        ConnectionStore.saveConnections([connection])

        // Verify password is NOT in the connections list data
        if let data = KeychainService.loadData(for: "parseable_connections_list"),
           let jsonString = String(data: data, encoding: .utf8) {
            XCTAssertFalse(jsonString.contains("supersecret"),
                "Password should not be stored in connection list JSON")
        }
    }
}
