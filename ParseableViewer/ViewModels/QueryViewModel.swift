import Foundation
import SwiftUI

@Observable
final class QueryViewModel {
    var sqlQuery = "" {
        didSet {
            // Editing the query invalidates any error underline, whose offsets
            // were computed against the previous text. Clearing here keeps a
            // late-arriving highlight from landing on the wrong position.
            if sqlQuery != oldValue { errorRange = nil }
        }
    }
    var results: [LogRecord] = [] {
        didSet {
            // Build search texts asynchronously
            searchTextTask?.cancel()
            cachedSearchTexts = []
            // Apply the current filter immediately using the inline fallback path
            // (the cache was just invalidated). Calling updateFilteredResults()
            // rather than `filteredResults = results` avoids briefly showing
            // unfiltered rows while a filter is active, and avoids leaving a stale
            // unfiltered set if the async rebuild below is cancelled before it
            // re-applies the filter.
            updateFilteredResults()
            let snapshot = results
            searchTextTask = Task {
                let texts = snapshot.map { record in
                    record.values.map { $0.displayString }.joined(separator: " ")
                }
                guard !Task.isCancelled else { return }
                cachedSearchTexts = texts
                if !filterText.isEmpty {
                    updateFilteredResults()
                }
            }
        }
    }
    private var cachedSearchTexts: [String] = []
    private var searchTextTask: Task<Void, Never>?
    var columns: [String] = []
    var columnOrder: [String] = []
    var hiddenColumns: Set<String> = []
    var autoHiddenColumns: Set<String> = []
    /// Column config from a saved query, applied on next query execution.
    var pendingColumnConfig: ColumnConfiguration?
    private var currentStream: String?
    var isLoading = false
    var errorMessage: String?
    var errorRange: NSRange?
    var resultCount = 0
    var queryDuration: TimeInterval?
    var selectedLogEntry: LogRecord?
    var filterText = "" {
        didSet { debouncedUpdateFilter() }
    }
    private var filterTask: Task<Void, Never>?
    var resultsTruncated = false

    // Schema fields for autocomplete
    var schemaFields: [SchemaField] = []
    /// The stream of the most recent `loadSchema` call, used to drop a stale
    /// in-flight response when the user rapidly switches streams.
    private var latestSchemaStream: String?

    // Query task for cancellation
    private var queryTask: Task<Void, Never>?

    // Time range
    var timeRangeOption: TimeRangeOption = .last1Hour
    var customStartDate = Calendar.current.date(byAdding: .hour, value: -1, to: Date()) ?? Date()
    var customEndDate = Date()

    // Query history
    var queryHistory: [QueryHistoryEntry] = []
    var historyIsFull = false
    private static let maxHistory = 50

    struct QueryHistoryEntry: Identifiable, Codable, Sendable {
        let id: UUID
        let sql: String
        let executedAt: Date
        let resultCount: Int
        let duration: TimeInterval

        init(sql: String, resultCount: Int, duration: TimeInterval) {
            self.id = UUID()
            self.sql = sql
            self.executedAt = Date()
            self.resultCount = resultCount
            self.duration = duration
        }
    }

    enum TimeRangeOption: String, CaseIterable, Identifiable {
        case last5Min = "Last 5 minutes"
        case last15Min = "Last 15 minutes"
        case last30Min = "Last 30 minutes"
        case last1Hour = "Last 1 hour"
        case last6Hours = "Last 6 hours"
        case last24Hours = "Last 24 hours"
        case last7Days = "Last 7 days"
        case last30Days = "Last 30 days"
        case custom = "Custom"

        var id: String { rawValue }

        /// Key used in UserDefaults / SettingsView @AppStorage for persistence.
        var settingsKey: String {
            switch self {
            case .last5Min: return "last5Min"
            case .last15Min: return "last15Min"
            case .last30Min: return "last30Min"
            case .last1Hour: return "last1Hour"
            case .last6Hours: return "last6Hours"
            case .last24Hours: return "last24Hours"
            case .last7Days: return "last7Days"
            case .last30Days: return "last30Days"
            case .custom: return "custom"
            }
        }

