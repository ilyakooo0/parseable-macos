import XCTest
@testable import ParseableViewer

@MainActor
final class LiveTailViewModelTests: XCTestCase {
    // MARK: - Fingerprinting

    func testFingerprintDeterministic() {
        let record: LogRecord = [
            "message": .string("hello"),
            "level": .string("info")
        ]
        let fp1 = LiveTailViewModel.fingerprint(for: record)
        let fp2 = LiveTailViewModel.fingerprint(for: record)
        XCTAssertEqual(fp1, fp2)
    }

    func testFingerprintDifferentForDifferentRecords() {
        let record1: LogRecord = ["message": .string("hello")]
        let record2: LogRecord = ["message": .string("world")]
        let fp1 = LiveTailViewModel.fingerprint(for: record1)
        let fp2 = LiveTailViewModel.fingerprint(for: record2)
        XCTAssertNotEqual(fp1, fp2)
    }

    func testFingerprintOrderIndependent() {
        // Records with same keys/values in different insertion order should produce same fingerprint
        // since fingerprint sorts keys
        let record1: LogRecord = ["a": .string("1"), "b": .string("2")]
        let record2: LogRecord = ["b": .string("2"), "a": .string("1")]
        let fp1 = LiveTailViewModel.fingerprint(for: record1)
        let fp2 = LiveTailViewModel.fingerprint(for: record2)
        XCTAssertEqual(fp1, fp2)
    }

    func testFingerprintEmptyRecord() {
        let record: LogRecord = [:]
        let fp = LiveTailViewModel.fingerprint(for: record)
        XCTAssertFalse(fp.isEmpty)
    }

    func testFingerprintDistinguishesKeyFromValue() {
        // Ensure "a"="b" and "ab"="" produce different fingerprints
        let record1: LogRecord = ["a": .string("b")]
        let record2: LogRecord = ["ab": .string("")]
        let fp1 = LiveTailViewModel.fingerprint(for: record1)
        let fp2 = LiveTailViewModel.fingerprint(for: record2)
        XCTAssertNotEqual(fp1, fp2)
    }

    func testFingerprintHandlesNullValues() {
        let record: LogRecord = ["key": .null]
        let fp = LiveTailViewModel.fingerprint(for: record)
        XCTAssertFalse(fp.isEmpty)
    }

    func testFingerprintHandlesNestedValues() {
        let record: LogRecord = ["data": .object(["nested": .string("value")])]
        let fp = LiveTailViewModel.fingerprint(for: record)
        XCTAssertFalse(fp.isEmpty)
    }

    // MARK: - Timestamp parsing

    func testParseTimestampISO8601WithFractionalSeconds() {
        let vm = LiveTailViewModel()
        let record: LogRecord = ["p_timestamp": .string("2024-06-15T10:30:45.123Z")]
        let date = vm.parseTimestamp(from: record)
        XCTAssertNotNil(date)
    }

    func testParseTimestampISO8601Basic() {
        let vm = LiveTailViewModel()
        let record: LogRecord = ["p_timestamp": .string("2024-06-15T10:30:45Z")]
        let date = vm.parseTimestamp(from: record)
        XCTAssertNotNil(date)
    }

    func testParseTimestampFallbackFields() {
        let vm = LiveTailViewModel()

        // "timestamp" field
        let r1: LogRecord = ["timestamp": .string("2024-06-15T10:30:45Z")]
        XCTAssertNotNil(vm.parseTimestamp(from: r1))

        // "time" field
        let r2: LogRecord = ["time": .string("2024-06-15T10:30:45Z")]
        XCTAssertNotNil(vm.parseTimestamp(from: r2))

        // "@timestamp" field
        let r3: LogRecord = ["@timestamp": .string("2024-06-15T10:30:45Z")]
        XCTAssertNotNil(vm.parseTimestamp(from: r3))
    }

