import Foundation
import SwiftUI

@MainActor
@Observable
final class LiveTailViewModel {
    var entries: [LiveTailEntry] = []
    var isRunning = false
    var isPaused = false
    var filterText = ""
    var columnFilters: [ColumnFilter] = []
    var pollInterval: TimeInterval = 2.0
    var maxEntries = 5000
    var errorMessage: String?
    var droppedCount = 0
    private(set) var lastPollTime: Date?

    // Column management
    var columns: [String] = []
    var columnOrder: [String] = []
    var hiddenColumns: Set<String> = []
    private var currentStream: String?

    // nonisolated(unsafe) so deinit can invalidate the timer.
    // Only mutated from @MainActor methods (start/stop).
    nonisolated(unsafe) private var timer: Timer?
    private var lastTimestamp: Date?
    private var seenFingerprints: Set<String> = []
    private var consecutiveErrors = 0
    private static let maxConsecutiveErrors = 5

    deinit {
        timer?.invalidate()
    }

    // Cached formatters to avoid per-poll allocation
    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoBasic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    struct LiveTailEntry: Identifiable, Sendable {
        let id = UUID()
        let timestamp: Date
        let record: LogRecord
        let displayTimestamp: String
        let summary: String
    }

    struct ColumnFilter: Identifiable, Equatable, Sendable {
        let id = UUID()
        let column: String
        let value: JSONValue?
        let exclude: Bool

        var displayLabel: String {
            let op = exclude ? "≠" : "="
            let val = value?.displayString ?? "null"
            return "\(column) \(op) \(val)"
        }
    }

    var filteredEntries: [LiveTailEntry] {
        var result = entries

        // Apply column filters
        for filter in columnFilters {
            result = result.filter { entry in
                let recordValue = entry.record[filter.column]
                let matches: Bool
                if filter.value == nil || filter.value == .null {
                    matches = recordValue == nil || recordValue == .null
                } else {
                    matches = recordValue == filter.value
                }
                return filter.exclude ? !matches : matches
            }
        }

        // Apply text filter
        if !filterText.isEmpty {
            result = result.filter { entry in
                entry.summary.localizedCaseInsensitiveContains(filterText) ||
                entry.record.values.contains { $0.displayString.localizedCaseInsensitiveContains(filterText) }
            }
        }

        return result
    }

    func addColumnFilter(column: String, value: JSONValue?, exclude: Bool) {
        // Remove any existing filter on the same column with the same value
        columnFilters.removeAll { $0.column == column && $0.value == value && $0.exclude == exclude }
        columnFilters.append(ColumnFilter(column: column, value: value, exclude: exclude))
    }

    func removeColumnFilter(_ filter: ColumnFilter) {
        columnFilters.removeAll { $0.id == filter.id }
    }

    func clearColumnFilters() {
        columnFilters.removeAll()
    }

    var entryCount: Int { entries.count }
    var displayedCount: Int { filteredEntries.count }

    func start(client: ParseableClient?, stream: String?) {
        guard let client, let stream, !isRunning else { return }

        // Read settings from UserDefaults (set by SettingsView @AppStorage)
        let storedInterval = UserDefaults.standard.double(forKey: "liveTailPollInterval")
        if storedInterval >= 1 { pollInterval = storedInterval }
        let storedMax = UserDefaults.standard.integer(forKey: "liveTailMaxEntries")
        if storedMax > 0 { maxEntries = storedMax }

        isRunning = true
        isPaused = false
        errorMessage = nil
        entries = []
        seenFingerprints = []
        droppedCount = 0
        consecutiveErrors = 0
        lastPollTime = nil
        lastTimestamp = Date()
        columns = []
        columnOrder = []
        hiddenColumns = []
        columnFilters = []
        currentStream = stream

        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isPaused else { return }
                await self.poll(client: client, stream: stream)
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        isPaused = false
    }

    func togglePause() {
        isPaused.toggle()
    }

