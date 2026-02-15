import XCTest
import SwiftUI
@testable import ParseableViewer

final class LogTableHelperTests: XCTestCase {
    // MARK: - idealColumnWidth

    func testIdealColumnWidthRespectsMinimum() {
        // A very short column name with no records should still meet the minimum width (50).
        let width = idealColumnWidth(for: "x", records: [])
        XCTAssertGreaterThanOrEqual(width, 50)
    }

    func testIdealColumnWidthRespectsMaximum() {
        // A record with extremely long content should be capped at 600.
        let longString = String(repeating: "A", count: 2000)
        let records: [LogRecord] = [["wide": .string(longString)]]
        let width = idealColumnWidth(for: "wide", records: records)
        XCTAssertLessThanOrEqual(width, 600)
    }

    func testIdealColumnWidthGrowsWithContent() {
        let shortRecords: [LogRecord] = [["col": .string("hi")]]
        let longRecords: [LogRecord] = [["col": .string("a much longer cell value here")]]
        let shortWidth = idealColumnWidth(for: "col", records: shortRecords)
        let longWidth = idealColumnWidth(for: "col", records: longRecords)
        XCTAssertLessThan(shortWidth, longWidth)
    }

    func testIdealColumnWidthConsidersHeaderName() {
        // A long column name should produce a wider column even with no records.
        let shortHeader = idealColumnWidth(for: "id", records: [])
        let longHeader = idealColumnWidth(for: "a_very_long_column_name_here", records: [])
        XCTAssertLessThan(shortHeader, longHeader)
    }

    // MARK: - computeColumnWidths

    func testComputeColumnWidthsReturnsAllColumns() {
        let columns = ["a", "b", "c"]
        let records: [LogRecord] = [["a": .string("x"), "b": .int(1), "c": .null]]
        let widths = computeColumnWidths(columns: columns, records: records)
        XCTAssertEqual(Set(widths.keys), Set(columns))
    }

    func testComputeColumnWidthsEmptyRecords() {
        let columns = ["col1", "col2"]
        let widths = computeColumnWidths(columns: columns, records: [])
        // Should still return widths based on header names
        XCTAssertEqual(widths.count, 2)
        for (_, width) in widths {
            XCTAssertGreaterThanOrEqual(width, 50)
        }
    }

    // MARK: - levelColor

    func testLevelColorError() {
        XCTAssertEqual(levelColor(for: "error"), .red)
        XCTAssertEqual(levelColor(for: "ERROR"), .red)
        XCTAssertEqual(levelColor(for: "fatal"), .red)
        XCTAssertEqual(levelColor(for: "CRITICAL"), .red)
        XCTAssertEqual(levelColor(for: "panic"), .red)
    }

    func testLevelColorWarn() {
        XCTAssertEqual(levelColor(for: "warn"), .orange)
        XCTAssertEqual(levelColor(for: "WARNING"), .orange)
    }

    func testLevelColorInfo() {
        XCTAssertEqual(levelColor(for: "info"), .blue)
        XCTAssertEqual(levelColor(for: "INFO"), .blue)
    }

    func testLevelColorDebug() {
        XCTAssertEqual(levelColor(for: "debug"), .secondary)
        XCTAssertEqual(levelColor(for: "TRACE"), .secondary)
    }

    func testLevelColorDefault() {
        XCTAssertEqual(levelColor(for: "unknown"), .primary)
        XCTAssertEqual(levelColor(for: ""), .primary)
    }

    // MARK: - parseSeverity

    func testParseSeverityFatal() {
        XCTAssertEqual(parseSeverity(from: "fatal"), .fatal)
        XCTAssertEqual(parseSeverity(from: "CRITICAL"), .fatal)
        XCTAssertEqual(parseSeverity(from: "panic"), .fatal)
        XCTAssertEqual(parseSeverity(from: "emerg"), .fatal)
        XCTAssertEqual(parseSeverity(from: "EMERGENCY"), .fatal)
        XCTAssertEqual(parseSeverity(from: "alert"), .fatal)
        XCTAssertEqual(parseSeverity(from: "crit"), .fatal)
    }

    func testParseSeverityError() {
        XCTAssertEqual(parseSeverity(from: "error"), .error)
        XCTAssertEqual(parseSeverity(from: "ERROR"), .error)
        XCTAssertEqual(parseSeverity(from: "err"), .error)
        XCTAssertEqual(parseSeverity(from: "failure"), .error)
        XCTAssertEqual(parseSeverity(from: "FAIL"), .error)
        XCTAssertEqual(parseSeverity(from: "severe"), .error)
    }

    func testParseSeverityWarning() {
        XCTAssertEqual(parseSeverity(from: "warn"), .warning)
        XCTAssertEqual(parseSeverity(from: "WARNING"), .warning)
        XCTAssertEqual(parseSeverity(from: "caution"), .warning)
    }

