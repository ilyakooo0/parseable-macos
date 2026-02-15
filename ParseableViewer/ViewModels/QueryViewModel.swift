import Foundation
import SwiftUI

@Observable
final class QueryViewModel {
    var sqlQuery = ""
    var results: [LogRecord] = []
    var columns: [String] = []
    var isLoading = false
    var errorMessage: String?
    var resultCount = 0
    var queryDuration: TimeInterval?
    var selectedLogEntry: LogRecord?
    var filterText = ""

    // Time range
    var timeRangeOption: TimeRangeOption = .last1Hour
    var customStartDate = Calendar.current.date(byAdding: .hour, value: -1, to: Date()) ?? Date()
    var customEndDate = Date()

    // Export
    var showExportDialog = false

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

        func dateRange() -> (start: Date, end: Date) {
            let now = Date()
            let start: Date
            switch self {
            case .last5Min: start = Calendar.current.date(byAdding: .minute, value: -5, to: now)!
            case .last15Min: start = Calendar.current.date(byAdding: .minute, value: -15, to: now)!
            case .last30Min: start = Calendar.current.date(byAdding: .minute, value: -30, to: now)!
            case .last1Hour: start = Calendar.current.date(byAdding: .hour, value: -1, to: now)!
            case .last6Hours: start = Calendar.current.date(byAdding: .hour, value: -6, to: now)!
            case .last24Hours: start = Calendar.current.date(byAdding: .hour, value: -24, to: now)!
            case .last7Days: start = Calendar.current.date(byAdding: .day, value: -7, to: now)!
            case .last30Days: start = Calendar.current.date(byAdding: .day, value: -30, to: now)!
            case .custom: start = now // Overridden by custom dates
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

    var filteredResults: [LogRecord] {
        guard !filterText.isEmpty else { return results }
        return results.filter { record in
            record.values.contains { value in
                value.displayString.localizedCaseInsensitiveContains(filterText)
            }
        }
    }

    @MainActor
    func executeQuery(client: ParseableClient?, stream: String?) async {
        guard let client else {
            errorMessage = "Not connected to server"
            return
        }

        let sql: String
        if sqlQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let stream else {
                errorMessage = "Select a stream or enter a SQL query"
                return
            }
            sql = "SELECT * FROM \"\(stream)\" ORDER BY p_timestamp DESC LIMIT 1000"
        } else {
            sql = sqlQuery
        }

        isLoading = true
        errorMessage = nil
        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            results = try await client.query(sql: sql, startTime: startDate, endTime: endDate)
            queryDuration = CFAbsoluteTimeGetCurrent() - startTime
            resultCount = results.count

            // Extract unique column names preserving a sensible order
            var seen = Set<String>()
            var orderedColumns: [String] = []
            // Prioritize common fields
            let priorityFields = ["p_timestamp", "p_tags", "p_metadata", "level", "severity", "message", "msg"]
            for field in priorityFields {
                for record in results {
                    if record[field] != nil && !seen.contains(field) {
                        seen.insert(field)
                        orderedColumns.append(field)
                        break
                    }
                }
            }
            for record in results {
                for key in record.keys.sorted() {
                    if !seen.contains(key) {
                        seen.insert(key)
                        orderedColumns.append(key)
                    }
                }
            }
            columns = orderedColumns
        } catch {
            errorMessage = error.localizedDescription
            results = []
            columns = []
        }

        isLoading = false
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
            sqlQuery = "SELECT * FROM \"\(stream)\" ORDER BY p_timestamp DESC LIMIT 1000"
        }
    }
}
