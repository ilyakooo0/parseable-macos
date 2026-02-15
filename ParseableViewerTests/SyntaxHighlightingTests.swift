@testable import ParseableViewer
import XCTest
import AppKit

final class SyntaxHighlightingTests: XCTestCase {

    // MARK: - Helpers

    private let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    private func sqlHighlight(_ sql: String) -> NSTextStorage {
        let ts = NSTextStorage(string: sql)
        SQLSyntaxHighlighter.highlight(sql, in: ts, baseFont: font)
        return ts
    }

    private func colorAt(_ ts: NSTextStorage, _ index: Int) -> NSColor? {
        ts.attributes(at: index, effectiveRange: nil)[.foregroundColor] as? NSColor
    }

    // MARK: - SQL: Keywords

    func testSQLKeywordsAreHighlighted() {
        let ts = sqlHighlight("SELECT * FROM logs")
        // SELECT (index 0) and FROM (index 9) should not be default label color
        let selectColor = colorAt(ts, 0)
        let logsColor = colorAt(ts, 14) // "logs" is plain identifier
        XCTAssertNotEqual(selectColor, logsColor,
                          "Keyword 'SELECT' should be a different color than identifier 'logs'")

        let fromColor = colorAt(ts, 9)
        XCTAssertEqual(selectColor, fromColor,
                       "'SELECT' and 'FROM' should share the same keyword color")
    }

    func testSQLKeywordsAreCaseInsensitive() {
        let ts = sqlHighlight("select * from logs")
        let selectColor = colorAt(ts, 0)
        let logsColor = colorAt(ts, 14)
        XCTAssertNotEqual(selectColor, logsColor)
    }

    func testSQLKeywordsAreBolded() {
        let ts = sqlHighlight("SELECT x")
        let attrs = ts.attributes(at: 0, effectiveRange: nil)
        let usedFont = attrs[.font] as? NSFont
        XCTAssertNotNil(usedFont)
        // Bold font has weight >= .bold
        let traits = usedFont!.fontDescriptor.symbolicTraits
        XCTAssertTrue(traits.contains(.bold), "Keywords should be bold")
    }

    // MARK: - SQL: Strings

    func testSQLSingleQuotedStringsHighlighted() {
        let sql = "WHERE msg = 'hello'"
        let ts = sqlHighlight(sql)
        let stringStart = (sql as NSString).range(of: "'hello'").location
        let stringColor = colorAt(ts, stringStart)
        let whereColor = colorAt(ts, 0) // WHERE keyword
        XCTAssertNotEqual(stringColor, whereColor,
                          "String literal should be a different color than keywords")
    }

    func testSQLKeywordsInsideStringsAreNotHighlightedAsKeywords() {
        let sql = "WHERE msg = 'SELECT FROM'"
        let ts = sqlHighlight(sql)
        let innerIdx = (sql as NSString).range(of: "'SELECT FROM'").location
        let stringColor = colorAt(ts, innerIdx)
        // The entire string should have the same color as its opening quote
        let innerKeywordIdx = innerIdx + 1 // 'S' in SELECT inside string
        let innerColor = colorAt(ts, innerKeywordIdx)
        XCTAssertEqual(stringColor, innerColor,
                       "Keywords inside strings should be colored as string, not as keyword")
    }

    // MARK: - SQL: Numbers

    func testSQLNumbersHighlighted() {
        let sql = "LIMIT 100"
        let ts = sqlHighlight(sql)
        let numIdx = (sql as NSString).range(of: "100").location
        let numColor = colorAt(ts, numIdx)
        let keyColor = colorAt(ts, 0)
        XCTAssertNotEqual(numColor, keyColor,
                          "Numbers should be a different color than keywords")
    }

    // MARK: - SQL: Comments

    func testSQLLineComments() {
        let sql = "SELECT * -- a comment\nFROM logs"
        let ts = sqlHighlight(sql)
        let commentIdx = (sql as NSString).range(of: "--").location
        let commentColor = colorAt(ts, commentIdx)
        let fromIdx = (sql as NSString).range(of: "FROM").location
        let fromColor = colorAt(ts, fromIdx)
        XCTAssertNotEqual(commentColor, fromColor,
                          "Comment color should differ from keyword color")
    }

    func testSQLKeywordsInsideCommentsNotHighlighted() {
        let sql = "-- SELECT FROM WHERE"
        let ts = sqlHighlight(sql)
        // All characters should share the comment color
        let dashColor = colorAt(ts, 0)
        let selectIdx = (sql as NSString).range(of: "SELECT").location
        let selectColor = colorAt(ts, selectIdx)
        XCTAssertEqual(dashColor, selectColor,
                       "Keywords inside comments should not be highlighted as keywords")
    }

