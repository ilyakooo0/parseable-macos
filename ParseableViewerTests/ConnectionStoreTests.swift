import XCTest
@testable import ParseableViewer

final class ConnectionStoreTests: XCTestCase {
    /// Whether the data-protection keychain is available in this environment.
    /// CI runners may lack the entitlements needed for `kSecUseDataProtectionKeychain`.
    private static let keychainAvailable: Bool = {
        let probe = "keychain-probe"
        let saved = KeychainService.saveData(Data(probe.utf8), for: "_test_probe")
        if saved {
            KeychainService.deleteData(for: "_test_probe")
        }
        return saved
    }()

    override func tearDown() {
        super.tearDown()
        KeychainService.deleteData(for: "parseable_connections_list")
        KeychainService.deleteData(for: "parseable_active_connection_id")
    }

    func testSaveNilActiveConnectionID() throws {
        try XCTSkipUnless(Self.keychainAvailable, "Data-protection keychain unavailable")
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

    func testSaveAndLoadActiveConnectionID() throws {
        try XCTSkipUnless(Self.keychainAvailable, "Data-protection keychain unavailable")
        let id = UUID()
        ConnectionStore.saveActiveConnectionID(id)
        let loaded = ConnectionStore.loadActiveConnectionID()
        XCTAssertEqual(loaded, id)
    }

    func testRoundTripConnectionPersistence() throws {
        try XCTSkipUnless(Self.keychainAvailable, "Data-protection keychain unavailable")
        let conn = ServerConnection(
            name: "Prod",
            url: "https://logs.example.com",
            username: "admin",
            password: "s3cret!"
        )
        ConnectionStore.saveConnections([conn])

        let loaded = ConnectionStore.loadConnections()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, conn.id)
        XCTAssertEqual(loaded.first?.name, "Prod")
        XCTAssertEqual(loaded.first?.url, "https://logs.example.com")
        XCTAssertEqual(loaded.first?.username, "admin")
        XCTAssertEqual(loaded.first?.password, "s3cret!")

        // Clean up
        KeychainService.deletePassword(for: conn.id)
    }

    func testRoundTripMultipleConnections() throws {
        try XCTSkipUnless(Self.keychainAvailable, "Data-protection keychain unavailable")
        let conn1 = ServerConnection(
            name: "Server A",
            url: "https://a.example.com",
            username: "user1",
            password: "pass1"
        )
        let conn2 = ServerConnection(
            name: "Server B",
            url: "https://b.example.com",
            username: "user2",
            password: "pass2"
        )
        ConnectionStore.saveConnections([conn1, conn2])

        let loaded = ConnectionStore.loadConnections()
        XCTAssertEqual(loaded.count, 2)

        let loadedA = loaded.first { $0.id == conn1.id }
        let loadedB = loaded.first { $0.id == conn2.id }
        XCTAssertEqual(loadedA?.name, "Server A")
        XCTAssertEqual(loadedA?.password, "pass1")
        XCTAssertEqual(loadedB?.name, "Server B")
        XCTAssertEqual(loadedB?.password, "pass2")

        // Clean up
        KeychainService.deletePassword(for: conn1.id)
        KeychainService.deletePassword(for: conn2.id)
    }

    func testPasswordNotInKeychainConnectionData() throws {
        try XCTSkipUnless(Self.keychainAvailable, "Data-protection keychain unavailable")
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
