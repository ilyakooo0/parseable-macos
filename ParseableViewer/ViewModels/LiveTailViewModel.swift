import Foundation
import SwiftUI

@Observable
final class LiveTailViewModel {
    var entries: [LiveTailEntry] = []
    var isRunning = false
    var isPaused = false
    var filterText = ""
    var maxEntries = 5000
    var errorMessage: String?

    private var timer: Timer?
    private var lastTimestamp: Date?
    private var seenHashes: Set<Int> = []

    struct LiveTailEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let record: LogRecord
        let displayTimestamp: String
        let summary: String
    }

    var filteredEntries: [LiveTailEntry] {
        guard !filterText.isEmpty else { return entries }
        return entries.filter { entry in
            entry.summary.localizedCaseInsensitiveContains(filterText) ||
            entry.record.values.contains { $0.displayString.localizedCaseInsensitiveContains(filterText) }
        }
    }

    var entryCount: Int { entries.count }
    var displayedCount: Int { filteredEntries.count }

    @MainActor
    func start(client: ParseableClient?, stream: String?) {
        guard let client, let stream, !isRunning else { return }

        isRunning = true
        isPaused = false
        errorMessage = nil
        entries = []
        seenHashes = []
        lastTimestamp = Date()

        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self, !self.isPaused else { return }
            Task { @MainActor in
                await self.poll(client: client, stream: stream)
            }
        }
    }

    @MainActor
    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        isPaused = false
    }

    func togglePause() {
        isPaused.toggle()
    }

    @MainActor
    func clear() {
        entries = []
        seenHashes = []
    }

    @MainActor
    private func poll(client: ParseableClient, stream: String) async {
        let now = Date()
        let queryStart = lastTimestamp ?? Calendar.current.date(byAdding: .second, value: -30, to: now)!
        let sql = "SELECT * FROM \"\(stream)\" ORDER BY p_timestamp DESC LIMIT 200"

        do {
            let records = try await client.query(sql: sql, startTime: queryStart, endTime: now)

            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"

            var newEntries: [LiveTailEntry] = []

            for record in records {
                let hash = record.hashValue
                guard !seenHashes.contains(hash) else { continue }
                seenHashes.insert(hash)

                let timestamp = parseTimestamp(from: record) ?? now
                let summary = buildSummary(from: record)

                newEntries.append(LiveTailEntry(
                    timestamp: timestamp,
                    record: record,
                    displayTimestamp: formatter.string(from: timestamp),
                    summary: summary
                ))
            }

            if !newEntries.isEmpty {
                entries.append(contentsOf: newEntries.sorted { $0.timestamp < $1.timestamp })

                // Trim if exceeding max
                if entries.count > maxEntries {
                    let excess = entries.count - maxEntries
                    entries.removeFirst(excess)
                }
            }

            lastTimestamp = now
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func parseTimestamp(from record: LogRecord) -> Date? {
        guard let value = record["p_timestamp"] ?? record["timestamp"] ?? record["time"] ?? record["@timestamp"] else {
            return nil
        }
        if case .string(let str) = value {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: str) {
                return date
            }
            // Try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: str)
        }
        return nil
    }

    private func buildSummary(from record: LogRecord) -> String {
        var parts: [String] = []

        // Level/severity
        if let level = record["level"] ?? record["severity"] ?? record["log_level"] {
            parts.append("[\(level.displayString)]")
        }

        // Message
        if let msg = record["message"] ?? record["msg"] ?? record["body"] ?? record["log"] {
            parts.append(msg.displayString)
        }

        if parts.isEmpty {
            // Fallback: show first few scalar fields
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