    // MARK: - SQL: Functions

    func testSQLFunctionsHighlighted() {
        let sql = "SELECT COUNT(*) FROM logs"
        let ts = sqlHighlight(sql)
        let countIdx = (sql as NSString).range(of: "COUNT").location
        let countColor = colorAt(ts, countIdx)
        let selectColor = colorAt(ts, 0)
        XCTAssertNotEqual(countColor, selectColor,
                          "Functions should be a different color than keywords")
    }

    // MARK: - SQL: Edge Cases

    func testSQLEmptyString() {
        let ts = NSTextStorage(string: "")
        SQLSyntaxHighlighter.highlight("", in: ts, baseFont: font)
        XCTAssertEqual(ts.length, 0)
    }

    func testSQLDoubleQuotedIdentifiers() {
        let sql = "SELECT \"my column\" FROM logs"
        let ts = sqlHighlight(sql)
        let quoteIdx = (sql as NSString).range(of: "\"my column\"").location
        let quoteColor = colorAt(ts, quoteIdx)
        let selectColor = colorAt(ts, 0)
        XCTAssertNotEqual(quoteColor, selectColor,
                          "Double-quoted identifiers should differ from keywords")
    }

    // MARK: - JSON Highlighting

    func testJSONHighlightProducesOutput() {
        let json = "{\"key\": \"value\", \"n\": 42}"
        let result = JSONSyntaxHighlighter.highlight(json)
        XCTAssertFalse(result.characters.isEmpty)
    }

    func testJSONHighlightEmptyString() {
        let result = JSONSyntaxHighlighter.highlight("")
        XCTAssertTrue(result.characters.isEmpty)
    }

    func testJSONKeysAndValuesHaveDifferentColors() {
        let json = "{\"name\": \"Alice\"}"
        let result = JSONSyntaxHighlighter.highlight(json)
        let ns = NSAttributedString(result)

        let keyIdx = (json as NSString).range(of: "\"name\"").location
        let valueIdx = (json as NSString).range(of: "\"Alice\"").location

        let keyColor = ns.attributes(at: keyIdx, effectiveRange: nil)[.foregroundColor] as? NSColor
        let valueColor = ns.attributes(at: valueIdx, effectiveRange: nil)[.foregroundColor] as? NSColor

        XCTAssertNotNil(keyColor)
        XCTAssertNotNil(valueColor)
        XCTAssertNotEqual(keyColor, valueColor,
                          "JSON keys and string values should have different colors")
    }

    func testJSONBooleansHighlighted() {
        let json = "{\"flag\": true}"
        let result = JSONSyntaxHighlighter.highlight(json)
        let ns = NSAttributedString(result)

        let boolIdx = (json as NSString).range(of: "true").location
        let boolColor = ns.attributes(at: boolIdx, effectiveRange: nil)[.foregroundColor] as? NSColor
        // Should not be default label color
        XCTAssertNotEqual(boolColor, NSColor.labelColor,
                          "Booleans should be highlighted")
    }

    func testJSONNullHighlighted() {
        let json = "{\"x\": null}"
        let result = JSONSyntaxHighlighter.highlight(json)
        let ns = NSAttributedString(result)

        let nullIdx = (json as NSString).range(of: "null").location
        let nullColor = ns.attributes(at: nullIdx, effectiveRange: nil)[.foregroundColor] as? NSColor
        XCTAssertNotEqual(nullColor, NSColor.labelColor,
                          "Null should be highlighted")
    }

    func testJSONNumbersHighlighted() {
        let json = "{\"count\": 42}"
        let result = JSONSyntaxHighlighter.highlight(json)
        let ns = NSAttributedString(result)

        let numIdx = (json as NSString).range(of: "42").location
        let numColor = ns.attributes(at: numIdx, effectiveRange: nil)[.foregroundColor] as? NSColor
        XCTAssertNotEqual(numColor, NSColor.labelColor,
                          "Numbers should be highlighted")
    }

    func testJSONNestedStructure() {
        let json = """
        {
          "user": {
            "name": "Bob",
            "age": 30,
            "active": true,
            "address": null
          }
        }
        """
        // Should not crash on nested JSON
        let result = JSONSyntaxHighlighter.highlight(json)
        XCTAssertFalse(result.characters.isEmpty)
    }
}
