import XCTest
@testable import ParseableViewer

final class SQLAutoCompleteTests: XCTestCase {

    private let streams = ["access_logs", "error_logs", "metrics"]
    private let fields = [
        SchemaField(name: "p_timestamp", dataType: "Utf8"),
        SchemaField(name: "level", dataType: "Utf8"),
        SchemaField(name: "message", dataType: "Utf8"),
        SchemaField(name: "host", dataType: "Utf8"),
        SchemaField(name: "status_code", dataType: "Int64"),
    ]

    // MARK: - Context detection

    func testContextAfterSelect() {
        let ctx = SQLCompletionProvider.determineContext(text: "SELECT ", position: 7)
        XCTAssertEqual(ctx, .columnRef)
    }

    func testContextAfterFrom() {
        let ctx = SQLCompletionProvider.determineContext(text: "SELECT * FROM ", position: 14)
        XCTAssertEqual(ctx, .tableRef)
    }

    func testContextAfterWhere() {
        let ctx = SQLCompletionProvider.determineContext(text: "SELECT * FROM t WHERE ", position: 22)
        XCTAssertEqual(ctx, .columnRef)
    }

    func testContextAfterAnd() {
        let ctx = SQLCompletionProvider.determineContext(text: "SELECT * FROM t WHERE x = 1 AND ", position: 32)
        XCTAssertEqual(ctx, .columnRef)
    }

    func testContextAfterJoin() {
        let ctx = SQLCompletionProvider.determineContext(text: "SELECT * FROM a JOIN ", position: 21)
        XCTAssertEqual(ctx, .tableRef)
    }

    func testContextAfterOrder() {
        let ctx = SQLCompletionProvider.determineContext(text: "SELECT * FROM t ORDER ", position: 22)
        XCTAssertEqual(ctx, .afterOrder)
    }

    func testContextAfterGroup() {
        let ctx = SQLCompletionProvider.determineContext(text: "SELECT * FROM t GROUP ", position: 22)
        XCTAssertEqual(ctx, .afterGroup)
    }

    func testContextAfterCommaInSelect() {
        let ctx = SQLCompletionProvider.determineContext(text: "SELECT a, ", position: 10)
        XCTAssertEqual(ctx, .columnRef)
    }

    func testContextAfterCommaInFrom() {
        let ctx = SQLCompletionProvider.determineContext(text: "SELECT * FROM a, ", position: 17)
        XCTAssertEqual(ctx, .tableRef)
    }

    func testContextGeneral() {
        let ctx = SQLCompletionProvider.determineContext(text: "", position: 0)
        XCTAssertEqual(ctx, .general)
    }

    // MARK: - Completions for keywords

    func testKeywordCompletionSelect() {
        let result = SQLCompletionProvider.completions(
            for: "SEL", cursorPosition: 3, streamNames: streams, schemaFields: fields
        )
        XCTAssertTrue(result.items.contains(where: { $0.text == "SELECT" }))
        XCTAssertEqual(result.prefix, "SEL")
        XCTAssertEqual(result.range, NSRange(location: 0, length: 3))
    }

    func testKeywordCompletionCaseInsensitive() {
        let result = SQLCompletionProvider.completions(
            for: "sel", cursorPosition: 3, streamNames: streams, schemaFields: fields
        )
        XCTAssertTrue(result.items.contains(where: { $0.text == "SELECT" }))
    }

    func testNoCompletionOnExactMatch() {
        let result = SQLCompletionProvider.completions(
            for: "SELECT", cursorPosition: 6, streamNames: [], schemaFields: []
        )
        // When the only match is exact, no items are returned
        XCTAssertTrue(result.items.isEmpty)
    }

    // MARK: - Table name completions

    func testTableCompletionAfterFrom() {
        let result = SQLCompletionProvider.completions(
            for: "SELECT * FROM ac", cursorPosition: 16, streamNames: streams, schemaFields: fields
        )
        XCTAssertTrue(result.items.contains(where: { $0.text == "\"access_logs\"" && $0.kind == .table }))
        XCTAssertFalse(result.items.contains(where: { $0.text == "\"metrics\"" }))
    }

    func testTableCompletionIncludesQuotes() {
        let result = SQLCompletionProvider.completions(
            for: "SELECT * FROM err", cursorPosition: 17, streamNames: streams, schemaFields: fields
        )
        let tableItem = result.items.first(where: { $0.kind == .table })
        XCTAssertNotNil(tableItem)
        XCTAssertEqual(tableItem?.text, "\"error_logs\"")
    }

    // MARK: - Column completions

    func testColumnCompletionAfterWhere() {
        let result = SQLCompletionProvider.completions(
            for: "SELECT * FROM t WHERE lev", cursorPosition: 25,
            streamNames: streams, schemaFields: fields
        )
        XCTAssertTrue(result.items.contains(where: { $0.text == "level" && $0.kind == .column }))
    }

    func testColumnCompletionIncludesDetail() {
        let result = SQLCompletionProvider.completions(
            for: "SELECT * FROM t WHERE sta", cursorPosition: 25,
            streamNames: streams, schemaFields: fields
        )
        let colItem = result.items.first(where: { $0.kind == .column })
        XCTAssertNotNil(colItem)
        XCTAssertEqual(colItem?.detail, "Int64")
    }

    func testColumnCompletionAfterSelect() {
        let result = SQLCompletionProvider.completions(
            for: "SELECT mes", cursorPosition: 10,
            streamNames: streams, schemaFields: fields
        )
        XCTAssertTrue(result.items.contains(where: { $0.text == "message" && $0.kind == .column }))
    }

    // MARK: - Function completions

