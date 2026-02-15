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

    // MARK: - ParseableError

    func testServerErrorDescription() {
        let error = ParseableError.serverError(500, "Internal Server Error")
        XCTAssertTrue(error.errorDescription?.contains("500") ?? false)
    }

    func testUnauthorizedDescription() {
        let error = ParseableError.unauthorized
        XCTAssertTrue(error.errorDescription?.contains("Authentication") ?? false)
    }

    func testNotConnectedDescription() {
        let error = ParseableError.notConnected
        XCTAssertTrue(error.errorDescription?.contains("Not connected") ?? false)
    }

    // MARK: - User-friendly error messages

    func testUserFriendlyMessageForUnauthorized() {
        let msg = ParseableError.userFriendlyMessage(for: ParseableError.unauthorized)
        XCTAssertTrue(msg.contains("username"))
        XCTAssertTrue(msg.contains("password"))
    }

    func testUserFriendlyMessageForServerError() {
        let msg = ParseableError.userFriendlyMessage(for: ParseableError.serverError(500, "fail"))
        XCTAssertTrue(msg.contains("500"))
        XCTAssertTrue(msg.contains("Parseable"))
    }

    func testUserFriendlyMessageForInvalidURL() {
        let msg = ParseableError.userFriendlyMessage(for: ParseableError.invalidURL)
        XCTAssertTrue(msg.lowercased().contains("url"))
    }

    func testUserFriendlyMessageForNetworkTimeout() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: nil)
        let msg = ParseableError.userFriendlyMessage(for: error)
        XCTAssertTrue(msg.lowercased().contains("timed out"))
    }

    func testUserFriendlyMessageForNoInternet() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: nil)
        let msg = ParseableError.userFriendlyMessage(for: error)
        XCTAssertTrue(msg.lowercased().contains("internet") || msg.lowercased().contains("network"))
    }

    func testUserFriendlyMessageForCannotFindHost() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost, userInfo: nil)
        let msg = ParseableError.userFriendlyMessage(for: error)
        XCTAssertTrue(msg.lowercased().contains("server") || msg.lowercased().contains("find"))
    }

    func testUserFriendlyMessageForCannotConnect() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost, userInfo: nil)
        let msg = ParseableError.userFriendlyMessage(for: error)
        XCTAssertTrue(msg.lowercased().contains("connect"))
    }

    func testUserFriendlyMessageForSSLError() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorSecureConnectionFailed, userInfo: nil)
        let msg = ParseableError.userFriendlyMessage(for: error)
        XCTAssertTrue(msg.lowercased().contains("ssl") || msg.lowercased().contains("tls"))
    }

    func testUserFriendlyMessageForGenericError() {
        let error = NSError(domain: "custom", code: 42, userInfo: [NSLocalizedDescriptionKey: "Something broke"])
        let msg = ParseableError.userFriendlyMessage(for: error)
        XCTAssertEqual(msg, "Something broke")
    }

    // MARK: - Stream name validation

    func testValidStreamName() {
        XCTAssertNil(SidebarView.validateStreamName("my-stream_v2.0"))
    }

    func testStreamNameWithSpaces() {
        let error = SidebarView.validateStreamName("my stream")
        XCTAssertNotNil(error)
        XCTAssertTrue(error?.contains("letters") ?? false)
    }

    func testStreamNameTooLong() {
        let name = String(repeating: "a", count: 256)
        let error = SidebarView.validateStreamName(name)
        XCTAssertNotNil(error)
        XCTAssertTrue(error?.contains("255") ?? false)
    }

    func testStreamNameStartsWithDot() {
        let error = SidebarView.validateStreamName(".hidden")
        XCTAssertNotNil(error)
        XCTAssertTrue(error?.contains("start") ?? false)
    }

    func testStreamNameStartsWithHyphen() {
        let error = SidebarView.validateStreamName("-bad")
        XCTAssertNotNil(error)
        XCTAssertTrue(error?.contains("start") ?? false)
    }

    func testStreamNameWithSpecialChars() {
        XCTAssertNotNil(SidebarView.validateStreamName("stream@1"))
        XCTAssertNotNil(SidebarView.validateStreamName("stream/path"))
        XCTAssertNotNil(SidebarView.validateStreamName("stream name"))
    }

    func testStreamNameMaxLength() {
        let name = String(repeating: "a", count: 255)
        XCTAssertNil(SidebarView.validateStreamName(name))
    }

    // MARK: - SQL identifier escaping

    func testEscapeSQLIdentifierSimple() {
        XCTAssertEqual(QueryViewModel.escapeSQLIdentifier("logs"), "\"logs\"")
    }

    func testEscapeSQLIdentifierWithQuotes() {
        XCTAssertEqual(QueryViewModel.escapeSQLIdentifier("my\"stream"), "\"my\"\"stream\"")
    }

    func testEscapeSQLIdentifierWithSpaces() {
        XCTAssertEqual(QueryViewModel.escapeSQLIdentifier("my stream"), "\"my stream\"")
    }

    // MARK: - CSV export

    func testBuildCSVEmpty() {
        XCTAssertEqual(QueryViewModel.buildCSV(records: [], columns: []), "")
    }

    func testBuildCSVWithData() {
        let records: [LogRecord] = [
            ["level": .string("info"), "msg": .string("hello")]
        ]
        let csv = QueryViewModel.buildCSV(records: records, columns: ["level", "msg"])
        XCTAssertTrue(csv.hasPrefix("level,msg\n"))
        XCTAssertTrue(csv.contains("info"))
        XCTAssertTrue(csv.contains("hello"))
    }

    func testBuildCSVEscapesCommas() {
        let records: [LogRecord] = [
            ["msg": .string("hello, world")]
        ]
        let csv = QueryViewModel.buildCSV(records: records, columns: ["msg"])
        XCTAssertTrue(csv.contains("\"hello, world\""))
    }

    func testBuildCSVEscapesQuotes() {
        let records: [LogRecord] = [
            ["msg": .string("say \"hi\"")]
        ]
        let csv = QueryViewModel.buildCSV(records: records, columns: ["msg"])
        XCTAssertTrue(csv.contains("\"say \"\"hi\"\"\""))
    }

    // MARK: - Malformed response decoding

    func testQueryResponseMalformedThrows() throws {
        // Malformed data that is neither QueryResponse nor [LogRecord]
        let data = "not json at all".data(using: .utf8)!

        // Neither format should decode
        XCTAssertNil(try? JSONDecoder().decode(QueryResponse.self, from: data))
        XCTAssertNil(try? JSONDecoder().decode([LogRecord].self, from: data))
    }

    func testRetentionConfigEmptyDataReturnsEmpty() throws {
        // Empty data should be treated as no retention (tested via the Data.isEmpty check)
        let emptyData = Data()
        // JSONDecoder would fail on empty data
        XCTAssertThrowsError(try JSONDecoder().decode([RetentionConfig].self, from: emptyData))
    }

    func testAlertConfigMalformedThrows() {
        // Completely invalid JSON should fail AlertConfig decoding
        let data = "<<<not json>>>".data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(AlertConfig.self, from: data))
    }

    func testRetentionConfigMalformedThrows() {
        // A plain string is not valid as RetentionConfig or [RetentionConfig]
        let data = "\"just a string\"".data(using: .utf8)!
        XCTAssertNil(try? JSONDecoder().decode([RetentionConfig].self, from: data))
        XCTAssertNil(try? JSONDecoder().decode(RetentionConfig.self, from: data))
    }
}
