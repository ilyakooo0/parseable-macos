import XCTest
@testable import ParseableViewer

final class ConnectionStoreTests: XCTestCase {
    private let testSuiteKey = "parseable_connections_test"

    override func tearDown() {
        super.tearDown()
        // Clean up any test data from UserDefaults
        UserDefaults.standard.removeObject(forKey: "parseable_connections")
        UserDefaults.standard.removeObject(forKey: "parseable_active_connection_id")
        UserDefaults.standard.removeObject(forKey: "parseable_saved_queries")
    }

    // MARK: - Active connection ID

    func testSaveAndLoadActiveConnectionID() {
        let id = UUID()
        ConnectionStore.saveActiveConnectionID(id)
        let loaded = ConnectionStore.loadActiveConnectionID()
        XCTAssertEqual(loaded, id)
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

    // MARK: - SavedQueryStore

    func testSavedQueryStoreLoadEmpty() {
        UserDefaults.standard.removeObject(forKey: "parseable_saved_queries")
        let queries = SavedQueryStore.load()
        XCTAssertTrue(queries.isEmpty)
    }

    func testSavedQueryStoreRoundTrip() {
        let query = SavedQuery(
            name: "Recent Errors",
            sql: "SELECT * FROM logs WHERE level = 'error' LIMIT 100",
            stream: "backend-logs"
        )
        SavedQueryStore.save([query])
        let loaded = SavedQueryStore.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].name, "Recent Errors")
        XCTAssertEqual(loaded[0].sql, "SELECT * FROM logs WHERE level = 'error' LIMIT 100")
        XCTAssertEqual(loaded[0].stream, "backend-logs")
    }

    func testSavedQueryStoreRoundTripWithColumnConfig() {
        let query = SavedQuery(
            name: "With Columns",
            sql: "SELECT * FROM logs",
            stream: "backend-logs",
            columnOrder: ["level", "message", "p_timestamp"],
            hiddenColumns: ["p_metadata"]
        )
        SavedQueryStore.save([query])
        let loaded = SavedQueryStore.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].columnOrder, ["level", "message", "p_timestamp"])
        XCTAssertEqual(loaded[0].hiddenColumns, ["p_metadata"])
    }

    func testSavedQueryStoreBackwardCompatibility() {
        // Simulate a saved query without column fields (pre-feature data)
        let json = """
        [{"id":"00000000-0000-0000-0000-000000000001","name":"Old Query","sql":"SELECT 1","stream":"s","createdAt":0}]
        """
        UserDefaults.standard.set(json.data(using: .utf8), forKey: "parseable_saved_queries")
        let loaded = SavedQueryStore.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].name, "Old Query")
        XCTAssertNil(loaded[0].columnOrder)
        XCTAssertNil(loaded[0].hiddenColumns)
    }

    func testSavedQueryStoreMultiple() {
        let q1 = SavedQuery(name: "Query 1", sql: "SELECT 1", stream: "s1")
        let q2 = SavedQuery(name: "Query 2", sql: "SELECT 2", stream: "s2")
        SavedQueryStore.save([q1, q2])
        let loaded = SavedQueryStore.load()
        XCTAssertEqual(loaded.count, 2)
    }

    // MARK: - SavedQuery model

    func testSavedQueryIdentifiable() {
        let q1 = SavedQuery(name: "A", sql: "SELECT 1", stream: "s")
        let q2 = SavedQuery(name: "B", sql: "SELECT 2", stream: "s")
        XCTAssertNotEqual(q1.id, q2.id)
    }

    func testSavedQueryHashable() {
        let q1 = SavedQuery(name: "A", sql: "SELECT 1", stream: "s")
        var set = Set<SavedQuery>()
        set.insert(q1)
        XCTAssertEqual(set.count, 1)
        set.insert(q1) // Same query again
        XCTAssertEqual(set.count, 1)
    }
}