    func testFunctionCompletion() {
        let result = SQLCompletionProvider.completions(
            for: "SELECT COU", cursorPosition: 10,
            streamNames: streams, schemaFields: fields
        )
        XCTAssertTrue(result.items.contains(where: { $0.text == "COUNT" && $0.kind == .function }))
    }

    // MARK: - Empty prefix returns nothing

    func testEmptyPrefixNoCompletions() {
        let result = SQLCompletionProvider.completions(
            for: "SELECT ", cursorPosition: 7,
            streamNames: streams, schemaFields: fields
        )
        XCTAssertTrue(result.items.isEmpty)
    }

    // MARK: - Prefix range

    func testPrefixRangeInMiddle() {
        let text = "SELECT * FROM acc WHERE"
        let result = SQLCompletionProvider.completions(
            for: text, cursorPosition: 17,
            streamNames: streams, schemaFields: fields
        )
        // "acc" starts at position 14
        XCTAssertEqual(result.range, NSRange(location: 14, length: 3))
        XCTAssertEqual(result.prefix, "acc")
    }

    // MARK: - ORDER BY / GROUP BY

    func testOrderByCompletion() {
        let result = SQLCompletionProvider.completions(
            for: "SELECT * FROM t ORDER B", cursorPosition: 23,
            streamNames: streams, schemaFields: fields
        )
        XCTAssertTrue(result.items.contains(where: { $0.text == "BY" }))
    }

    func testGroupByCompletion() {
        let result = SQLCompletionProvider.completions(
            for: "SELECT * FROM t GROUP B", cursorPosition: 23,
            streamNames: streams, schemaFields: fields
        )
        XCTAssertTrue(result.items.contains(where: { $0.text == "BY" }))
    }

    // MARK: - isWordCharacter

    func testWordCharacters() {
        XCTAssertTrue(SQLCompletionProvider.isWordCharacter(0x41))  // A
        XCTAssertTrue(SQLCompletionProvider.isWordCharacter(0x5A))  // Z
        XCTAssertTrue(SQLCompletionProvider.isWordCharacter(0x61))  // a
        XCTAssertTrue(SQLCompletionProvider.isWordCharacter(0x7A))  // z
        XCTAssertTrue(SQLCompletionProvider.isWordCharacter(0x30))  // 0
        XCTAssertTrue(SQLCompletionProvider.isWordCharacter(0x39))  // 9
        XCTAssertTrue(SQLCompletionProvider.isWordCharacter(0x5F))  // _
        XCTAssertFalse(SQLCompletionProvider.isWordCharacter(0x20)) // space
        XCTAssertFalse(SQLCompletionProvider.isWordCharacter(0x2C)) // comma
        XCTAssertFalse(SQLCompletionProvider.isWordCharacter(0x28)) // (
    }

    // MARK: - Edge cases

    func testCursorAtZero() {
        let result = SQLCompletionProvider.completions(
            for: "SELECT", cursorPosition: 0,
            streamNames: streams, schemaFields: fields
        )
        XCTAssertTrue(result.items.isEmpty)
    }

    func testCursorBeyondEnd() {
        let result = SQLCompletionProvider.completions(
            for: "SEL", cursorPosition: 100,
            streamNames: streams, schemaFields: fields
        )
        XCTAssertTrue(result.items.isEmpty)
    }

    func testEmptyText() {
        let result = SQLCompletionProvider.completions(
            for: "", cursorPosition: 0,
            streamNames: streams, schemaFields: fields
        )
        XCTAssertTrue(result.items.isEmpty)
    }

    // MARK: - Mixed context completions

    func testGeneralContextIncludesAllKinds() {
        // Typing "m" at the start should match keywords (no keywords start with m),
        // functions, tables ("metrics"), and columns ("message")
        let result = SQLCompletionProvider.completions(
            for: "m", cursorPosition: 1,
            streamNames: streams, schemaFields: fields
        )
        XCTAssertTrue(result.items.contains(where: { $0.kind == .function })) // MAX, MIN
        XCTAssertTrue(result.items.contains(where: { $0.kind == .table }))    // metrics
        XCTAssertTrue(result.items.contains(where: { $0.kind == .column }))   // message
    }

    // MARK: - Completion item properties

    func testCompletionItemKindLabels() {
        let kw = SQLCompletionItem(text: "SELECT", kind: .keyword)
        XCTAssertEqual(kw.kindLabel, "K")

        let fn = SQLCompletionItem(text: "COUNT", kind: .function)
        XCTAssertEqual(fn.kindLabel, "F")

        let tbl = SQLCompletionItem(text: "logs", kind: .table)
        XCTAssertEqual(tbl.kindLabel, "T")

        let col = SQLCompletionItem(text: "level", kind: .column)
        XCTAssertEqual(col.kindLabel, "C")
    }

    // MARK: - Context with DISTINCT, NOT, BETWEEN, etc.

    func testContextAfterDistinct() {
        let ctx = SQLCompletionProvider.determineContext(text: "SELECT DISTINCT ", position: 16)
        XCTAssertEqual(ctx, .columnRef)
    }

    func testContextAfterNot() {
        let ctx = SQLCompletionProvider.determineContext(text: "SELECT * FROM t WHERE NOT ", position: 26)
        XCTAssertEqual(ctx, .columnRef)
    }

    func testContextAfterLeftJoin() {
        let ctx = SQLCompletionProvider.determineContext(text: "SELECT * FROM a LEFT JOIN ", position: 26)
        XCTAssertEqual(ctx, .tableRef)
    }
}

// Make SQLCompletionContext Equatable for assertions
extension SQLCompletionContext: Equatable {}