        func dateRange() -> (start: Date, end: Date) {
            let now = Date()
            let cal = Calendar.current
            let start: Date
            switch self {
            case .last5Min: start = cal.date(byAdding: .minute, value: -5, to: now) ?? now
            case .last15Min: start = cal.date(byAdding: .minute, value: -15, to: now) ?? now
            case .last30Min: start = cal.date(byAdding: .minute, value: -30, to: now) ?? now
            case .last1Hour: start = cal.date(byAdding: .hour, value: -1, to: now) ?? now
            case .last6Hours: start = cal.date(byAdding: .hour, value: -6, to: now) ?? now
            case .last24Hours: start = cal.date(byAdding: .hour, value: -24, to: now) ?? now
            case .last7Days: start = cal.date(byAdding: .day, value: -7, to: now) ?? now
            case .last30Days: start = cal.date(byAdding: .day, value: -30, to: now) ?? now
            case .custom: start = now
            }
            return (start, now)
        }
    }

    var startDate: Date {
        if timeRangeOption == .custom {
            return customStartDate
        }
        return timeRangeOption.dateRange().start
    }

    var endDate: Date {
        if timeRangeOption == .custom {
            return customEndDate
        }
        return timeRangeOption.dateRange().end
    }

    var visibleColumns: [String] {
        let allHidden = hiddenColumns.union(autoHiddenColumns)
        return columnOrder.filter { !allHidden.contains($0) }
    }

    func toggleColumnVisibility(_ column: String) {
        if hiddenColumns.contains(column) {
            hiddenColumns.remove(column)
        } else if autoHiddenColumns.contains(column) {
            autoHiddenColumns.remove(column)
        } else {
            // Don't allow hiding all columns
            let allHidden = hiddenColumns.union(autoHiddenColumns)
            let visibleCount = columnOrder.count - allHidden.count
            if visibleCount > 1 {
                hiddenColumns.insert(column)
            }
        }
        saveColumnConfig()
        updateSQLColumns()
    }

    func showAllColumns() {
        hiddenColumns.removeAll()
        autoHiddenColumns.removeAll()
        saveColumnConfig()
        updateSQLColumns()
    }

    func moveColumn(from source: IndexSet, to destination: Int) {
        columnOrder.move(fromOffsets: source, toOffset: destination)
        saveColumnConfig()
        updateSQLColumns()
    }

    func moveColumn(_ column: String, to targetColumn: String) {
        guard let fromIndex = columnOrder.firstIndex(of: column),
              let toIndex = columnOrder.firstIndex(of: targetColumn),
              fromIndex != toIndex else { return }
        let item = columnOrder.remove(at: fromIndex)
        // Removing an element before the target shifts the target down by one, so
        // inserting at the original `toIndex` would land the column past its target.
        let adjusted = fromIndex < toIndex ? toIndex - 1 : toIndex
        columnOrder.insert(item, at: adjusted)
        saveColumnConfig()
        updateSQLColumns()
    }

    func resetColumnConfig() {
        columnOrder = columns
        hiddenColumns.removeAll()
        autoHiddenColumns.removeAll()
        saveColumnConfig()
        updateSQLColumns()
    }

    /// Rewrites the SELECT clause of `sqlQuery` to reflect the current `visibleColumns`.
    func updateSQLColumns() {
        guard let range = SQLTokenizer.selectColumnListRange(in: sqlQuery) else { return }

        let visible = visibleColumns
        guard !visible.isEmpty else { return }

        let newColumnList: String
        // Use `*` whenever every column is visible, regardless of display order —
        // reordering columns (a set-preserving permutation) must not pin the query
        // to an explicit snapshot that hides newly-appearing fields on re-query.
        if visible.count == columns.count && Set(visible) == Set(columns) {
            newColumnList = "*"
        } else {
            newColumnList = visible.map { Self.escapeSQLIdentifier($0) }.joined(separator: ", ")
        }

        sqlQuery.replaceSubrange(range, with: newColumnList)
    }

