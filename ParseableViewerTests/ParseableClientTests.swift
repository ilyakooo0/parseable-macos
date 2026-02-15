import XCTest
@testable import ParseableViewer

final class ParseableClientTests: XCTestCase {
    // MARK: - Query response parsing

    func testQueryResponseWrappedFormat() throws {
        let json = """
        {"records": [{"message": "hello"}], "fields": ["message"]}
        """.data(using: .utf8)!

        let wrapped = try JSONDecoder().decode(QueryResponse.self, from: json)
        XCTAssertEqual(wrapped.records.count, 1)
        XCTAssertEqual(wrapped.records[0]["message"], .string("hello"))
        XCTAssertEqual(wrapped.fields, ["message"])
    }

    func testQueryResponseDirectArrayFormat() throws {
        let json = """
        [{"level": "info", "msg": "test"}]
        """.data(using: .utf8)!

        let records = try JSONDecoder().decode([LogRecord].self, from: json)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0]["level"], .string("info"))
        XCTAssertEqual(records[0]["msg"], .string("test"))
    }

    func testQueryResponseEmptyArray() throws {
        let json = "[]".data(using: .utf8)!
        let records = try JSONDecoder().decode([LogRecord].self, from: json)
        XCTAssertTrue(records.isEmpty)
    }

    func testQueryResponseWrappedEmptyRecords() throws {
        let json = """
        {"records": [], "fields": ["a", "b"]}
        """.data(using: .utf8)!

        let wrapped = try JSONDecoder().decode(QueryResponse.self, from: json)
        XCTAssertTrue(wrapped.records.isEmpty)
        XCTAssertEqual(wrapped.fields, ["a", "b"])
    }

    // MARK: - Alert config decoding

    func testAlertConfigKeyedFormat() throws {
        let json = """
        {"alerts": [{"name": "high-cpu", "message": "CPU > 90%"}], "version": "v1"}
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(AlertConfig.self, from: json)
        XCTAssertEqual(config.alerts?.count, 1)
        XCTAssertEqual(config.alerts?[0].name, "high-cpu")
        XCTAssertEqual(config.version, "v1")
    }

    func testAlertConfigDirectArrayFormat() throws {
        let json = """
        [{"name": "disk-full", "message": "Disk usage > 95%"}]
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(AlertConfig.self, from: json)
        XCTAssertEqual(config.alerts?.count, 1)
        XCTAssertEqual(config.alerts?[0].name, "disk-full")
        XCTAssertNil(config.version)
    }

    func testAlertConfigMemberwiseInit() {
        let config = AlertConfig(alerts: [], version: nil)
        XCTAssertEqual(config.alerts?.count, 0)
        XCTAssertNil(config.version)
    }

    // MARK: - Retention config decoding

    func testRetentionConfigArray() throws {
        let json = """
        [{"description": "Keep 30 days", "duration": "30d", "action": "delete"}]
        """.data(using: .utf8)!

        let configs = try JSONDecoder().decode([RetentionConfig].self, from: json)
        XCTAssertEqual(configs.count, 1)
        XCTAssertEqual(configs[0].duration, "30d")
    }

    func testRetentionConfigSingleObject() throws {
        let json = """
        {"description": "Keep 7 days", "duration": "7d", "action": "delete"}
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(RetentionConfig.self, from: json)
        XCTAssertEqual(config.duration, "7d")
        XCTAssertEqual(config.action, "delete")
    }

    // MARK: - Stream schema decoding

    func testStreamSchemaKeyedFormat() throws {
        let json = """
        {"fields": [{"name": "level", "data_type": "Utf8"}]}
        """.data(using: .utf8)!

        let schema = try JSONDecoder().decode(StreamSchema.self, from: json)
        XCTAssertEqual(schema.fields.count, 1)
        XCTAssertEqual(schema.fields[0].name, "level")
        XCTAssertEqual(schema.fields[0].dataType, "Utf8")
    }

    func testStreamSchemaDirectArrayFormat() throws {
        let json = """
        [{"name": "count", "data_type": "Int64"}]
        """.data(using: .utf8)!

        let schema = try JSONDecoder().decode(StreamSchema.self, from: json)
        XCTAssertEqual(schema.fields.count, 1)
        XCTAssertEqual(schema.fields[0].dataType, "Int64")
    }

    func testSchemaFieldObjectDataType() throws {
        let json = """
        {"name": "tags", "data_type": {"List": "Utf8"}}
        """.data(using: .utf8)!

        let field = try JSONDecoder().decode(SchemaField.self, from: json)
        XCTAssertEqual(field.name, "tags")
        XCTAssertFalse(field.dataType.isEmpty)
    }

    // MARK: - User info decoding

    func testUserInfoKeyedFormat() throws {
        let json = """
        {"id": "admin", "method": "native"}
        """.data(using: .utf8)!

        let user = try JSONDecoder().decode(UserInfo.self, from: json)
        XCTAssertEqual(user.id, "admin")
        XCTAssertEqual(user.method, "native")
    }

    func testUserInfoPlainString() throws {
        let json = """
        "readonly-user"
        """.data(using: .utf8)!

        let user = try JSONDecoder().decode(UserInfo.self, from: json)
        XCTAssertEqual(user.id, "readonly-user")
        XCTAssertNil(user.method)
    }

    // MARK: - LogStream decoding

    func testLogStreamKeyedFormat() throws {
        let json = """
        {"name": "backend-logs"}
        """.data(using: .utf8)!

        let stream = try JSONDecoder().decode(LogStream.self, from: json)
        XCTAssertEqual(stream.name, "backend-logs")
    }

    func testLogStreamPlainString() throws {
        let json = """
        "frontend-logs"
        """.data(using: .utf8)!

        let stream = try JSONDecoder().decode(LogStream.self, from: json)
        XCTAssertEqual(stream.name, "frontend-logs")
    }

    // MARK: - ServerAbout decoding

    func testServerAboutPartialFields() throws {
        let json = """
        {"version": "1.0.0", "mode": "standalone"}
        """.data(using: .utf8)!

        let about = try JSONDecoder().decode(ServerAbout.self, from: json)
        XCTAssertEqual(about.version, "1.0.0")
        XCTAssertEqual(about.mode, "standalone")
        XCTAssertNil(about.commit)
        XCTAssertNil(about.grpcPort)
    }

    func testServerAboutEmptyObject() throws {
        let json = "{}".data(using: .utf8)!
        let about = try JSONDecoder().decode(ServerAbout.self, from: json)
        XCTAssertNil(about.version)
        XCTAssertNil(about.mode)
    }

    // MARK: - Auth header

    func testClientInitFromConnection() throws {
        let connection = ServerConnection(
            name: "test",
            url: "https://example.com",
            username: "admin",
            password: "secret"
        )
        let client = try ParseableClient(connection: connection)
        XCTAssertEqual(client.username, "admin")
        XCTAssertEqual(client.baseURL.absoluteString, "https://example.com")
    }

    func testClientInitInvalidURL() {
        let connection = ServerConnection(
            name: "test",
            url: "",
            username: "admin",
            password: "secret"
        )
        XCTAssertThrowsError(try ParseableClient(connection: connection))
    }
}
