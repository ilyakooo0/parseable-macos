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
        vm.columnOrder = ["name", "age"]
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
        vm.columnOrder = ["msg", "note"]
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

    // MARK: - Query cancellation

    @MainActor
    func testCancelQuerySetsState() {
        let vm = QueryViewModel()
        // Simulate loading state
        vm.isLoading = true
        vm.cancelQuery()
        XCTAssertFalse(vm.isLoading)
        XCTAssertEqual(vm.errorMessage, "Query cancelled")
    }

    @MainActor
    func testCancelQueryWhenNotLoading() {
        let vm = QueryViewModel()
        vm.cancelQuery()
        // Should still set the message but not crash
        XCTAssertFalse(vm.isLoading)
        XCTAssertEqual(vm.errorMessage, "Query cancelled")
    }

    // MARK: - Default query uses escaped identifiers

    func testSetDefaultQueryEscapesStreamName() {
        let vm = QueryViewModel()
        vm.setDefaultQuery(stream: "my-stream")
        XCTAssertTrue(vm.sqlQuery.contains("\"my-stream\""))
    }

    func testSetDefaultQueryEscapesQuotesInStreamName() {
        let vm = QueryViewModel()
        vm.setDefaultQuery(stream: "stream\"name")
        XCTAssertTrue(vm.sqlQuery.contains("\"stream\"\"name\""))
    }

    // MARK: - Column filter

    func testAddColumnFilterIncludeStringValue() {
        let vm = QueryViewModel()
        vm.sqlQuery = "SELECT * FROM \"logs\" ORDER BY p_timestamp DESC LIMIT 1000"
        vm.addColumnFilter(column: "level", value: .string("error"), exclude: false)
        XCTAssertTrue(vm.sqlQuery.contains("WHERE \"level\" = 'error'"))
        XCTAssertTrue(vm.sqlQuery.contains("ORDER BY"))
    }

    func testAddColumnFilterExcludeStringValue() {
        let vm = QueryViewModel()
        vm.sqlQuery = "SELECT * FROM \"logs\" ORDER BY p_timestamp DESC LIMIT 1000"
        vm.addColumnFilter(column: "level", value: .string("debug"), exclude: true)
        XCTAssertTrue(vm.sqlQuery.contains("WHERE \"level\" <> 'debug'"))
        XCTAssertTrue(vm.sqlQuery.contains("ORDER BY"))
    }

    func testAddColumnFilterNullValue() {
        let vm = QueryViewModel()
        vm.sqlQuery = "SELECT * FROM \"logs\" ORDER BY p_timestamp DESC"
        vm.addColumnFilter(column: "tag", value: nil, exclude: false)
        XCTAssertTrue(vm.sqlQuery.contains("WHERE \"tag\" IS NULL"))
    }

    func testAddColumnFilterExcludeNullValue() {
        let vm = QueryViewModel()
        vm.sqlQuery = "SELECT * FROM \"logs\" ORDER BY p_timestamp DESC"
        vm.addColumnFilter(column: "tag", value: .null, exclude: true)
        XCTAssertTrue(vm.sqlQuery.contains("WHERE \"tag\" IS NOT NULL"))
    }

    func testAddColumnFilterAppendsToExistingWhere() {
        let vm = QueryViewModel()
        vm.sqlQuery = "SELECT * FROM \"logs\" WHERE \"level\" = 'error' ORDER BY p_timestamp DESC"
        vm.addColumnFilter(column: "host", value: .string("web-1"), exclude: false)
        XCTAssertTrue(vm.sqlQuery.contains("AND \"host\" = 'web-1'"))
        XCTAssertTrue(vm.sqlQuery.contains("WHERE \"level\" = 'error'"))
    }

    func testAddColumnFilterIntValue() {
        let vm = QueryViewModel()
        vm.sqlQuery = "SELECT * FROM \"logs\""
        vm.addColumnFilter(column: "status", value: .int(200), exclude: false)
        XCTAssertTrue(vm.sqlQuery.contains("WHERE \"status\" = 200"))
    }

    func testAddColumnFilterNoOpOnEmptyQuery() {
        let vm = QueryViewModel()
        vm.sqlQuery = ""
        vm.addColumnFilter(column: "level", value: .string("info"), exclude: false)
        XCTAssertEqual(vm.sqlQuery, "")
    }

    func testAddColumnFilterQueryWithoutOrderBy() {
        let vm = QueryViewModel()
        vm.sqlQuery = "SELECT * FROM \"logs\""
        vm.addColumnFilter(column: "level", value: .string("warn"), exclude: true)
        XCTAssertTrue(vm.sqlQuery.contains("WHERE \"level\" <> 'warn'"))
    }

    func testAddColumnFilterEscapesSingleQuotesInValue() {
        let vm = QueryViewModel()
        vm.sqlQuery = "SELECT * FROM \"logs\""
        vm.addColumnFilter(column: "msg", value: .string("it's a test"), exclude: false)
        XCTAssertTrue(vm.sqlQuery.contains("'it''s a test'"))
    }

    // MARK: - Column visibility

    func testVisibleColumnsExcludesHidden() {
        let vm = QueryViewModel()
        vm.columns = ["a", "b", "c"]
        vm.columnOrder = ["a", "b", "c"]
        vm.hiddenColumns = ["b"]
        XCTAssertEqual(vm.visibleColumns, ["a", "c"])
    }

    func testToggleColumnVisibilityHidesColumn() {
        let vm = QueryViewModel()
        vm.columns = ["a", "b", "c"]
        vm.columnOrder = ["a", "b", "c"]
        vm.toggleColumnVisibility("b")
        XCTAssertTrue(vm.hiddenColumns.contains("b"))
        XCTAssertEqual(vm.visibleColumns, ["a", "c"])
    }

    func testToggleColumnVisibilityShowsColumn() {
        let vm = QueryViewModel()
        vm.columns = ["a", "b", "c"]
        vm.columnOrder = ["a", "b", "c"]
        vm.hiddenColumns = ["b"]
        vm.toggleColumnVisibility("b")
        XCTAssertFalse(vm.hiddenColumns.contains("b"))
        XCTAssertEqual(vm.visibleColumns, ["a", "b", "c"])
    }

    func testCannotHideAllColumns() {
        let vm = QueryViewModel()
        vm.columns = ["a", "b"]
        vm.columnOrder = ["a", "b"]
        vm.toggleColumnVisibility("a")
        XCTAssertTrue(vm.hiddenColumns.contains("a"))
        // Trying to hide the last visible column should be prevented
        vm.toggleColumnVisibility("b")
        XCTAssertFalse(vm.hiddenColumns.contains("b"))
        XCTAssertEqual(vm.visibleColumns, ["b"])
    }

    func testShowAllColumns() {
        let vm = QueryViewModel()
        vm.columns = ["a", "b", "c"]
        vm.columnOrder = ["a", "b", "c"]
        vm.hiddenColumns = ["a", "b"]
        vm.showAllColumns()
        XCTAssertTrue(vm.hiddenColumns.isEmpty)
        XCTAssertEqual(vm.visibleColumns, ["a", "b", "c"])
    }

    // MARK: - Column reordering

    func testMoveColumnByName() {
        let vm = QueryViewModel()
        vm.columns = ["a", "b", "c"]
        vm.columnOrder = ["a", "b", "c"]
        vm.moveColumn("c", to: "a")
        XCTAssertEqual(vm.columnOrder, ["c", "a", "b"])
    }

    func testMoveColumnByIndexSet() {
        let vm = QueryViewModel()
        vm.columns = ["a", "b", "c"]
        vm.columnOrder = ["a", "b", "c"]
        vm.moveColumn(from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(vm.columnOrder, ["c", "a", "b"])
    }

    func testResetColumnConfig() {
        let vm = QueryViewModel()
        vm.columns = ["a", "b", "c"]
        vm.columnOrder = ["c", "b", "a"]
        vm.hiddenColumns = ["b"]
        vm.resetColumnConfig()
        XCTAssertEqual(vm.columnOrder, ["a", "b", "c"])
        XCTAssertTrue(vm.hiddenColumns.isEmpty)
    }

    func testVisibleColumnsRespectsOrder() {
        let vm = QueryViewModel()
        vm.columns = ["a", "b", "c"]
        vm.columnOrder = ["c", "a", "b"]
        vm.hiddenColumns = ["a"]
        XCTAssertEqual(vm.visibleColumns, ["c", "b"])
    }

    // MARK: - Column config persistence

    func testApplyColumnConfigWithNoSavedConfig() {
        let vm = QueryViewModel()
        vm.applyColumnConfig(extractedColumns: ["x", "y", "z"], stream: nil)
        XCTAssertEqual(vm.columns, ["x", "y", "z"])
        XCTAssertEqual(vm.columnOrder, ["x", "y", "z"])
        XCTAssertTrue(vm.hiddenColumns.isEmpty)
    }

    func testApplyColumnConfigMergesNewColumns() {
        let vm = QueryViewModel()
        // Save a config for "test_stream"
        let config = QueryViewModel.ColumnConfiguration(order: ["b", "a"], hidden: ["a"])
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: "parseable_column_config_test_stream")
        }

        // Apply with new columns that include an extra column "c"
        vm.applyColumnConfig(extractedColumns: ["a", "b", "c"], stream: "test_stream")
        XCTAssertEqual(vm.columnOrder, ["b", "a", "c"]) // saved order preserved, new "c" appended
        XCTAssertEqual(vm.hiddenColumns, ["a"]) // saved hidden preserved

        // Clean up
        UserDefaults.standard.removeObject(forKey: "parseable_column_config_test_stream")
    }

    func testApplyColumnConfigRemovesStaleSavedColumns() {
        let vm = QueryViewModel()
        // Save a config with a column that no longer exists
        let config = QueryViewModel.ColumnConfiguration(order: ["old", "a", "b"], hidden: ["old"])
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: "parseable_column_config_test_stream2")
        }

        vm.applyColumnConfig(extractedColumns: ["a", "b"], stream: "test_stream2")
        XCTAssertEqual(vm.columnOrder, ["a", "b"]) // "old" removed
        XCTAssertTrue(vm.hiddenColumns.isEmpty) // "old" was hidden but no longer exists

        // Clean up
        UserDefaults.standard.removeObject(forKey: "parseable_column_config_test_stream2")
    }

    func testClearResultsResetsColumnState() {
        let vm = QueryViewModel()
        vm.columns = ["a", "b"]
        vm.columnOrder = ["b", "a"]
        vm.hiddenColumns = ["a"]
        vm.clearResults()
        XCTAssertTrue(vm.columns.isEmpty)
        XCTAssertTrue(vm.columnOrder.isEmpty)
        XCTAssertTrue(vm.hiddenColumns.isEmpty)
    }

    func testCSVExportUsesVisibleColumns() {
        let vm = QueryViewModel()
        vm.results = [
            ["name": .string("Alice"), "age": .int(30), "secret": .string("hidden")],
        ]
        vm.columns = ["name", "age", "secret"]
        vm.columnOrder = ["name", "age", "secret"]
        vm.hiddenColumns = ["secret"]
        let csv = vm.exportAsCSV()

        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines[0], "name,age")
        XCTAssertFalse(csv.contains("secret"))
        XCTAssertFalse(csv.contains("hidden"))
    }

    // MARK: - Empty column detection

    func testEmptyColumnsDetectsAllNulls() {
        let vm = QueryViewModel()
        let records: [LogRecord] = [
            ["a": .string("val"), "b": .null],
            ["a": .string("val2"), "b": .null],
        ]
        let empty = vm.emptyColumns(in: records, columns: ["a", "b"])
        XCTAssertEqual(empty, ["b"])
    }

    func testEmptyColumnsDetectsMissingKeys() {
        let vm = QueryViewModel()
        let records: [LogRecord] = [
            ["a": .string("val")],
            ["a": .string("val2")],
        ]
        let empty = vm.emptyColumns(in: records, columns: ["a", "b"])
        XCTAssertEqual(empty, ["b"])
    }

    func testEmptyColumnsDetectsEmptyStrings() {
        let vm = QueryViewModel()
        let records: [LogRecord] = [
            ["a": .string("val"), "b": .string("")],
            ["a": .string("val2"), "b": .string("")],
        ]
        let empty = vm.emptyColumns(in: records, columns: ["a", "b"])
        XCTAssertEqual(empty, ["b"])
    }

    func testEmptyColumnsMixedNullAndMissing() {
        let vm = QueryViewModel()
        let records: [LogRecord] = [
            ["a": .string("val"), "b": .null],
            ["a": .string("val2")],
            ["a": .string("val3"), "b": .string("")],
        ]
        let empty = vm.emptyColumns(in: records, columns: ["a", "b"])
        XCTAssertEqual(empty, ["b"])
    }

    func testEmptyColumnsNotEmptyIfAnyRecordHasValue() {
        let vm = QueryViewModel()
        let records: [LogRecord] = [
            ["a": .string("val"), "b": .null],
            ["a": .string("val2"), "b": .string("data")],
        ]
        let empty = vm.emptyColumns(in: records, columns: ["a", "b"])
        XCTAssertTrue(empty.isEmpty)
    }

    func testEmptyColumnsNoRecords() {
        let vm = QueryViewModel()
        let empty = vm.emptyColumns(in: [], columns: ["a", "b"])
        XCTAssertEqual(empty, ["a", "b"])
    }

    func testEmptyColumnsNoColumns() {
        let vm = QueryViewModel()
        let records: [LogRecord] = [["a": .string("val")]]
        let empty = vm.emptyColumns(in: records, columns: [])
        XCTAssertTrue(empty.isEmpty)
    }

    func testAutoHiddenColumnsExcludedFromVisibleColumns() {
        let vm = QueryViewModel()
        vm.columns = ["a", "b", "c"]
        vm.columnOrder = ["a", "b", "c"]
        vm.autoHiddenColumns = ["b"]
        XCTAssertEqual(vm.visibleColumns, ["a", "c"])
    }

    func testToggleAutoHiddenColumnShowsIt() {
        let vm = QueryViewModel()
        vm.columns = ["a", "b", "c"]
        vm.columnOrder = ["a", "b", "c"]
        vm.autoHiddenColumns = ["b"]
        vm.toggleColumnVisibility("b")
        XCTAssertFalse(vm.autoHiddenColumns.contains("b"))
        XCTAssertEqual(vm.visibleColumns, ["a", "b", "c"])
    }

    func testShowAllColumnsClearsAutoHidden() {
        let vm = QueryViewModel()
        vm.columns = ["a", "b", "c"]
        vm.columnOrder = ["a", "b", "c"]
        vm.hiddenColumns = ["a"]
        vm.autoHiddenColumns = ["b"]
        vm.showAllColumns()
        XCTAssertTrue(vm.hiddenColumns.isEmpty)
        XCTAssertTrue(vm.autoHiddenColumns.isEmpty)
        XCTAssertEqual(vm.visibleColumns, ["a", "b", "c"])
    }

    func testResetColumnConfigClearsAutoHidden() {
        let vm = QueryViewModel()
        vm.columns = ["a", "b", "c"]
        vm.columnOrder = ["c", "b", "a"]
        vm.autoHiddenColumns = ["b"]
        vm.resetColumnConfig()
        XCTAssertEqual(vm.columnOrder, ["a", "b", "c"])
        XCTAssertTrue(vm.autoHiddenColumns.isEmpty)
    }

    func testClearResultsClearsAutoHidden() {
        let vm = QueryViewModel()
        vm.columns = ["a", "b"]
        vm.columnOrder = ["a", "b"]
        vm.autoHiddenColumns = ["b"]
        vm.clearResults()
        XCTAssertTrue(vm.autoHiddenColumns.isEmpty)
    }

    func testCSVExportExcludesAutoHiddenColumns() {
        let vm = QueryViewModel()
        vm.results = [
            ["name": .string("Alice"), "age": .int(30), "empty_col": .null],
        ]
        vm.columns = ["name", "age", "empty_col"]
        vm.columnOrder = ["name", "age", "empty_col"]
        vm.autoHiddenColumns = ["empty_col"]
        let csv = vm.exportAsCSV()

        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines[0], "name,age")
        XCTAssertFalse(csv.contains("empty_col"))
    }

    func testBoolZeroValuesNotTreatedAsEmpty() {
        let vm = QueryViewModel()
        let records: [LogRecord] = [
            ["a": .bool(false)],
            ["a": .int(0)],
        ]
        let empty = vm.emptyColumns(in: records, columns: ["a"])
        XCTAssertTrue(empty.isEmpty)
    }
}