    func clear() {
        entries = []
        seenFingerprints = []
        droppedCount = 0
        columns = []
        columnOrder = []
        hiddenColumns = []
        columnFilters = []
    }

    // MARK: - Column Management

    var visibleColumns: [String] {
        columnOrder.filter { !hiddenColumns.contains($0) }
    }

    func toggleColumnVisibility(_ column: String) {
        if hiddenColumns.contains(column) {
            hiddenColumns.remove(column)
        } else {
            let visibleCount = columnOrder.count - hiddenColumns.count
            if visibleCount > 1 {
                hiddenColumns.insert(column)
            }
        }
        saveColumnConfig()
    }

    func showAllColumns() {
        hiddenColumns.removeAll()
        saveColumnConfig()
    }

    func moveColumn(from source: IndexSet, to destination: Int) {
        columnOrder.move(fromOffsets: source, toOffset: destination)
        saveColumnConfig()
    }

    func moveColumn(_ column: String, to targetColumn: String) {
        guard let fromIndex = columnOrder.firstIndex(of: column),
              let toIndex = columnOrder.firstIndex(of: targetColumn),
              fromIndex != toIndex else { return }
        let item = columnOrder.remove(at: fromIndex)
        columnOrder.insert(item, at: toIndex)
        saveColumnConfig()
    }

    func resetColumnConfig() {
        columnOrder = columns
        hiddenColumns.removeAll()
        saveColumnConfig()
    }

    // MARK: - Column Configuration Persistence

    private static func columnConfigKey(for stream: String) -> String {
        "parseable_livetail_column_config_\(stream)"
    }

