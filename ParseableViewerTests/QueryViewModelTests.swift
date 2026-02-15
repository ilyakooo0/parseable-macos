import XCTest
@testable import ParseableViewer

final class QueryViewModelTests: XCTestCase {
    // MARK: - Column extraction

    func testExtractColumnsOrdersPriorityFieldsFirst() {
        let vm = QueryViewModel()
        let records: [LogRecord] = [
            [
                "custom_field": .string("val"),
                "message": .string("hello"),
                "p_timestamp": .string("2024-01-01"),
                "level": .string("info"),
                "zebra": .string("z")
            ]
        ]

        // Simulate the column extraction by running a query with mock data
        // Since we can't easily mock the client, test the public interface
        // by verifying filteredResults and columns after setting them directly
        vm.results = records
        vm.columns = vm.extractColumns(from: records)

        // Priority fields should come first
        XCTAssertEqual(vm.columns[0], "p_timestamp")
        XCTAssertEqual(vm.columns[1], "level")
        XCTAssertEqual(vm.columns[2], "message")

        // Remaining fields sorted alphabetically
        let remaining = Array(vm.columns.dropFirst(3))
        XCTAssertEqual(remaining, remaining.sorted())
    }

    func testExtractColumnsEmpty() {
        let vm = QueryViewModel()
        let cols = vm.extractColumns(from: [])
        XCTAssertTrue(cols.isEmpty)
    }

    func testExtractColumnsMergesAcrossRecords() {
        let vm = QueryViewModel()
        let records: [LogRecord] = [
            ["a": .int(1), "b": .int(2)],
            ["b": .int(3), "c": .int(4)]
        ]
        let cols = vm.extractColumns(from: records)
        XCTAssertEqual(Set(cols), Set(["a", "b", "c"]))
        XCTAssertEqual(cols.count, 3) // no duplicates
    }

    // MARK: - Filtered results

    func testFilteredResultsEmptyFilter() {
        let vm = QueryViewModel()
        vm.results = [
            ["message": .string("hello")],
            ["message": .string("world")]
        ]
        vm.filterText = ""
        XCTAssertEqual(vm.filteredResults.count, 2)
    }

    func testFilteredResultsMatchesContent() {
        let vm = QueryViewModel()
        vm.results = [
            ["message": .string("hello world")],
            ["message": .string("goodbye moon")],
            ["message": .string("Hello there")]
        ]
        vm.filterText = "hello"
        XCTAssertEqual(vm.filteredResults.count, 2) // case-insensitive
    }

    func testFilteredResultsNoMatch() {
        let vm = QueryViewModel()
        vm.results = [
            ["message": .string("hello")],
            ["message": .string("world")]
        ]
        vm.filterText = "xyz"
        XCTAssertEqual(vm.filteredResults.count, 0)
    }

    // MARK: - CSV export

    func testExportCSVBasic() {
        let vm = QueryViewModel()
        vm.results = [
            ["name": .string("Alice"), "age": .int(30)],
            ["name": .string("Bob"), "age": .int(25)]
        ]
        vm.columns = ["name", "age"]
        let csv = vm.exportAsCSV()

        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 3) // header + 2 rows
        XCTAssertEqual(lines[0], "name,age")
        XCTAssertEqual(lines[1], "Alice,30")
        XCTAssertEqual(lines[2], "Bob,25")
    }

    func testExportCSVEscaping() {
        let vm = QueryViewModel()
        vm.results = [
            ["msg": .string("hello, world"), "note": .string("has \"quotes\"")]
        ]
        vm.columns = ["msg", "note"]
        let csv = vm.exportAsCSV()

        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[1].contains("\"hello, world\""))
        XCTAssertTrue(lines[1].contains("\"has \"\"quotes\"\"\""))
    }

    func testExportCSVEmpty() {
        let vm = QueryViewModel()
        XCTAssertEqual(vm.exportAsCSV(), "")
    }

    // MARK: - JSON export

    func testExportJSONEmpty() {
        let vm = QueryViewModel()
        XCTAssertEqual(vm.exportAsJSON(), "[]")
    }

    func testExportJSONNotEmpty() {
        let vm = QueryViewModel()
        vm.results = [["key": .string("value")]]
        let json = vm.exportAsJSON()
        XCTAssertTrue(json.contains("\"key\""))
        XCTAssertTrue(json.contains("\"value\""))
    }

    // MARK: - Time range

    func testTimeRangeOptionsAllHaveValues() {
        for option in QueryViewModel.TimeRangeOption.allCases {
            let range = option.dateRange()
            XCTAssertLessThanOrEqual(range.start, range.end, "Option \(option.rawValue) has invalid range")
        }
    }

    func testTimeRangePresets() {
        let now = Date()
        let fiveMin = QueryViewModel.TimeRangeOption.last5Min.dateRange()
        let diff = now.timeIntervalSince(fiveMin.start)
        // Should be roughly 5 minutes (300 seconds) +/- 2 seconds for test execution time
        XCTAssertTrue(abs(diff - 300) < 2, "Last 5 min diff was \(diff)")
    }

    // MARK: - Query history

    func testSetDefaultQuery() {
        let vm = QueryViewModel()
        vm.setDefaultQuery(stream: "test_stream")
        XCTAssertTrue(vm.sqlQuery.contains("test_stream"))
        XCTAssertTrue(vm.sqlQuery.contains("SELECT"))
    }

    func testSetDefaultQueryDoesNotOverwrite() {
        let vm = QueryViewModel()
        vm.sqlQuery = "SELECT 1"
        vm.setDefaultQuery(stream: "test_stream")
        XCTAssertEqual(vm.sqlQuery, "SELECT 1")
    }
}

