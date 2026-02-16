import XCTest
@testable import ParseableViewer

final class ConnectionStoreTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        // Clean up UserDefaults
        UserDefaults.standard.removeObject(forKey: "parseable_connections")
        UserDefaults.standard.removeObject(forKey: "parseable_active_connection_id")
        // Clean up Keychain
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
        UserDefaults.standard.removeObject(forKey: "parseable_active_connection_id")
        KeychainService.deleteData(for: "parseable_active_connection_id")
        let loaded = ConnectionStore.loadActiveConnectionID()
        XCTAssertNil(loaded)
    }

    // MARK: - Connection persistence

    func testLoadConnectionsWhenEmpty() {
        UserDefaults.standard.removeObject(forKey: "parseable_connections")
        KeychainService.deleteData(for: "parseable_connections_list")
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

    // MARK: - Migration from UserDefaults to Keychain

    func testMigratesConnectionsFromUserDefaults() {
        // Simulate old version: data only in UserDefaults, not in Keychain
        let connection = ServerConnection(
            name: "Legacy Server",
            url: "https://legacy.example.com",
            username: "admin",
            password: ""
        )
        let data = try! JSONEncoder().encode([connection])
        UserDefaults.standard.set(data, forKey: "parseable_connections")
        KeychainService.deleteData(for: "parseable_connections_list")

        let loaded = ConnectionStore.loadConnections()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].name, "Legacy Server")

        // Verify migration: data should now be in Keychain
        let keychainData = KeychainService.loadData(for: "parseable_connections_list")
        XCTAssertNotNil(keychainData, "Connections should be migrated to Keychain")
    }

    func testMigratesActiveConnectionIDFromUserDefaults() {
        // Simulate old version: active ID only in UserDefaults
        let id = UUID()
        UserDefaults.standard.set(id.uuidString, forKey: "parseable_active_connection_id")
        KeychainService.deleteData(for: "parseable_active_connection_id")

        let loaded = ConnectionStore.loadActiveConnectionID()
        XCTAssertEqual(loaded, id)

        // Verify migration: should now be in Keychain
        let keychainData = KeychainService.loadData(for: "parseable_active_connection_id")
        XCTAssertNotNil(keychainData, "Active connection ID should be migrated to Keychain")
    }

    func testKeychainTakesPriorityOverUserDefaults() {
        // Put different data in Keychain vs UserDefaults
        let keychainConn = ServerConnection(
            name: "Keychain Server",
            url: "https://keychain.example.com",
            username: "admin",
            password: ""
        )
        let udConn = ServerConnection(
            name: "UserDefaults Server",
            url: "https://ud.example.com",
            username: "admin",
            password: ""
        )

        let keychainData = try! JSONEncoder().encode([keychainConn])
        KeychainService.saveData(keychainData, for: "parseable_connections_list")

        let udData = try! JSONEncoder().encode([udConn])
        UserDefaults.standard.set(udData, forKey: "parseable_connections")

        let loaded = ConnectionStore.loadConnections()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].name, "Keychain Server",
            "Keychain data should take priority over UserDefaults")
    }

    func testConnectionsSurviveUserDefaultsWipe() {
        // Save connections normally (writes to both Keychain and UserDefaults)
        let connection = ServerConnection(
            name: "Persistent",
            url: "https://persistent.example.com",
            username: "admin",
            password: "pass"
        )
        ConnectionStore.saveConnections([connection])

        // Simulate UserDefaults being wiped (as happens on app upgrade
        // with ad-hoc signing)
        UserDefaults.standard.removeObject(forKey: "parseable_connections")

        let loaded = ConnectionStore.loadConnections()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].name, "Persistent",
            "Connections should survive UserDefaults being wiped")
    }

    func testActiveIDSurvivesUserDefaultsWipe() {
        let id = UUID()
        ConnectionStore.saveActiveConnectionID(id)

        // Simulate UserDefaults being wiped
        UserDefaults.standard.removeObject(forKey: "parseable_active_connection_id")

        let loaded = ConnectionStore.loadActiveConnectionID()
        XCTAssertEqual(loaded, id,
            "Active connection ID should survive UserDefaults being wiped")
    }
}