    func testParseSeverityInfo() {
        XCTAssertEqual(parseSeverity(from: "info"), .info)
        XCTAssertEqual(parseSeverity(from: "INFO"), .info)
        XCTAssertEqual(parseSeverity(from: "information"), .info)
        XCTAssertEqual(parseSeverity(from: "informational"), .info)
        XCTAssertEqual(parseSeverity(from: "notice"), .info)
    }

    func testParseSeverityDebug() {
        XCTAssertEqual(parseSeverity(from: "debug"), .debug)
        XCTAssertEqual(parseSeverity(from: "DEBUG"), .debug)
        XCTAssertEqual(parseSeverity(from: "dbg"), .debug)
        XCTAssertEqual(parseSeverity(from: "verbose"), .debug)
    }

    func testParseSeverityTrace() {
        XCTAssertEqual(parseSeverity(from: "trace"), .trace)
        XCTAssertEqual(parseSeverity(from: "TRACE"), .trace)
        XCTAssertEqual(parseSeverity(from: "finest"), .trace)
        XCTAssertEqual(parseSeverity(from: "finer"), .trace)
        XCTAssertEqual(parseSeverity(from: "fine"), .trace)
        XCTAssertEqual(parseSeverity(from: "all"), .trace)
    }

    func testParseSeverityNumericSyslog() {
        // RFC 5424 severity codes
        XCTAssertEqual(parseSeverity(from: "0"), .fatal)   // Emergency
        XCTAssertEqual(parseSeverity(from: "1"), .fatal)   // Alert
        XCTAssertEqual(parseSeverity(from: "2"), .fatal)   // Critical
        XCTAssertEqual(parseSeverity(from: "3"), .error)   // Error
        XCTAssertEqual(parseSeverity(from: "4"), .warning) // Warning
        XCTAssertEqual(parseSeverity(from: "5"), .info)    // Notice
        XCTAssertEqual(parseSeverity(from: "6"), .info)    // Informational
        XCTAssertEqual(parseSeverity(from: "7"), .debug)   // Debug
    }

    func testParseSeverityUnknown() {
        XCTAssertEqual(parseSeverity(from: ""), .unknown)
        XCTAssertEqual(parseSeverity(from: "something"), .unknown)
        XCTAssertEqual(parseSeverity(from: "99"), .unknown)
    }

    func testParseSeverityWhitespace() {
        XCTAssertEqual(parseSeverity(from: "  error  "), .error)
        XCTAssertEqual(parseSeverity(from: " WARN "), .warning)
    }

    // MARK: - extractSeverity

    func testExtractSeverityFromLevelColumn() {
        let record: LogRecord = ["level": .string("error"), "message": .string("boom")]
        XCTAssertEqual(extractSeverity(from: record), .error)
    }

    func testExtractSeverityFromSeverityColumn() {
        let record: LogRecord = ["severity": .string("warning"), "msg": .string("watch out")]
        XCTAssertEqual(extractSeverity(from: record), .warning)
    }

    func testExtractSeverityFromSeverityTextColumn() {
        let record: LogRecord = ["severity_text": .string("FATAL")]
        XCTAssertEqual(extractSeverity(from: record), .fatal)
    }

    func testExtractSeverityFromLogLevelColumn() {
        let record: LogRecord = ["log_level": .string("info")]
        XCTAssertEqual(extractSeverity(from: record), .info)
    }

    func testExtractSeverityFromNumericValue() {
        let record: LogRecord = ["priority": .int(3)]
        XCTAssertEqual(extractSeverity(from: record), .error)
    }

    func testExtractSeverityNoSeverityColumn() {
        let record: LogRecord = ["message": .string("hello"), "timestamp": .string("now")]
        XCTAssertEqual(extractSeverity(from: record), .unknown)
    }

    func testExtractSeverityUnrecognizedValue() {
        let record: LogRecord = ["level": .string("custom_level")]
        XCTAssertEqual(extractSeverity(from: record), .unknown)
    }

    // MARK: - severityRowTint

    func testSeverityRowTintFatalReturnsColor() {
        XCTAssertNotNil(severityRowTint(for: .fatal))
    }

    func testSeverityRowTintErrorReturnsColor() {
        XCTAssertNotNil(severityRowTint(for: .error))
    }

    func testSeverityRowTintWarningReturnsColor() {
        XCTAssertNotNil(severityRowTint(for: .warning))
    }

    func testSeverityRowTintInfoReturnsNil() {
        XCTAssertNil(severityRowTint(for: .info))
    }

    func testSeverityRowTintDebugReturnsNil() {
        XCTAssertNil(severityRowTint(for: .debug))
    }

    func testSeverityRowTintTraceReturnsNil() {
        XCTAssertNil(severityRowTint(for: .trace))
    }

    func testSeverityRowTintUnknownReturnsNil() {
        XCTAssertNil(severityRowTint(for: .unknown))
    }
}
