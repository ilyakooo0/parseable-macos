import XCTest
@testable import ParseableViewer

final class JSONValueTests: XCTestCase {
    // MARK: - Decoding

    func testDecodeNull() throws {
        let data = "null".data(using: .utf8)!
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(value, .null)
    }

    func testDecodeBool() throws {
        let trueData = "true".data(using: .utf8)!
        let falseData = "false".data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: trueData), .bool(true))
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: falseData), .bool(false))
    }

    func testDecodeInt() throws {
        let data = "42".data(using: .utf8)!
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(value, .int(42))
    }

    func testDecodeDouble() throws {
        let data = "3.14".data(using: .utf8)!
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(value, .double(3.14))
    }

    func testDecodeString() throws {
        let data = "\"hello\"".data(using: .utf8)!
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(value, .string("hello"))
    }

    func testDecodeArray() throws {
        let data = "[1, \"two\", true]".data(using: .utf8)!
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(value, .array([.int(1), .string("two"), .bool(true)]))
    }

    func testDecodeObject() throws {
        let data = "{\"key\": \"value\", \"count\": 5}".data(using: .utf8)!
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(value, .object(["key": .string("value"), "count": .int(5)]))
    }

    func testDecodeNestedObject() throws {
        let json = """
        {"user": {"name": "Alice", "tags": [1, 2]}, "active": true}
        """
        let data = json.data(using: .utf8)!
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        let expected: JSONValue = .object([
            "user": .object(["name": .string("Alice"), "tags": .array([.int(1), .int(2)])]),
            "active": .bool(true)
        ])
        XCTAssertEqual(value, expected)
    }

    // MARK: - Encoding roundtrip

    func testRoundtrip() throws {
        let original: JSONValue = .object([
            "name": .string("test"),
            "count": .int(42),
            "active": .bool(true),
            "data": .array([.null, .double(1.5)]),
            "nested": .object(["x": .string("y")])
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - displayString

    func testDisplayStringNull() {
        XCTAssertEqual(JSONValue.null.displayString, "null")
    }

    func testDisplayStringBool() {
        XCTAssertEqual(JSONValue.bool(true).displayString, "true")
        XCTAssertEqual(JSONValue.bool(false).displayString, "false")
    }

    func testDisplayStringInt() {
        XCTAssertEqual(JSONValue.int(42).displayString, "42")
        XCTAssertEqual(JSONValue.int(-1).displayString, "-1")
    }

    func testDisplayStringDouble() {
        // Whole doubles show without decimal
        XCTAssertEqual(JSONValue.double(5.0).displayString, "5")
        // Fractional doubles keep their precision
        XCTAssertTrue(JSONValue.double(3.14).displayString.hasPrefix("3.14"))
    }

    func testDisplayStringString() {
        XCTAssertEqual(JSONValue.string("hello").displayString, "hello")
        XCTAssertEqual(JSONValue.string("").displayString, "")
    }

    func testDisplayStringArray() {
        let arr = JSONValue.array([.int(1), .int(2), .int(3)])
        XCTAssertEqual(arr.displayString, "[3 items]")
    }

    func testDisplayStringObject() {
        let obj = JSONValue.object(["a": .int(1), "b": .int(2)])
        XCTAssertEqual(obj.displayString, "{2 fields}")
    }

    // MARK: - isScalar

    func testIsScalar() {
        XCTAssertTrue(JSONValue.null.isScalar)
        XCTAssertTrue(JSONValue.bool(true).isScalar)
        XCTAssertTrue(JSONValue.int(0).isScalar)
        XCTAssertTrue(JSONValue.double(0.0).isScalar)
        XCTAssertTrue(JSONValue.string("").isScalar)
        XCTAssertFalse(JSONValue.array([]).isScalar)
        XCTAssertFalse(JSONValue.object([:]).isScalar)
    }

    // MARK: - Accessors

    func testStringValue() {
        XCTAssertEqual(JSONValue.string("hello").stringValue, "hello")
        XCTAssertNil(JSONValue.int(42).stringValue)
    }

    func testObjectValue() {
        let dict: [String: JSONValue] = ["key": .string("val")]
        XCTAssertEqual(JSONValue.object(dict).objectValue, dict)
        XCTAssertNil(JSONValue.string("x").objectValue)
    }

    func testArrayValue() {
        let arr: [JSONValue] = [.int(1), .int(2)]
        XCTAssertEqual(JSONValue.array(arr).arrayValue, arr)
        XCTAssertNil(JSONValue.int(0).arrayValue)
    }

    // MARK: - prettyPrinted

    func testPrettyPrintedScalars() {
        XCTAssertEqual(JSONValue.null.prettyPrinted(), "null")
        XCTAssertEqual(JSONValue.bool(true).prettyPrinted(), "true")
        XCTAssertEqual(JSONValue.int(42).prettyPrinted(), "42")
        XCTAssertEqual(JSONValue.string("hi").prettyPrinted(), "\"hi\"")
    }

    func testPrettyPrintedEmptyContainers() {
        XCTAssertEqual(JSONValue.array([]).prettyPrinted(), "[]")
        XCTAssertEqual(JSONValue.object([:]).prettyPrinted(), "{}")
    }

    func testPrettyPrintedSmallArray() {
        let arr = JSONValue.array([.int(1), .int(2), .int(3)])
        XCTAssertEqual(arr.prettyPrinted(), "[1, 2, 3]")
    }

    func testPrettyPrintedMaxDepthTruncates() {
        // Build a nested object 5 levels deep
        var value: JSONValue = .string("leaf")
        for i in (0..<5).reversed() {
            value = .object(["level\(i)": value])
        }
        // With maxDepth=3, should hit displayString fallback
        let result = value.prettyPrinted(maxDepth: 3)
        // The outer 3 levels render normally; deeper levels use displayString
        XCTAssertTrue(result.contains("level0"))
        XCTAssertTrue(result.contains("level1"))
        XCTAssertTrue(result.contains("level2"))
        // level3 should be rendered as displayString summary, not expanded
        XCTAssertFalse(result.contains("\"level3\":"))
    }

    func testPrettyPrintedDefaultMaxDepthIsDeep() {
        // 10 levels deep should render fine with default maxDepth=50
        var value: JSONValue = .string("deep")
        for _ in 0..<10 {
            value = .object(["nest": value])
        }
        let result = value.prettyPrinted()
        XCTAssertTrue(result.contains("\"deep\""))
    }

    // MARK: - JSON string escaping

    func testEscapeJSONStringQuotes() {
        let result = JSONValue.escapeJSONString("hello \"world\"")
        XCTAssertEqual(result, "hello \\\"world\\\"")
    }

    func testEscapeJSONStringBackslash() {
        let result = JSONValue.escapeJSONString("path\\to\\file")
        XCTAssertEqual(result, "path\\\\to\\\\file")
    }

    func testEscapeJSONStringNewlineAndTab() {
        let result = JSONValue.escapeJSONString("line1\nline2\ttab")
        XCTAssertEqual(result, "line1\\nline2\\ttab")
    }

    func testEscapeJSONStringCarriageReturn() {
        let result = JSONValue.escapeJSONString("before\rafter")
        XCTAssertEqual(result, "before\\rafter")
    }

    func testEscapeJSONStringNoEscapingNeeded() {
        let result = JSONValue.escapeJSONString("simple text 123")
        XCTAssertEqual(result, "simple text 123")
    }

    func testPrettyPrintedStringWithSpecialChars() {
        let value = JSONValue.string("he said \"hi\" and\\or\nnewline")
        let result = value.prettyPrinted()
        XCTAssertEqual(result, "\"he said \\\"hi\\\" and\\\\or\\nnewline\"")
    }

    func testPrettyPrintedObjectKeyWithSpecialChars() {
        let value = JSONValue.object(["key\"with\"quotes": .int(1)])
        let result = value.prettyPrinted()
        XCTAssertTrue(result.contains("key\\\"with\\\"quotes"))
    }

    // MARK: - QueryResponse

    func testQueryResponseDecode() throws {
        let json = """
        {"records": [{"level": "info", "msg": "test"}], "fields": ["level", "msg"]}
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(QueryResponse.self, from: data)
        XCTAssertEqual(response.records.count, 1)
        XCTAssertEqual(response.fields, ["level", "msg"])
        XCTAssertEqual(response.records[0]["level"], .string("info"))
    }

    func testQueryResponseDecodeDirectArray() throws {
        let json = """
        [{"level": "error", "msg": "boom"}]
        """
        let data = json.data(using: .utf8)!
        // Direct array should fail for QueryResponse but succeed for [LogRecord]
        let result = try? JSONDecoder().decode(QueryResponse.self, from: data)
        XCTAssertNil(result)

        let records = try JSONDecoder().decode([LogRecord].self, from: data)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0]["level"], .string("error"))
    }

    // MARK: - LogRecord as typealias

    func testLogRecordDecoding() throws {
        let json = """
        {"p_timestamp": "2024-01-01T00:00:00Z", "level": "info", "message": "hello world"}
        """
        let data = json.data(using: .utf8)!
        let record = try JSONDecoder().decode(LogRecord.self, from: data)
        XCTAssertEqual(record["p_timestamp"], .string("2024-01-01T00:00:00Z"))
        XCTAssertEqual(record["level"], .string("info"))
        XCTAssertEqual(record["message"], .string("hello world"))
    }
}
