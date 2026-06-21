import Foundation
import SwiftUI

@MainActor
@Observable
final class LiveTailViewModel {
    var entries: [LiveTailEntry] = []
    var isRunning = false
    var isPaused = false
    var filterText = "" {
        didSet { rebuildFilteredEntries() }
    }
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
    /// The full persisted set of hidden columns, including ones not yet seen in
    /// this session. Live-tail columns are discovered incrementally across polls,
    /// so `hiddenColumns` (only the seen ones) can't be the source of truth — a
    /// column hidden last session would reappear visible when it shows up in a
    /// later poll. This retains the intent so it stays hidden when it appears.
    private var savedHiddenColumns: Set<String> = []
    private var currentStream: String?

    // nonisolated(unsafe) so deinit can invalidate the timer.
    // Only mutated from @MainActor methods (start/stop).
    nonisolated(unsafe) private var timer: Timer?
    private var lastTimestamp: Date?
    private var seenFingerprints: Set<String> = []
    /// Insertion-ordered mirror of `seenFingerprints` (oldest first), used to
    /// evict the least-recently-seen fingerprints when the set is trimmed.
    private var seenFingerprintOrder: [String] = []
    /// Upper bound on the dedup fingerprint set. Kept well above `maxEntries` so
    /// fingerprints of recently-evicted entries survive long enough to suppress
    /// duplicates that reappear inside the next poll's look-back window, while
    /// still bounding memory. Only when this is exceeded do we fall back to the
    /// retained-entry fingerprints.
    private var maxSeenFingerprints: Int { maxEntries * 4 }
    private var allKnownKeys: Set<String> = []
    private var consecutiveErrors = 0
    private static let maxConsecutiveErrors = 5
    /// Guards against overlapping polls: if a poll's network round-trip outlasts
    /// the timer interval, the next tick must not start a second concurrent poll
    /// (which would let the two interleave and write `lastTimestamp` /
    /// `consecutiveErrors` out of order).
    private var isPolling = false
    /// Bumped by start()/stop()/clear() so an in-flight poll whose network
    /// round-trip outlives one of those transitions can detect it was superseded
    /// and drop its results instead of repopulating a torn-down/cleared tail.
    private var pollGeneration = 0

    deinit {
        timer?.invalidate()
    }

