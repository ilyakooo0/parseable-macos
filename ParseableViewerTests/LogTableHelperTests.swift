import XCTest
import SwiftUI
@testable import ParseableViewer

final class LogTableHelperTests: XCTestCase {
    // MARK: - columnWidth

    func testColumnWidthTimestampFields() {
        XCTAssertEqual(columnWidth(for: "p_timestamp"), 200)
        XCTAssertEqual(columnWidth(for: "timestamp"), 200)
        XCTAssertEqual(columnWidth(for: "@timestamp"), 200)
        XCTAssertEqual(columnWidth(for: "time"), 200)
    }

    func testColumnWidthLevelFields() {
        XCTAssertEqual(columnWidth(for: "level"), 80)
        XCTAssertEqual(columnWidth(for: "severity"), 80)
        XCTAssertEqual(columnWidth(for: "log_level"), 80)
    }

    func testColumnWidthMessageFields() {
        XCTAssertEqual(columnWidth(for: "message"), 400)
        XCTAssertEqual(columnWidth(for: "msg"), 400)
        XCTAssertEqual(columnWidth(for: "body"), 400)
        XCTAssertEqual(columnWidth(for: "log"), 400)
    }

    func testColumnWidthDefault() {
        XCTAssertEqual(columnWidth(for: "custom_field"), 160)
        XCTAssertEqual(columnWidth(for: "unknown"), 160)
        XCTAssertEqual(columnWidth(for: ""), 160)
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
}