    private func saveColumnConfig() {
        guard let stream = currentStream else { return }
        let config = QueryViewModel.ColumnConfiguration(order: columnOrder, hidden: hiddenColumns)
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: Self.columnConfigKey(for: stream))
        }
    }

    private static func loadColumnConfig(for stream: String) -> QueryViewModel.ColumnConfiguration? {
        guard let data = UserDefaults.standard.data(forKey: columnConfigKey(for: stream)) else { return nil }
        return try? JSONDecoder().decode(QueryViewModel.ColumnConfiguration.self, from: data)
    }

    // MARK: - Column Extraction

    private func extractColumns(from records: [LogRecord]) -> [String] {
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

    private func updateColumns(stream: String) {
        let allRecords = entries.map { $0.record }
        let extracted = extractColumns(from: allRecords)

        if columns.isEmpty {
            // First time — apply saved config
            columns = extracted
            currentStream = stream

            if let config = Self.loadColumnConfig(for: stream) {
                let extractedSet = Set(extracted)
                var merged = config.order.filter { extractedSet.contains($0) }
                let mergedSet = Set(merged)
                for col in extracted where !mergedSet.contains(col) {
                    merged.append(col)
                }
                columnOrder = merged
                hiddenColumns = config.hidden.intersection(extractedSet)
            } else {
                columnOrder = extracted
                hiddenColumns = []
            }
        } else {
            // Merge: keep existing order, append any new columns
            let existingSet = Set(columnOrder)
            var newCols = [String]()
            for col in extracted where !existingSet.contains(col) {
                newCols.append(col)
            }
            if !newCols.isEmpty {
                columns.append(contentsOf: newCols)
                columnOrder.append(contentsOf: newCols)
            }
        }
    }

    private func poll(client: ParseableClient, stream: String) async {
        let now = Date()
        // The Parseable server truncates query time-ranges to minute
        // boundaries, so a narrow window (< 60 s) can collapse to a
        // zero-width range and return HTTP 400.  Always look back at
        // least 90 seconds; fingerprint deduplication prevents showing
        // duplicate entries.
        let idealStart = lastTimestamp ?? now.addingTimeInterval(-30)
        let safeStart = now.addingTimeInterval(-90)
        let queryStart = min(idealStart, safeStart)
        let sql = "SELECT * FROM \(QueryViewModel.escapeSQLIdentifier(stream)) ORDER BY p_timestamp DESC LIMIT 200"

        do {
            let records = try await client.query(sql: sql, startTime: queryStart, endTime: now)

            var newEntries: [LiveTailEntry] = []

            for record in records {
                let fp = Self.fingerprint(for: record)
                guard !seenFingerprints.contains(fp) else { continue }
                seenFingerprints.insert(fp)

                let timestamp = parseTimestamp(from: record) ?? now
                let summary = buildSummary(from: record)

                newEntries.append(LiveTailEntry(
                    timestamp: timestamp,
                    record: record,
                    displayTimestamp: Self.displayFormatter.string(from: timestamp),
                    summary: summary
                ))
            }

            if !newEntries.isEmpty {
                entries.append(contentsOf: newEntries.sorted { $0.timestamp < $1.timestamp })

                if entries.count > maxEntries {
                    let excess = entries.count - maxEntries
                    droppedCount += excess
                    entries.removeFirst(excess)

                    // Rebuild fingerprint set from remaining entries to bound memory
                    // and ensure dropped entries can be re-detected if they reappear.
                    seenFingerprints = Set(entries.map { Self.fingerprint(for: $0.record) })
                }

                updateColumns(stream: stream)
            }

            lastTimestamp = now
            lastPollTime = now
            errorMessage = nil
            consecutiveErrors = 0
        } catch {
            consecutiveErrors += 1
            if consecutiveErrors >= Self.maxConsecutiveErrors {
                errorMessage = "\(ParseableError.userFriendlyMessage(for: error)) — stopped after \(consecutiveErrors) consecutive failures"
                stop()
            } else {
                errorMessage = ParseableError.userFriendlyMessage(for: error)
            }
        }
    }

    /// Deterministic content-based fingerprint using sorted key-value pairs and FNV-1a.
    static func fingerprint(for record: LogRecord) -> String {
        var h0: UInt64 = 14695981039346656037
        var h1: UInt64 = 14695981039346656037 &* 31
        for key in record.keys.sorted() {
            for byte in key.utf8 {
                h0 = (h0 ^ UInt64(byte)) &* 1099511628211
                h1 = (h1 ^ UInt64(byte)) &* 6700417
            }
            h0 = (h0 ^ 0) &* 1099511628211 // separator
            if let val = record[key] {
                // Use exportString so nested objects/arrays contribute their
                // actual content to the hash, not just their field count.
                for byte in val.exportString.utf8 {
                    h0 = (h0 ^ UInt64(byte)) &* 1099511628211
                    h1 = (h1 ^ UInt64(byte)) &* 6700417
                }
            }
            h1 = (h1 ^ 0xFF) &* 6700417 // field separator
        }
        return String(h0, radix: 36) + String(h1, radix: 36)
    }

    func parseTimestamp(from record: LogRecord) -> Date? {
        guard let value = record["p_timestamp"] ?? record["timestamp"] ?? record["time"] ?? record["@timestamp"] else {
            return nil
        }
        if case .string(let str) = value {
            if let date = Self.isoFractional.date(from: str) {
                return date
            }
            return Self.isoBasic.date(from: str)
        }
        return nil
    }

    func buildSummary(from record: LogRecord) -> String {
        var parts: [String] = []

        if let level = record["level"] ?? record["severity"] ?? record["log_level"] {
            parts.append("[\(level.displayString)]")
        }

        if let msg = record["message"] ?? record["msg"] ?? record["body"] ?? record["log"] {
            parts.append(msg.displayString)
        }

        if parts.isEmpty {
            let scalarFields = record
                .filter { $0.key != "p_timestamp" && $0.key != "p_tags" && $0.key != "p_metadata" }
                .sorted { $0.key < $1.key }
                .prefix(3)
            for (key, value) in scalarFields {
                if value.isScalar {
                    parts.append("\(key)=\(value.displayString)")
                }
            }
        }

        return parts.joined(separator: " ")
    }
}
