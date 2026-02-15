import Foundation
import SwiftUI

@Observable
final class QueryViewModel {
    var sqlQuery = ""
    var results: [LogRecord] = [] {
        didSet { updateFilteredResults() }
    }
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
        didSet { updateFilteredResults() }
    }
    var resultsTruncated = false

    // Schema fields for autocomplete
    var schemaFields: [SchemaField] = []

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
        columnOrder.insert(item, at: toIndex)
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
        if visible == columns {
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

    private func updateFilteredResults() {
        if filterText.isEmpty {
            filteredResults = results
        } else {
            filteredResults = results.filter { record in
                record.values.contains { value in
                    value.displayString.localizedCaseInsensitiveContains(filterText)
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
        guard let client, let stream else {
            schemaFields = []
            return
        }
        do {
            let schema = try await client.getStreamSchema(stream: stream)
            schemaFields = schema.fields
        } catch {
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
            for column in empty {
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
        if let data = try? encoder.encode(results),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return "[]"
    }

    func exportAsCSV() -> String {
        Self.buildCSV(records: results, columns: visibleColumns)
    }

    /// Builds a CSV string from records and columns. Safe to call from any thread.
    static func buildCSV(records: [LogRecord], columns: [String]) -> String {
        guard !records.isEmpty, !columns.isEmpty else { return "" }

        var csv = columns.map { escapeCSV($0) }.joined(separator: ",") + "\n"

        for record in records {
            let row = columns.map { column in
                let value = record[column]?.exportString ?? ""
                return escapeCSV(value)
            }
            csv += row.joined(separator: ",") + "\n"
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

        let wherePattern = #"(?i)\bWHERE\b"#
        let tailPattern = #"(?i)\b(ORDER\s+BY|GROUP\s+BY|HAVING|LIMIT)\b"#

        if let whereRange = sql.range(of: wherePattern, options: .regularExpression) {
            let afterWhere = whereRange.upperBound
            let searchRange = afterWhere..<sql.endIndex
            if let tailRange = sql.range(of: tailPattern, options: .regularExpression, range: searchRange) {
                sql.insert(contentsOf: "AND \(condition) ", at: tailRange.lowerBound)
            } else {
                sql += " AND \(condition)"
            }
        } else {
            if let tailRange = sql.range(of: tailPattern, options: .regularExpression) {
                sql.insert(contentsOf: "WHERE \(condition) ", at: tailRange.lowerBound)
            } else {
                sql += " WHERE \(condition)"
            }
        }

        sqlQuery = sql
    }

    /// Sets the default query for the given stream, returning `true` if the
    /// query text was replaced (i.e. the user hadn't customized it).
    @discardableResult
    func setDefaultQuery(stream: String, previousStream: String? = nil) -> Bool {
        // Replace the query if it's empty or still matches the auto-generated
        // default for the previous stream. If the user edited the SQL, keep it.
        let shouldReplace: Bool
        if sqlQuery.isEmpty {
            shouldReplace = true
        } else if let prev = previousStream {
            let prevPrefix = "SELECT * FROM \(Self.escapeSQLIdentifier(prev))"
            shouldReplace = sqlQuery.hasPrefix(prevPrefix)
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
