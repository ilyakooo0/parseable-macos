import Foundation
import SwiftUI

@Observable
final class QueryViewModel {
    var sqlQuery = ""
    var results: [LogRecord] = [] {
        didSet { updateFilteredResults() }
    }
    var columns: [String] = []
    var isLoading = false
    var errorMessage: String?
    var resultCount = 0
    var queryDuration: TimeInterval?
    var selectedLogEntry: LogRecord?
    var filterText = "" {
        didSet { updateFilteredResults() }
    }
    var resultsTruncated = false

    // Time range
    var timeRangeOption: TimeRangeOption = .last1Hour
    var customStartDate = Calendar.current.date(byAdding: .hour, value: -1, to: Date()) ?? Date()
    var customEndDate = Date()

    // Query history
    var queryHistory: [QueryHistoryEntry] = []
    var historyIsFull = false
    private static let maxHistory = 50

    struct QueryHistoryEntry: Identifiable, Codable {
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
        return stored > 0 ? stored : 1000
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
        if sqlQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let stream else {
                errorMessage = "Select a stream or enter a SQL query"
                return
            }
            sql = "SELECT * FROM \"\(stream)\" ORDER BY p_timestamp DESC LIMIT \(limit)"
        } else {
            sql = sqlQuery
        }

        isLoading = true
        errorMessage = nil
        resultsTruncated = false
        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            results = try await client.query(sql: sql, startTime: startDate, endTime: endDate)
            queryDuration = CFAbsoluteTimeGetCurrent() - startTime
            resultCount = results.count

            // Detect if results were likely truncated
            resultsTruncated = results.count == limit

            // Extract columns in a single pass, with priority fields first
            columns = extractColumns(from: results)

            // Record in history
            let entry = QueryHistoryEntry(sql: sql, resultCount: resultCount, duration: queryDuration ?? 0)
            addToHistory(entry)
        } catch {
            errorMessage = error.localizedDescription
            results = []
            columns = []
        }

        isLoading = false
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
        guard !results.isEmpty, !columns.isEmpty else { return "" }

        var csv = columns.map { escapeCSV($0) }.joined(separator: ",") + "\n"

        for record in results {
            let row = columns.map { column in
                let value = record[column]?.displayString ?? ""
                return escapeCSV(value)
            }
            csv += row.joined(separator: ",") + "\n"
        }

        return csv
    }

    private func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    func setDefaultQuery(stream: String) {
        if sqlQuery.isEmpty {
            sqlQuery = "SELECT * FROM \"\(stream)\" ORDER BY p_timestamp DESC LIMIT \(queryLimit)"
        }
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