    // MARK: - Column Configuration Persistence

    struct ColumnConfiguration: Codable {
        var order: [String]
        var hidden: Set<String>
    }

    private static func columnConfigKey(for stream: String) -> String {
        "parseable_column_config_\(stream)"
    }

    private func saveColumnConfig() {
        guard let stream = currentStream else { return }
        let config = ColumnConfiguration(order: columnOrder, hidden: hiddenColumns)
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: Self.columnConfigKey(for: stream))
        }
    }

    static func loadColumnConfig(for stream: String) -> ColumnConfiguration? {
        guard let data = UserDefaults.standard.data(forKey: columnConfigKey(for: stream)) else { return nil }
        return try? JSONDecoder().decode(ColumnConfiguration.self, from: data)
    }

    func applyColumnConfig(extractedColumns: [String], stream: String?) {
        columns = extractedColumns
        currentStream = stream

        // Use pending config (from a saved query) if available,
        // otherwise fall back to the per-stream default.
        let config: ColumnConfiguration?
        if let pending = pendingColumnConfig {
            config = pending
            pendingColumnConfig = nil
        } else if let stream {
            config = Self.loadColumnConfig(for: stream)
        } else {
            config = nil
        }

        guard let config else {
            columnOrder = extractedColumns
            hiddenColumns = []
            return
        }

        // Merge saved order with actual columns: keep saved order for columns
        // that still exist, then append any new columns at the end
        let extractedSet = Set(extractedColumns)
        var merged = config.order.filter { extractedSet.contains($0) }
        let mergedSet = Set(merged)
        for col in extractedColumns where !mergedSet.contains(col) {
            merged.append(col)
        }
        columnOrder = merged
        hiddenColumns = config.hidden.intersection(extractedSet)
    }

    private(set) var filteredResults: [LogRecord] = []

    private func debouncedUpdateFilter() {
        filterTask?.cancel()
        if filterText.isEmpty {
            updateFilteredResults()
            return
        }
        filterTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            updateFilteredResults()
        }
    }

    private func updateFilteredResults() {
        if filterText.isEmpty {
            filteredResults = results
        } else {
            let text = filterText
            // The search-text cache is built asynchronously, so it may be empty
            // or stale when the filter changes. `zip` would silently truncate to
            // the shorter sequence and drop matching rows, so only use the cache
            // when it lines up with the current results; otherwise compute the
            // search text inline for correctness.
            if cachedSearchTexts.count == results.count {
                filteredResults = zip(results, cachedSearchTexts).compactMap { record, searchText in
                    searchText.localizedCaseInsensitiveContains(text) ? record : nil
                }
            } else {
                filteredResults = results.filter { record in
                    record.values
                        .map { $0.displayString }
                        .joined(separator: " ")
                        .localizedCaseInsensitiveContains(text)
                }
            }
        }
    }

    private var queryLimit: Int {
        let stored = UserDefaults.standard.integer(forKey: "maxQueryResults")
        guard stored > 0 else { return 1000 }
        return min(stored, 100_000)
    }

    init() {
        queryHistory = Self.loadHistory()
        // Apply the default time range from settings
        if let stored = UserDefaults.standard.string(forKey: "defaultTimeRange"),
           let option = TimeRangeOption.allCases.first(where: { $0.settingsKey == stored }) {
            timeRangeOption = option
        }
    }

    @MainActor
    func executeQuery(client: ParseableClient?, stream: String?) async {
        guard let client else {
            errorMessage = "Not connected to server"
            return
        }

        let limit = queryLimit
        let sql: String
        let usedAutoLimit: Bool
        if sqlQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let stream else {
                errorMessage = "Select a stream or enter a SQL query"
                return
            }
            sql = "SELECT * FROM \(Self.escapeSQLIdentifier(stream)) ORDER BY p_timestamp DESC LIMIT \(limit)"
            usedAutoLimit = true
        } else {
            sql = sqlQuery
            usedAutoLimit = false
        }

        // Cancel any in-flight query
        queryTask?.cancel()

        isLoading = true
        errorMessage = nil
        errorRange = nil
        resultsTruncated = false
        let startTime = CFAbsoluteTimeGetCurrent()

        let task = Task {
            do {
                try Task.checkCancellation()
                let queryResults = try await client.query(sql: sql, startTime: startDate, endTime: endDate)
                try Task.checkCancellation()
                // Re-check before committing. A superseding executeQuery() cancels
                // this task (queryTask?.cancel()) before starting the next one, but
                // cancellation landing just after the check above would otherwise
                // let a stale query clobber the newer one's results/columns.
                guard !Task.isCancelled else { return }

                results = queryResults
                queryDuration = CFAbsoluteTimeGetCurrent() - startTime
                resultCount = results.count

                // Detect if results were likely truncated (only meaningful
                // for auto-generated queries where we control the LIMIT)
                resultsTruncated = usedAutoLimit && results.count == limit

                // Extract columns in a single pass, with priority fields first,
                // then apply any saved column configuration for this stream
                let extracted = extractColumns(from: results)
                applyColumnConfig(extractedColumns: extracted, stream: stream)

                // Auto-hide columns that have no values in any row.
                // Clear first so stale state from a previous query doesn't
                // interfere with the visible-count check.
                autoHiddenColumns = []
                let empty = emptyColumns(in: results, columns: columnOrder)
                let candidates = empty.subtracting(hiddenColumns)
                let visibleCount = columnOrder.count - hiddenColumns.count
                // Ensure at least one column remains visible
                if candidates.count < visibleCount {
                    autoHiddenColumns = candidates
                }

                // Record in history
                let entry = QueryHistoryEntry(sql: sql, resultCount: resultCount, duration: queryDuration ?? 0)
                addToHistory(entry)
            } catch is CancellationError {
                // Silently ignore — cancelQuery() or a new executeQuery() handles state
                return
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = ParseableError.userFriendlyMessage(for: error)
                if let serverError = error as? ParseableError,
                   case .serverError(_, let msg) = serverError,
                   let pos = SQLErrorPosition.parse(from: msg) {
                    errorRange = SQLTokenizer.errorHighlightRange(
                        line: pos.line, column: pos.column, in: sqlQuery
                    )
                }
                results = []
                columns = []
                // Drop the previous query's column layout too, otherwise derived
                // state like `visibleColumns` (and a CSV export reading it) would
                // report stale column names after the failure.
                columnOrder = []
                hiddenColumns = []
                autoHiddenColumns = []
            }

            isLoading = false
        }
        queryTask = task
        await task.value
    }

    @MainActor
    func cancelQuery() {
        queryTask?.cancel()
        queryTask = nil
        isLoading = false
        errorMessage = "Query cancelled"
        errorRange = nil
    }

    @MainActor
    func loadSchema(client: ParseableClient?, stream: String?) async {
        latestSchemaStream = stream
        guard let client, let stream else {
            schemaFields = []
            return
        }
        do {
            let schema = try await client.getStreamSchema(stream: stream)
            // A newer load (e.g. a rapid stream switch) may have superseded this
            // one; only commit if this is still the stream last requested,
            // otherwise we'd show the wrong stream's fields in autocomplete.
            guard latestSchemaStream == stream else { return }
            schemaFields = schema.fields
        } catch {
            guard latestSchemaStream == stream else { return }
            // Schema load is best-effort; don't surface errors
            schemaFields = []
        }
    }

    /// Single-pass column extraction with priority ordering.
    func extractColumns(from records: [LogRecord]) -> [String] {
        let priorityFields = ["p_timestamp", "p_tags", "p_metadata", "level", "severity", "message", "msg"]
        var allKeys = Set<String>()
        for record in records {
            allKeys.formUnion(record.keys)
        }

        var ordered: [String] = []
        for field in priorityFields {
            if allKeys.remove(field) != nil {
                ordered.append(field)
            }
        }
        ordered.append(contentsOf: allKeys.sorted())
        return ordered
    }

    /// Returns the set of columns that have no meaningful value in any record.
    /// A value is considered empty if it is missing (nil), `.null`, or `.string("")`.
    func emptyColumns(in records: [LogRecord], columns: [String]) -> Set<String> {
        var empty = Set(columns)
        for record in records {
            if empty.isEmpty { break }
            // Iterate a snapshot: mutating `empty` while iterating it directly
            // is undefined behavior and can skip elements or trap.
            for column in Array(empty) {
                if let value = record[column], value != .null, value != .string("") {
                    empty.remove(column)
                }
            }
        }
        return empty
    }

    func exportAsJSON() -> String {
        guard !results.isEmpty else { return "[]" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(Self.projectRecords(results, to: visibleColumns)),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return "[]"
    }

    func exportAsCSV() -> String {
        Self.buildCSV(records: results, columns: visibleColumns)
    }

    /// Projects each record down to the given columns so JSON export, like CSV,
    /// respects hidden columns instead of leaking every field. Safe to call from
    /// any thread.
    static func projectRecords(_ records: [LogRecord], to columns: [String]) -> [LogRecord] {
        // No column list means no restriction (columns not computed yet) — export
        // the full records rather than stripping every field to an empty object.
        guard !columns.isEmpty else { return records }
        let allowed = Set(columns)
        return records.map { record in record.filter { allowed.contains($0.key) } }
    }

    /// Builds a CSV string from records and columns. Safe to call from any thread.
    static func buildCSV(records: [LogRecord], columns: [String]) -> String {
        guard !records.isEmpty, !columns.isEmpty else { return "" }

        var csv = String()
        csv.reserveCapacity(columns.count * 50 * (records.count + 1))

        // Header
        for (i, col) in columns.enumerated() {
            if i > 0 { csv.append(",") }
            csv.append(escapeCSV(col))
        }
        csv.append("\n")

        // Rows
        for record in records {
            for (i, column) in columns.enumerated() {
                if i > 0 { csv.append(",") }
                let value = record[column]?.exportString ?? ""
                csv.append(escapeCSV(value))
            }
            csv.append("\n")
        }

        return csv
    }

    private static func escapeCSV(_ value: String) -> String {
        // Check at the Unicode scalar level to correctly detect \r and \n
        // inside \r\n (CRLF) grapheme clusters, which Swift's String.contains
        // treats as a single Character that doesn't match "\r" or "\n" alone.
        let needsQuoting = value.unicodeScalars.contains { scalar in
            scalar == "," || scalar == "\"" || scalar == "\n" || scalar == "\r"
        }
        if needsQuoting {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    func clearResults() {
        // Cancel any in-flight work first. Without this, a query still running
        // when the user switches streams or disconnects would pass its post-await
        // cancellation check (it was never cancelled) and write its results +
        // persist a column config for the *old* stream after this reset.
        queryTask?.cancel()
        queryTask = nil
        searchTextTask?.cancel()
        searchTextTask = nil
        filterTask?.cancel()
        filterTask = nil

        // The in-flight query was cancelled above, so its task returns via the
        // CancellationError path and never reaches `isLoading = false`. Reset it
        // here, otherwise deselecting the stream / disconnecting (which calls
        // clearResults with no follow-up query) leaves the spinner stuck on.
        isLoading = false

        results = []
        columns = []
        columnOrder = []
        hiddenColumns = []
        autoHiddenColumns = []
        currentStream = nil
        resultCount = 0
        queryDuration = nil
        selectedLogEntry = nil
        errorMessage = nil
        errorRange = nil
        resultsTruncated = false
        schemaFields = []
    }

    /// Modifies `sqlQuery` to add a column-value filter condition.
    /// When `exclude` is true, the condition excludes the value; otherwise it includes only matching rows.
    func addColumnFilter(column: String, value: JSONValue?, exclude: Bool) {
        let escapedCol = Self.escapeSQLIdentifier(column)
        let condition: String
        if let value, value != .null {
            let literal = value.sqlLiteral
            condition = exclude ? "\(escapedCol) <> \(literal)" : "\(escapedCol) = \(literal)"
        } else {
            condition = exclude ? "\(escapedCol) IS NOT NULL" : "\(escapedCol) IS NULL"
        }

        var sql = sqlQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if sql.isEmpty { return }

        // Locate the top-level WHERE and the first trailing clause using the
        // tokenizer rather than a raw regex, so keywords inside quoted
        // identifiers, string literals, comments, or subqueries are ignored.
        let tailKeywords: Set<String> = ["ORDER", "GROUP", "HAVING", "LIMIT", "OFFSET"]
        var depth = 0
        var whereEnd: String.Index?
        var tailStart: String.Index?
        for token in SQLTokenizer.tokenize(sql) {
            switch token.kind {
            case .leftParen:
                depth += 1
            case .rightParen:
                depth = max(0, depth - 1)
            case .keyword(let kw) where depth == 0:
                if kw == "WHERE", whereEnd == nil {
                    whereEnd = token.range.upperBound
                } else if tailKeywords.contains(kw), tailStart == nil {
                    tailStart = token.range.lowerBound
                }
            default:
                break
            }
        }

        if let whereEnd {
            // Parenthesize the existing WHERE body before AND-ing the new
            // condition, otherwise an existing top-level OR silently changes
            // meaning: `WHERE a = 1 OR b = 2` would become
            // `WHERE a = 1 OR b = 2 AND c = 3`, which SQL binds as
            // `a = 1 OR (b = 2 AND c = 3)` rather than the intended
            // `(a = 1 OR b = 2) AND c = 3`.
            let bodyEnd = tailStart ?? sql.endIndex
            let head = sql[..<whereEnd]
            let body = sql[whereEnd..<bodyEnd].trimmingCharacters(in: .whitespacesAndNewlines)
            let tail = sql[bodyEnd...].trimmingCharacters(in: .whitespacesAndNewlines)
            sql = "\(head) (\(body)) AND \(condition)"
            if !tail.isEmpty {
                sql += " \(tail)"
            }
        } else if let tailStart {
            sql.insert(contentsOf: "WHERE \(condition) ", at: tailStart)
        } else {
            sql += " WHERE \(condition)"
        }

        sqlQuery = sql
    }

    /// Sets the default query for the given stream, returning `true` if the
    /// query text was replaced (i.e. the user hadn't customized it).
    @discardableResult
    func setDefaultQuery(stream: String, previousStream: String? = nil) -> Bool {
        // Always replace when switching streams — the previous query (whether
        // auto-generated or from a saved filter) belongs to the old stream.
        // Only preserve the query when no stream change occurred (e.g. onAppear).
        let shouldReplace: Bool
        if sqlQuery.isEmpty || previousStream != nil {
            shouldReplace = true
        } else {
            shouldReplace = false
        }

        if shouldReplace {
            sqlQuery = "SELECT * FROM \(Self.escapeSQLIdentifier(stream)) ORDER BY p_timestamp DESC LIMIT \(queryLimit)"
        }
        return shouldReplace
    }

    /// Escapes a SQL identifier by doubling internal double-quotes, then wrapping in double-quotes.
    static func escapeSQLIdentifier(_ identifier: String) -> String {
        "\"\(identifier.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    // MARK: - Query History

    private func addToHistory(_ entry: QueryHistoryEntry) {
        // Deduplicate consecutive identical queries
        if queryHistory.first?.sql == entry.sql { return }
        queryHistory.insert(entry, at: 0)
        if queryHistory.count > Self.maxHistory {
            queryHistory = Array(queryHistory.prefix(Self.maxHistory))
            historyIsFull = true
        }
        Self.saveHistory(queryHistory)
    }

    func clearHistory() {
        queryHistory = []
        historyIsFull = false
        Self.saveHistory([])
    }

    private static let historyKey = "parseable_query_history"

    private static func loadHistory() -> [QueryHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: historyKey) else { return [] }
        return (try? JSONDecoder().decode([QueryHistoryEntry].self, from: data)) ?? []
    }

    private static func saveHistory(_ history: [QueryHistoryEntry]) {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }
}