    func testParseTimestampPriorityOrder() {
        let vm = LiveTailViewModel()
        // p_timestamp should take priority
        let record: LogRecord = [
            "p_timestamp": .string("2024-01-01T00:00:00Z"),
            "timestamp": .string("2024-12-31T23:59:59Z")
        ]
        let date = vm.parseTimestamp(from: record)
        XCTAssertNotNil(date)

        let calendar = Calendar.current
        let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: date!)
        XCTAssertEqual(components.year, 2024)
        XCTAssertEqual(components.month, 1)
    }

    func testParseTimestampNoTimestampField() {
        let vm = LiveTailViewModel()
        let record: LogRecord = ["message": .string("no timestamp")]
        let date = vm.parseTimestamp(from: record)
        XCTAssertNil(date)
    }

    func testParseTimestampNonStringValue() {
        let vm = LiveTailViewModel()
        let record: LogRecord = ["p_timestamp": .int(1718446245)]
        let date = vm.parseTimestamp(from: record)
        XCTAssertNil(date)
    }

    func testParseTimestampInvalidString() {
        let vm = LiveTailViewModel()
        let record: LogRecord = ["p_timestamp": .string("not-a-date")]
        let date = vm.parseTimestamp(from: record)
        XCTAssertNil(date)
    }

    // MARK: - Summary building

    func testBuildSummaryWithLevelAndMessage() {
        let vm = LiveTailViewModel()
        let record: LogRecord = [
            "level": .string("info"),
            "message": .string("Server started")
        ]
        let summary = vm.buildSummary(from: record)
        XCTAssertTrue(summary.contains("[info]"))
        XCTAssertTrue(summary.contains("Server started"))
    }

    func testBuildSummaryAlternateFieldNames() {
        let vm = LiveTailViewModel()
        let record: LogRecord = [
            "severity": .string("warn"),
            "msg": .string("Disk almost full")
        ]
        let summary = vm.buildSummary(from: record)
        XCTAssertTrue(summary.contains("[warn]"))
        XCTAssertTrue(summary.contains("Disk almost full"))
    }

    func testBuildSummaryFallbackToScalarFields() {
        let vm = LiveTailViewModel()
        let record: LogRecord = [
            "status": .int(200),
            "path": .string("/api/health")
        ]
        let summary = vm.buildSummary(from: record)
        XCTAssertFalse(summary.isEmpty)
    }

    func testBuildSummaryEmptyRecord() {
        let vm = LiveTailViewModel()
        let record: LogRecord = [:]
        let summary = vm.buildSummary(from: record)
        XCTAssertEqual(summary, "")
    }

    // MARK: - ViewModel state

    func testInitialState() {
        let vm = LiveTailViewModel()
        XCTAssertFalse(vm.isRunning)
        XCTAssertFalse(vm.isPaused)
        XCTAssertTrue(vm.entries.isEmpty)
        XCTAssertEqual(vm.droppedCount, 0)
        XCTAssertNil(vm.lastPollTime)
        XCTAssertNil(vm.errorMessage)
    }

    func testStartWithoutClientIsNoOp() {
        let vm = LiveTailViewModel()
        vm.start(client: nil, stream: "test")
        XCTAssertFalse(vm.isRunning)
    }

    func testStartWithoutStreamIsNoOp() {
        let connection = ServerConnection(name: "test", url: "https://example.com", username: "u", password: "p")
        let client = try? ParseableClient(connection: connection)
        let vm = LiveTailViewModel()
        vm.start(client: client, stream: nil)
        XCTAssertFalse(vm.isRunning)
    }

    func testTogglePause() {
        let vm = LiveTailViewModel()
        XCTAssertFalse(vm.isPaused)
        vm.togglePause()
        XCTAssertTrue(vm.isPaused)
        vm.togglePause()
        XCTAssertFalse(vm.isPaused)
    }

    func testClearResetsState() {
        let vm = LiveTailViewModel()
        vm.droppedCount = 42
        vm.clear()
        XCTAssertTrue(vm.entries.isEmpty)
        XCTAssertEqual(vm.droppedCount, 0)
    }

    func testFilteredEntriesEmptyFilter() {
        let vm = LiveTailViewModel()
        vm.filterText = ""
        XCTAssertEqual(vm.filteredEntries.count, vm.entries.count)
    }

    func testStopResetsRunningState() {
        let connection = ServerConnection(name: "test", url: "https://example.com", username: "u", password: "p")
        let client = try? ParseableClient(connection: connection)
        let vm = LiveTailViewModel()
        vm.start(client: client, stream: "test-stream")
        XCTAssertTrue(vm.isRunning)
        vm.stop()
        XCTAssertFalse(vm.isRunning)
        XCTAssertFalse(vm.isPaused)
    }

    func testStartTwiceIsNoOp() {
        let connection = ServerConnection(name: "test", url: "https://example.com", username: "u", password: "p")
        let client = try? ParseableClient(connection: connection)
        let vm = LiveTailViewModel()
        vm.start(client: client, stream: "test-stream")
        XCTAssertTrue(vm.isRunning)
        // Starting again while running should be a no-op
        vm.start(client: client, stream: "other-stream")
        XCTAssertTrue(vm.isRunning)
        vm.stop()
    }

    func testDisplayedCountMatchesFilteredEntries() {
        let vm = LiveTailViewModel()
        XCTAssertEqual(vm.displayedCount, 0)
        XCTAssertEqual(vm.entryCount, 0)
    }
}