    // Cached formatters — nonisolated(unsafe) so static methods can use them from Task.detached
    nonisolated(unsafe) private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        // Fixed-format formatters must use en_US_POSIX so a non-Gregorian or
        // non-Latin-digit system locale doesn't render wrong numerals/era.
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    nonisolated(unsafe) private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let isoBasic: ISO8601DateFormatter = {
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
        let fingerprint: String
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

    private(set) var cachedFilteredEntries: [LiveTailEntry] = []
    var cachedFilteredRecords: [LogRecord] {
        cachedFilteredEntries.map { $0.record }
    }
    private(set) var filteredEntriesGeneration: Int = 0

    private func rebuildFilteredEntries() {
        let hasColumnFilters = !columnFilters.isEmpty
        let hasTextFilter = !filterText.isEmpty
        let activeFilters = columnFilters
        let text = filterText

        let result: [LiveTailEntry]
        if !hasColumnFilters && !hasTextFilter {
            result = entries
        } else {
            result = entries.filter { entry in
                if hasColumnFilters {
                    for filter in activeFilters {
                        let recordValue = entry.record[filter.column]
                        let matches: Bool
                        if filter.value == nil || filter.value == .null {
                            matches = recordValue == nil || recordValue == .null
                        } else {
                            matches = recordValue == filter.value
                        }
                        if filter.exclude ? matches : !matches {
                            return false
                        }
                    }
                }
                if hasTextFilter {
                    if !entry.summary.localizedCaseInsensitiveContains(text) &&
                       !entry.record.values.contains(where: { $0.displayString.localizedCaseInsensitiveContains(text) }) {
                        return false
                    }
                }
                return true
            }
        }

        cachedFilteredEntries = result
        filteredEntriesGeneration += 1
    }

    func addColumnFilter(column: String, value: JSONValue?, exclude: Bool) {
        // Remove any existing filter on the same column with the same value
        columnFilters.removeAll { $0.column == column && $0.value == value && $0.exclude == exclude }
        columnFilters.append(ColumnFilter(column: column, value: value, exclude: exclude))
        rebuildFilteredEntries()
    }

    func removeColumnFilter(_ filter: ColumnFilter) {
        columnFilters.removeAll { $0.id == filter.id }
        rebuildFilteredEntries()
    }

    func clearColumnFilters() {
        columnFilters.removeAll()
        rebuildFilteredEntries()
    }

    var entryCount: Int { entries.count }
    var displayedCount: Int { cachedFilteredEntries.count }

    func start(client: ParseableClient?, stream: String?) {
        guard let client, let stream, !isRunning else { return }

        // Read settings from UserDefaults (set by SettingsView @AppStorage)
        let storedInterval = UserDefaults.standard.double(forKey: "liveTailPollInterval")
        if storedInterval >= 1 { pollInterval = storedInterval }
        let storedMax = UserDefaults.standard.integer(forKey: "liveTailMaxEntries")
        if storedMax > 0 { maxEntries = storedMax }

        pollGeneration += 1
        isRunning = true
        isPaused = false
        errorMessage = nil
        entries = []
        seenFingerprints = []
        seenFingerprintOrder = []
        allKnownKeys = []
        droppedCount = 0
        consecutiveErrors = 0
        lastPollTime = nil
        lastTimestamp = Date()
        columns = []
        columnOrder = []
        hiddenColumns = []
        savedHiddenColumns = []
        columnFilters = []
        currentStream = stream
        rebuildFilteredEntries()

        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isPaused else { return }
                await self.poll(client: client, stream: stream)
            }
        }
    }

    func stop() {
        pollGeneration += 1
        timer?.invalidate()
        timer = nil
        isRunning = false
        isPaused = false
    }

    func togglePause() {
        isPaused.toggle()
    }

    func clear() {
        pollGeneration += 1
        entries = []
        seenFingerprints = []
        seenFingerprintOrder = []
        // Advance the look-back floor to now: without this, the next poll queries
        // from the old `lastTimestamp` with an empty fingerprint set and re-inserts
        // every just-cleared record still inside the ~90 s window, repopulating the
        // view the user just emptied. Matches start()'s reset.
        lastTimestamp = Date()
        allKnownKeys = []
        droppedCount = 0
        // Reset the failure counter too: the timer keeps polling after a clear, so
        // leaving accumulated errors in place could trip the auto-stop threshold
        // sooner than the intended N consecutive failures. Matches start()'s reset.
        consecutiveErrors = 0
        columns = []
        columnOrder = []
        hiddenColumns = []
        savedHiddenColumns = []
        columnFilters = []
        rebuildFilteredEntries()
    }

    // MARK: - Column Management

    var visibleColumns: [String] {
        columnOrder.filter { !hiddenColumns.contains($0) }
    }

    func toggleColumnVisibility(_ column: String) {
        if hiddenColumns.contains(column) {
            hiddenColumns.remove(column)
            savedHiddenColumns.remove(column)
        } else {
            let visibleCount = columnOrder.count - hiddenColumns.count
            if visibleCount > 1 {
                hiddenColumns.insert(column)
                savedHiddenColumns.insert(column)
            }
        }
        saveColumnConfig()
    }

    func showAllColumns() {
        hiddenColumns.removeAll()
        savedHiddenColumns.removeAll()
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
        savedHiddenColumns.removeAll()
        saveColumnConfig()
    }

    // MARK: - Column Configuration Persistence

    private static func columnConfigKey(for stream: String) -> String {
        "parseable_livetail_column_config_\(stream)"
    }

    private func saveColumnConfig() {
        guard let stream = currentStream else { return }
        // Persist the full intended hidden set (including columns not yet seen
        // this session) so it survives across restarts and incremental discovery.
        let config = QueryViewModel.ColumnConfiguration(order: columnOrder, hidden: savedHiddenColumns)
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: Self.columnConfigKey(for: stream))
        }
    }

    private static func loadColumnConfig(for stream: String) -> QueryViewModel.ColumnConfiguration? {
        guard let data = UserDefaults.standard.data(forKey: columnConfigKey(for: stream)) else { return nil }
        return try? JSONDecoder().decode(QueryViewModel.ColumnConfiguration.self, from: data)
    }

    // MARK: - Column Extraction

    private func extractColumnsFromKeys(_ keys: Set<String>) -> [String] {
        let priorityFields = ["p_timestamp", "p_tags", "p_metadata", "level", "severity", "message", "msg"]
        var remaining = keys
        var ordered: [String] = []
        for field in priorityFields {
            if remaining.remove(field) != nil {
                ordered.append(field)
            }
        }
        ordered.append(contentsOf: remaining.sorted())
        return ordered
    }

    private func updateColumns(stream: String) {
        let extracted = extractColumnsFromKeys(allKnownKeys)

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
                savedHiddenColumns = config.hidden
                hiddenColumns = config.hidden.intersection(extractedSet)
            } else {
                columnOrder = extracted
                savedHiddenColumns = []
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
                // Re-hide any newly appearing column that was hidden in a prior
                // session but hadn't been seen yet this run.
                hiddenColumns.formUnion(newCols.filter { savedHiddenColumns.contains($0) })
            }
        }

        // The `visibleCount > 1` guard in toggleColumnVisibility only covers
        // user toggles. The config-load and incremental-merge paths above can
        // hide every known column (e.g. a saved-hidden set that happens to cover
        // all columns seen so far), which would render the live-tail table with
        // zero columns. Keep at least the first column visible.
        if !columnOrder.isEmpty, hiddenColumns.count >= columnOrder.count,
           let firstColumn = columnOrder.first {
            hiddenColumns.remove(firstColumn)
        }
    }

    private func poll(client: ParseableClient, stream: String) async {
        guard !isPolling else { return }
        isPolling = true
        defer { isPolling = false }
        let generation = pollGeneration

        let now = Date()
        // The Parseable server truncates query time-ranges to minute
        // boundaries, so a narrow window (< 60 s) can collapse to a
        // zero-width range and return HTTP 400.  Always look back at
        // least 90 seconds; fingerprint deduplication prevents showing
        // duplicate entries.
        let idealStart = lastTimestamp ?? now.addingTimeInterval(-30)
        let safeStart = now.addingTimeInterval(-90)
        let queryStart = min(idealStart, safeStart)
        // ORDER BY DESC keeps the newest rows when the page is capped, so a busy
        // stream that exceeds the limit within one ~90 s window silently loses the
        // oldest rows in that window. Keep a generous page to make that rare; this
        // HTTP-polling tail can't match true gRPC streaming throughput regardless.
        let sql = "SELECT * FROM \(QueryViewModel.escapeSQLIdentifier(stream)) ORDER BY p_timestamp DESC LIMIT 1000"

        do {
            let records = try await client.query(sql: sql, startTime: queryStart, endTime: now)

            // A stop()/clear()/start during the network round-trip supersedes this
            // poll; don't write stale results to a torn-down or cleared tail. Also
            // bail if the user paused mid-flight.
            guard isRunning, !isPaused, generation == pollGeneration else { return }

            // Process records off the main actor using a snapshot of seen fingerprints
            let seenSnapshot = seenFingerprints
            let pollTime = now
            let candidateEntries = await Task.detached(priority: .userInitiated) {
                var results: [LiveTailEntry] = []
                for record in records {
                    let fp = Self.fingerprint(for: record)
                    guard !seenSnapshot.contains(fp) else { continue }
                    let timestamp = Self.parseTimestamp(from: record) ?? pollTime
                    let summary = Self.buildSummary(from: record)
                    results.append(LiveTailEntry(
                        timestamp: timestamp,
                        record: record,
                        displayTimestamp: Self.displayFormatter.string(from: timestamp),
                        summary: summary,
                        fingerprint: fp
                    ))
                }
                return results
            }.value

            // Re-check after the detached processing hop: a stop/clear could have
            // landed while we were off the main actor.
            guard isRunning, !isPaused, generation == pollGeneration else { return }

            // Authoritative dedup on main actor
            var newEntries: [LiveTailEntry] = []
            for entry in candidateEntries {
                if seenFingerprints.insert(entry.fingerprint).inserted {
                    seenFingerprintOrder.append(entry.fingerprint)
                    newEntries.append(entry)
                }
            }

            if !newEntries.isEmpty {
                entries.append(contentsOf: newEntries.sorted { $0.timestamp < $1.timestamp })

                if entries.count > maxEntries {
                    let excess = entries.count - maxEntries
                    droppedCount += excess
                    // Entries are not globally time-sorted across polls (a late or
                    // backfilled record appends after newer ones), so trimming by
                    // array position could evict newer entries. Sort by timestamp
                    // first so the suffix keeps the chronologically newest.
                    entries.sort { $0.timestamp < $1.timestamp }
                    entries = Array(entries.suffix(maxEntries))

                    // Do NOT rebuild the fingerprint set from the retained
                    // entries: an evicted record can still fall inside the next
                    // poll's look-back window, and dropping its fingerprint here
                    // would let it pass the dedup check and be re-appended as a
                    // duplicate. Keep the full seen-set so dedup stays correct;
                    // it is bounded below to avoid unbounded growth.
                    if seenFingerprints.count > maxSeenFingerprints {
                        // Evict the OLDEST surplus fingerprints by insertion order,
                        // not by what's currently buffered. Collapsing to only the
                        // buffered set would drop recently-evicted fingerprints that
                        // still fall inside the next poll's ~90 s look-back window,
                        // re-admitting those records as duplicates. Keeping the
                        // most-recently-seen tail preserves a full window of evicted
                        // fingerprints. Buffered fingerprints are always retained so
                        // a re-fetch of a buffered record stays deduplicated.
                        let overflow = seenFingerprints.count - maxSeenFingerprints
                        let buffered = Set(entries.map { $0.fingerprint })
                        let toDrop = Set(seenFingerprintOrder.prefix(overflow))
                            .subtracting(buffered)
                        if !toDrop.isEmpty {
                            seenFingerprints.subtract(toDrop)
                            seenFingerprintOrder.removeAll { toDrop.contains($0) }
                        }
                    }
                }

                // Only scan new records for new keys
                var hasNewKeys = false
                for entry in newEntries {
                    for key in entry.record.keys {
                        if allKnownKeys.insert(key).inserted {
                            hasNewKeys = true
                        }
                    }
                }
                if hasNewKeys {
                    updateColumns(stream: stream)
                }

                rebuildFilteredEntries()
            }

            lastTimestamp = now
            lastPollTime = now
            errorMessage = nil
            consecutiveErrors = 0
        } catch {
            // Drop the error if this poll was cancelled or superseded by a
            // stop/clear/start — don't bump the failure counter or surface an
            // error on a tail the user already tore down.
            guard !Task.isCancelled, isRunning, generation == pollGeneration else { return }
            consecutiveErrors += 1
            if consecutiveErrors >= Self.maxConsecutiveErrors {
                errorMessage = "\(ParseableError.userFriendlyMessage(for: error)) — stopped after \(consecutiveErrors) consecutive failures"
                stop()
            } else {
                errorMessage = ParseableError.userFriendlyMessage(for: error)
            }
        }
    }

    /// Deterministic content-based fingerprint using XOR with golden-ratio mixing.
    /// Order-independent: O(k) instead of O(k log k) per record.
    nonisolated static func fingerprint(for record: LogRecord) -> String {
        var xorAccum0: UInt64 = 0
        var xorAccum1: UInt64 = 0
        for (key, value) in record {
            var kh0: UInt64 = 14695981039346656037
            var kh1: UInt64 = 14695981039346656037 &* 31
            for byte in key.utf8 {
                kh0 = (kh0 ^ UInt64(byte)) &* 1099511628211
                kh1 = (kh1 ^ UInt64(byte)) &* 6700417
            }
            kh0 = (kh0 ^ 0) &* 1099511628211 // separator
            hashJSONValue(value, h0: &kh0, h1: &kh1)
            kh1 = (kh1 ^ 0xFF) &* 6700417 // field separator
            xorAccum0 ^= kh0 &* 0x9E3779B97F4A7C15
            xorAccum1 ^= kh1 &* 0x9E3779B97F4A7C15
        }
        let h0 = 14695981039346656037 &+ xorAccum0
        let h1 = (14695981039346656037 &* 31) &+ xorAccum1
        return String(h0, radix: 36) + String(h1, radix: 36)
    }

    /// Mixes the 8 bytes of a number's canonical 64-bit representation, prefixed by
    /// a shared numeric type byte so ints and equal-valued doubles fingerprint alike.
    nonisolated private static func hashNumberBits(_ bitPattern: UInt64, h0: inout UInt64, h1: inout UInt64) {
        h0 = (h0 ^ 0x02) &* 1099511628211
        h1 = (h1 ^ 0x02) &* 6700417
        var bits = bitPattern
        for _ in 0..<8 {
            h0 = (h0 ^ (bits & 0xFF)) &* 1099511628211
            h1 = (h1 ^ (bits & 0xFF)) &* 6700417
            bits >>= 8
        }
    }

    /// Recursively hashes a JSONValue tree without allocating intermediate strings.
    /// Uses type-discriminator bytes to prevent cross-type collisions.
    nonisolated private static func hashJSONValue(_ value: JSONValue, h0: inout UInt64, h1: inout UInt64) {
        switch value {
        case .null:
            h0 = (h0 ^ 0x00) &* 1099511628211
            h1 = (h1 ^ 0x00) &* 6700417
        case .bool(let b):
            h0 = (h0 ^ 0x01) &* 1099511628211
            h1 = (h1 ^ 0x01) &* 6700417
            let byte: UInt64 = b ? 1 : 0
            h0 = (h0 ^ byte) &* 1099511628211
            h1 = (h1 ^ byte) &* 6700417
        // `.int` and `.double` share one numeric encoding so the fingerprint stays
        // consistent with JSONValue equality, where `.int(5) == .double(5.0)`.
        // JSONValue.hash(into:) canonicalizes both through `Double`; mirror that here
        // (with NaN folded to a single bit pattern) so a field that serializes as `5`
        // in one poll and `5.0` in another doesn't bypass dedup as a phantom row.
        case .int(let i):
            hashNumberBits(Double(i).bitPattern, h0: &h0, h1: &h1)
        case .double(let d):
            hashNumberBits((d.isNaN ? Double.nan : d).bitPattern, h0: &h0, h1: &h1)
        case .string(let s):
            h0 = (h0 ^ 0x04) &* 1099511628211
            h1 = (h1 ^ 0x04) &* 6700417
            for byte in s.utf8 {
                h0 = (h0 ^ UInt64(byte)) &* 1099511628211
                h1 = (h1 ^ UInt64(byte)) &* 6700417
            }
        case .array(let arr):
            h0 = (h0 ^ 0x05) &* 1099511628211
            h1 = (h1 ^ 0x05) &* 6700417
            for element in arr {
                hashJSONValue(element, h0: &h0, h1: &h1)
                h0 = (h0 ^ 0xFE) &* 1099511628211 // element separator
                h1 = (h1 ^ 0xFE) &* 6700417
            }
        case .object(let dict):
            h0 = (h0 ^ 0x06) &* 1099511628211
            h1 = (h1 ^ 0x06) &* 6700417
            var xor0: UInt64 = 0
            var xor1: UInt64 = 0
            for (key, value) in dict {
                var kh0: UInt64 = 14695981039346656037
                var kh1: UInt64 = 14695981039346656037 &* 31
                for byte in key.utf8 {
                    kh0 = (kh0 ^ UInt64(byte)) &* 1099511628211
                    kh1 = (kh1 ^ UInt64(byte)) &* 6700417
                }
                kh0 = (kh0 ^ 0xFD) &* 1099511628211 // key-value separator
                hashJSONValue(value, h0: &kh0, h1: &kh1)
                xor0 ^= kh0 &* 0x9E3779B97F4A7C15
                xor1 ^= kh1 &* 0x9E3779B97F4A7C15
            }
            h0 = h0 &+ xor0
            h1 = h1 &+ xor1
        }
    }

    nonisolated static func parseTimestamp(from record: LogRecord) -> Date? {
        guard let value = record["p_timestamp"] ?? record["timestamp"] ?? record["time"] ?? record["@timestamp"] else {
            return nil
        }
        if case .string(let str) = value {
            if let date = isoFractional.date(from: str) {
                return date
            }
            return isoBasic.date(from: str)
        }
        return nil
    }

    nonisolated static func buildSummary(from record: LogRecord) -> String {
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
