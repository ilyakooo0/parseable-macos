import XCTest
@testable import ParseableViewer

final class SQLTokenizerTests: XCTestCase {

    // MARK: - Tokenizer basics

    func testTokenizesSimpleSelect() {
        let tokens = SQLTokenizer.tokenize("SELECT * FROM t")
        let kinds = tokens.map(\.kind)
        XCTAssertEqual(kinds, [
            .keyword("SELECT"), .whitespace, .star, .whitespace,
            .keyword("FROM"), .whitespace, .identifier("t"),
        ])
    }

    func testTokenizesQuotedIdentifier() {
        let tokens = SQLTokenizer.tokenize(#"SELECT "my col" FROM t"#)
        let kinds = tokens.map(\.kind)
        XCTAssertEqual(kinds, [
            .keyword("SELECT"), .whitespace, .quotedIdentifier("my col"),
            .whitespace, .keyword("FROM"), .whitespace, .identifier("t"),
        ])
    }

    func testTokenizesDoubledQuoteEscape() {
        let tokens = SQLTokenizer.tokenize(#"SELECT "a""b" FROM t"#)
        let ids = tokens.compactMap { token -> String? in
            if case .quotedIdentifier(let v) = token.kind { return v }
            return nil
        }
        XCTAssertEqual(ids, [#"a"b"#])
    }

    func testTokenizesStringLiteral() {
        let tokens = SQLTokenizer.tokenize("SELECT 'hello' FROM t")
        let strings = tokens.compactMap { token -> String? in
            if case .stringLiteral(let v) = token.kind { return v }
            return nil
        }
        XCTAssertEqual(strings, ["hello"])
    }

    func testTokenizesEscapedStringLiteral() {
        let tokens = SQLTokenizer.tokenize("SELECT 'it''s' FROM t")
        let strings = tokens.compactMap { token -> String? in
            if case .stringLiteral(let v) = token.kind { return v }
            return nil
        }
        XCTAssertEqual(strings, ["it's"])
    }

    func testTokenizesLineComment() {
        let tokens = SQLTokenizer.tokenize("SELECT * -- get all\nFROM t")
        let kinds = tokens.map(\.kind)
        XCTAssertTrue(kinds.contains(.lineComment))
        // FROM should still be tokenized as a keyword
        XCTAssertTrue(kinds.contains(.keyword("FROM")))
    }

    func testTokenizesBlockComment() {
        let tokens = SQLTokenizer.tokenize("SELECT /* cols */ * FROM t")
        let kinds = tokens.map(\.kind)
        XCTAssertTrue(kinds.contains(.blockComment))
        XCTAssertTrue(kinds.contains(.star))
    }

    func testTokenizesNumber() {
        let tokens = SQLTokenizer.tokenize("LIMIT 100")
        let nums = tokens.compactMap { token -> String? in
            if case .number(let v) = token.kind { return v }
            return nil
        }
        XCTAssertEqual(nums, ["100"])
    }

    func testTokenizesNumberWithExponent() {
        let tokens = SQLTokenizer.tokenize("SELECT 1.5e-3")
        let nums = tokens.compactMap { token -> String? in
            if case .number(let v) = token.kind { return v }
            return nil
        }
        XCTAssertEqual(nums, ["1.5e-3"])
    }

    func testTokenizesOperators() {
        let tokens = SQLTokenizer.tokenize("a <> b")
        let others = tokens.compactMap { token -> String? in
            if case .other(let v) = token.kind { return v }
            return nil
        }
        XCTAssertEqual(others, ["<", ">"])
    }

    func testKeywordsAreCaseInsensitive() {
        let tokens = SQLTokenizer.tokenize("select distinct from where")
        let keywords = tokens.compactMap { token -> String? in
            if case .keyword(let v) = token.kind { return v }
            return nil
        }
        // All stored uppercased
        XCTAssertEqual(keywords, ["SELECT", "DISTINCT", "FROM", "WHERE"])
    }

    func testNonKeywordIdentifier() {
        let tokens = SQLTokenizer.tokenize("SELECT mycol FROM t")
        let ids = tokens.compactMap { token -> String? in
            if case .identifier(let v) = token.kind { return v }
            return nil
        }
        XCTAssertEqual(ids, ["mycol", "t"])
    }

    // MARK: - selectColumnListRange

    func testSimpleSelectStar() {
        let sql = "SELECT * FROM table1"
        let range = SQLTokenizer.selectColumnListRange(in: sql)
        XCTAssertNotNil(range)
        XCTAssertEqual(String(sql[range!]), "*")
    }

    func testSimpleColumnList() {
        let sql = "SELECT a, b, c FROM table1"
        let range = SQLTokenizer.selectColumnListRange(in: sql)
        XCTAssertNotNil(range)
        XCTAssertEqual(String(sql[range!]), "a, b, c")
    }

    func testSelectDistinct() {
        let sql = "SELECT DISTINCT a, b FROM table1"
        let range = SQLTokenizer.selectColumnListRange(in: sql)
        XCTAssertNotNil(range)
        XCTAssertEqual(String(sql[range!]), "a, b")
    }

    func testCaseInsensitiveKeywords() {
        let sql = "select a, b from table1"
        let range = SQLTokenizer.selectColumnListRange(in: sql)
        XCTAssertNotNil(range)
        XCTAssertEqual(String(sql[range!]), "a, b")
    }

    func testQuotedColumnNames() {
        let sql = #"SELECT "my col", "other" FROM table1"#
        let range = SQLTokenizer.selectColumnListRange(in: sql)
        XCTAssertNotNil(range)
        XCTAssertEqual(String(sql[range!]), #""my col", "other""#)
    }

    func testSubqueryInSelect() {
        let sql = "SELECT (SELECT count(*) FROM other), col FROM main"
        let range = SQLTokenizer.selectColumnListRange(in: sql)
        XCTAssertNotNil(range)
        // Should capture everything up to the top-level FROM
        XCTAssertEqual(String(sql[range!]), "(SELECT count(*) FROM other), col")
    }

    func testStringLiteralContainingFROM() {
        let sql = "SELECT 'from' AS label FROM table1"
        let range = SQLTokenizer.selectColumnListRange(in: sql)
        XCTAssertNotNil(range)
        XCTAssertEqual(String(sql[range!]), "'from' AS label")
    }

    func testFunctionCallsInSelect() {
        let sql = "SELECT COALESCE(a, b), UPPER(c) FROM table1"
        let range = SQLTokenizer.selectColumnListRange(in: sql)
        XCTAssertNotNil(range)
        XCTAssertEqual(String(sql[range!]), "COALESCE(a, b), UPPER(c)")
    }

    func testNestedSubqueries() {
        let sql = "SELECT (SELECT MAX(x) FROM (SELECT 1 AS x FROM dual)) FROM t"
        let range = SQLTokenizer.selectColumnListRange(in: sql)
        XCTAssertNotNil(range)
        XCTAssertEqual(String(sql[range!]), "(SELECT MAX(x) FROM (SELECT 1 AS x FROM dual))")
    }

    func testCommentBeforeFROM() {
        let sql = "SELECT a, b /* columns */ FROM table1"
        let range = SQLTokenizer.selectColumnListRange(in: sql)
        XCTAssertNotNil(range)
        // Column list should not include the trailing comment
        XCTAssertEqual(String(sql[range!]), "a, b")
    }

    func testLineCommentContainingFROM() {
        let sql = "SELECT a -- FROM fake\n, b FROM table1"
        let range = SQLTokenizer.selectColumnListRange(in: sql)
        XCTAssertNotNil(range)
        XCTAssertEqual(String(sql[range!]), "a -- FROM fake\n, b")
    }

    func testNoFROMReturnsNil() {
        let sql = "SELECT a, b, c"
        let range = SQLTokenizer.selectColumnListRange(in: sql)
        XCTAssertNil(range)
    }

    func testNoSELECTReturnsNil() {
        let sql = "INSERT INTO t VALUES (1, 2)"
        let range = SQLTokenizer.selectColumnListRange(in: sql)
        XCTAssertNil(range)
    }

    func testEmptyStringReturnsNil() {
        let range = SQLTokenizer.selectColumnListRange(in: "")
        XCTAssertNil(range)
    }

    func testLeadingWhitespace() {
        let sql = "  SELECT a, b FROM table1"
        let range = SQLTokenizer.selectColumnListRange(in: sql)
        XCTAssertNotNil(range)
        XCTAssertEqual(String(sql[range!]), "a, b")
    }

    func testFullQueryWithWhereOrderLimit() {
        let sql = #"SELECT "p_timestamp", "msg" FROM "logs" WHERE level = 'error' ORDER BY "p_timestamp" DESC LIMIT 1000"#
        let range = SQLTokenizer.selectColumnListRange(in: sql)
        XCTAssertNotNil(range)
        XCTAssertEqual(String(sql[range!]), #""p_timestamp", "msg""#)
    }

    func testReplacementRoundTrip() {
        let sql = "SELECT a, b, c FROM table1 ORDER BY a"
        guard let range = SQLTokenizer.selectColumnListRange(in: sql) else {
            XCTFail("Expected range")
            return
        }
        var modified = sql
        modified.replaceSubrange(range, with: #""x", "y""#)
        XCTAssertEqual(modified, #"SELECT "x", "y" FROM table1 ORDER BY a"#)
    }

    func testReplacementWithStar() {
        let sql = #"SELECT "a", "b" FROM table1"#
        guard let range = SQLTokenizer.selectColumnListRange(in: sql) else {
            XCTFail("Expected range")
            return
        }
        var modified = sql
        modified.replaceSubrange(range, with: "*")
        XCTAssertEqual(modified, "SELECT * FROM table1")
    }

    func testQuotedIdentifierContainingFROM() {
        let sql = #"SELECT "from" FROM table1"#
        let range = SQLTokenizer.selectColumnListRange(in: sql)
        XCTAssertNotNil(range)
        XCTAssertEqual(String(sql[range!]), #""from""#)
    }

    // MARK: - SQLErrorPosition.parse

    func testParseDataFusionError() {
        let msg = "Expected: an expression, found: FROM at Line: 1, Column 15"
        let pos = SQLErrorPosition.parse(from: msg)
        XCTAssertEqual(pos, SQLErrorPosition(line: 1, column: 15))
    }

    func testParseDataFusionErrorWithColonAfterColumn() {
        let msg = "Error at Line: 2, Column: 10"
        let pos = SQLErrorPosition.parse(from: msg)
        XCTAssertEqual(pos, SQLErrorPosition(line: 2, column: 10))
    }

    func testParseReturnsNilForNoPosition() {
        let msg = "Some generic error without position info"
        XCTAssertNil(SQLErrorPosition.parse(from: msg))
    }

    func testParseReturnsNilForEmptyString() {
        XCTAssertNil(SQLErrorPosition.parse(from: ""))
    }

    // MARK: - characterOffset

    func testCharacterOffsetSingleLine() {
        let sql = "SELECT * FROM t"
        // Line 1, Column 8 → offset 7 (the '*')
        XCTAssertEqual(SQLTokenizer.characterOffset(line: 1, column: 8, in: sql), 7)
    }

    func testCharacterOffsetMultiLine() {
        let sql = "SELECT *\nFROM t"
        // Line 2, Column 1 → offset 9 (the 'F' of FROM)
        XCTAssertEqual(SQLTokenizer.characterOffset(line: 2, column: 1, in: sql), 9)
    }

    func testCharacterOffsetLineBeyondEnd() {
        let sql = "SELECT *"
        XCTAssertNil(SQLTokenizer.characterOffset(line: 3, column: 1, in: sql))
    }

    func testCharacterOffsetColumnBeyondEnd() {
        let sql = "SELECT *"
        // Column 100 on a short string
        XCTAssertNil(SQLTokenizer.characterOffset(line: 1, column: 100, in: sql))
    }

    // MARK: - tokenRange

    func testTokenRangeAtKeyword() {
        let sql = "SELEC * FROM t"
        // Offset 0 is at the start of "SELEC" (which is an identifier, not a keyword)
        let range = SQLTokenizer.tokenRange(atOffset: 0, in: sql)
        XCTAssertNotNil(range)
        XCTAssertEqual((sql as NSString).substring(with: range!), "SELEC")
    }

    func testTokenRangeAtWhitespaceSnapsToNextToken() {
        let sql = "SELECT  * FROM t"
        // Offset 6 is inside the whitespace between SELECT and *
        let range = SQLTokenizer.tokenRange(atOffset: 7, in: sql)
        XCTAssertNotNil(range)
        XCTAssertEqual((sql as NSString).substring(with: range!), "*")
    }

    func testTokenRangeAtIdentifier() {
        let sql = "SELECT * FROM mytable"
        // Offset 14 is at 'm' of "mytable"
        let range = SQLTokenizer.tokenRange(atOffset: 14, in: sql)
        XCTAssertNotNil(range)
        XCTAssertEqual((sql as NSString).substring(with: range!), "mytable")
    }

    // MARK: - errorHighlightRange (end-to-end)

    func testErrorHighlightRangeTypoInKeyword() {
        let sql = "SELEC * FROM t"
        // DataFusion would report Line: 1, Column 1 for SELEC
        let range = SQLTokenizer.errorHighlightRange(line: 1, column: 1, in: sql)
        XCTAssertNotNil(range)
        XCTAssertEqual((sql as NSString).substring(with: range!), "SELEC")
    }

    func testErrorHighlightRangeMultiLine() {
        let sql = "SELECT *\nFRO t"
        // Line 2, Column 1 → "FRO"
        let range = SQLTokenizer.errorHighlightRange(line: 2, column: 1, in: sql)
        XCTAssertNotNil(range)
        XCTAssertEqual((sql as NSString).substring(with: range!), "FRO")
    }

    func testErrorHighlightRangeInvalidPosition() {
        let sql = "SELECT * FROM t"
        XCTAssertNil(SQLTokenizer.errorHighlightRange(line: 99, column: 1, in: sql))
    }
}
