import SwiftUI
import UniformTypeIdentifiers

/// Computes the display width needed for a text string using the given font.
private func measureTextWidth(_ text: String, font: NSFont) -> CGFloat {
    let attributes: [NSAttributedString.Key: Any] = [.font: font]
    return ceil((text as NSString).size(withAttributes: attributes).width)
}

/// Font used for header text measurement.
private let headerMeasureFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
/// Font used for cell text measurement.
private let cellMeasureFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)

/// Computes the ideal width for a single column by sampling record content.
func idealColumnWidth(for column: String, records: [LogRecord]) -> CGFloat {
    let padding: CGFloat = 28 // horizontal padding (6*2) + sort indicator + buffer
    let minWidth: CGFloat = 50
    let maxWidth: CGFloat = 600
    let sampleCount = min(records.count, 200)

    var widest = measureTextWidth(column, font: headerMeasureFont)
    // Sample evenly across the whole result set, not just the first N rows —
    // otherwise a wide value that sorts beyond row N is never measured and the
    // column auto-fits too narrow after sorting. Map each of the `sampleCount`
    // samples to a spread-out index so we hit exactly `sampleCount` distinct rows
    // (a stride with an integer step would skip rows yet still undersample).
    for s in 0..<sampleCount {
        let i = s * records.count / sampleCount
        let text = records[i][column]?.displayString ?? ""
        widest = max(widest, measureTextWidth(text, font: cellMeasureFont))
    }

    return min(max(widest + padding, minWidth), maxWidth)
}

/// Computes ideal widths for all columns by sampling record content.
func computeColumnWidths(columns: [String], records: [LogRecord]) -> [String: CGFloat] {
    var widths: [String: CGFloat] = [:]
    for column in columns {
        widths[column] = idealColumnWidth(for: column, records: records)
    }
    return widths
}

/// Shared log-level color mapping.
func levelColor(for value: String) -> Color {
    switch value.lowercased() {
    case "error", "fatal", "critical", "panic": return .red
    case "warn", "warning": return .orange
    case "info": return .blue
    case "debug", "trace": return .secondary
    default: return .primary
    }
}

// MARK: - Severity Row Tinting

/// Semantic severity levels for row background tinting.
enum SeverityLevel {
    case fatal
    case error
    case warning
    case info
    case debug
    case trace
    case unknown
}

/// Column names (lowercased) that commonly hold a severity / log-level value.
private let severityColumnNames: Set<String> = [
    "level", "severity", "log_level", "loglevel", "log.level",
    "p_level", "severity_text", "levelname", "log_severity",
    "priority", "syslog_severity", "msg_severity", "verbosity",
    "otel.severity", "severity_number",
]

/// Maps a raw severity string to a ``SeverityLevel``.
func parseSeverity(from value: String) -> SeverityLevel {
    let lower = value.trimmingCharacters(in: .whitespaces).lowercased()

    // Try well-known textual levels first.
    switch lower {
    // Fatal / Critical
    case "fatal", "critical", "panic", "emerg", "emergency", "alert", "crit":
        return .fatal
    // Error
    case "error", "err", "failure", "fail", "severe":
        return .error
    // Warning
    case "warn", "warning", "caution":
        return .warning
    // Info / Notice
    case "info", "information", "informational", "notice":
        return .info
    // Debug
    case "debug", "dbg", "verbose":
        return .debug
    // Trace
    case "trace", "finest", "finer", "fine", "all":
        return .trace
    default:
        break
    }

    // Try numeric syslog severity (RFC 5424): 0=Emergency … 7=Debug.
    if let num = Int(lower) {
        switch num {
        case 0...1: return .fatal   // Emergency, Alert
        case 2:     return .fatal   // Critical
        case 3:     return .error   // Error
        case 4:     return .warning // Warning
        case 5:     return .info    // Notice
        case 6:     return .info    // Informational
        case 7:     return .debug   // Debug
        default:    break
        }
    }

    return .unknown
}

/// Columns (lowercased) that carry an OpenTelemetry `severity_number` (1–24)
/// rather than an RFC 5424 syslog severity (0–7). The two scales overlap, so
/// numeric values from these columns must be interpreted on the OTel scale.
private let otelSeverityColumns: Set<String> = ["severity_number", "otel.severity"]

/// Maps an OpenTelemetry `severity_number` (1–24) to a ``SeverityLevel``.
/// Higher is more severe, in contrast to RFC 5424.
func parseOTelSeverityNumber(_ num: Int) -> SeverityLevel {
    switch num {
    case 1...4:   return .trace
    case 5...8:   return .debug
    case 9...12:  return .info
    case 13...16: return .warning
    case 17...20: return .error
    case 21...24: return .fatal
    default:      return .unknown
    }
}

/// Extracts the severity level from a log record by checking only known severity columns.
func extractSeverity(from record: LogRecord, severityColumns: Set<String>) -> SeverityLevel {
    // Iterate in a deterministic (sorted) order so that, when a record carries
    // more than one severity-like column with conflicting values, the "winning"
    // column is stable across runs rather than dependent on Set iteration order.
    for col in severityColumns.sorted() {
        guard let value = record[col] else { continue }
        let str: String
        switch value {
        case .string(let s): str = s
        case .int(let i):    str = String(i)
        // Numeric severities (e.g. OTel severity_number) sometimes decode as a
        // double; stringify the integral value so they still parse.
        case .double(let d) where d == d.rounded() && abs(d) < 1e15:
            str = String(format: "%.0f", d)
        default:             continue
        }
        // OpenTelemetry severity columns use a 1–24 scale that collides with
        // RFC 5424's 0–7, so disambiguate numeric values by column name.
        if otelSeverityColumns.contains(col.lowercased()),
           let num = Int(str.trimmingCharacters(in: .whitespaces)) {
            let level = parseOTelSeverityNumber(num)
            if level != .unknown { return level }
            continue
        }
        let level = parseSeverity(from: str)
        if level != .unknown { return level }
    }
    return .unknown
}

/// Returns a subtle background tint color for a severity level.
/// Info, debug, trace, and unknown levels return `nil` (no tint).
func severityRowTint(for level: SeverityLevel) -> Color? {
    switch level {
    case .fatal:   return Color.red.opacity(0.12)
    case .error:   return Color.red.opacity(0.07)
    case .warning: return Color.orange.opacity(0.07)
    case .info, .debug, .trace, .unknown: return nil
    }
}

/// Builds the set of column names (preserving original casing) that are severity columns.
func buildSeverityColumnSet(columns: [String]) -> Set<String> {
    var result = Set<String>()
    for col in columns {
        if severityColumnNames.contains(col.lowercased()) {
            result.insert(col)
        }
    }
    return result
}

// MARK: - LogTableView

struct IndexedRecord: Identifiable {
    let id: Int
    let record: LogRecord
    let severity: SeverityLevel
}

struct LogTableView: View {
    let records: [LogRecord]
    let columns: [String]
    @Binding var selectedRecord: LogRecord?
    var isLoading: Bool = false
    var wrapText: Bool = false
    var onCellFilter: ((_ column: String, _ value: JSONValue?, _ exclude: Bool) -> Void)?
    var onMoveColumn: ((String, String) -> Void)?
    @State private var sortColumn: String?
    @State private var sortAscending = false
    @State private var selectedIndex: Int?
    @State private var cachedSorted: [IndexedRecord] = []
    @State private var severityColumnSet: Set<String> = []
    @State private var sortTask: Task<Void, Never>?
    @State private var widthTask: Task<Void, Never>?
    @State private var columnWidths: [String: CGFloat] = [:]

    var body: some View {
        if records.isEmpty && isLoading {
            VStack(spacing: 8) {
                ProgressView()
                    .controlSize(.large)
                Text("Loading results...")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if records.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("No results")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HSplitView {
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(Array(cachedSorted.enumerated()), id: \.element.id) { index, item in
                                LogRowView(
                                    record: item.record,
                                    columns: columns,
                                    columnWidths: columnWidths,
                                    isSelected: selectedIndex == item.id,
                                    isAlternate: index % 2 == 1,
                                    severity: item.severity,
                                    severityColumns: severityColumnSet,
                                    wrapText: wrapText,
                                    onCellFilter: onCellFilter
                                )
                                .onTapGesture {
                                    if selectedIndex == item.id {
                                        selectedIndex = nil
                                        selectedRecord = nil
                                    } else {
                                        selectedIndex = item.id
                                        selectedRecord = item.record
                                    }
                                }
                            }
                        } header: {
                            LogHeaderView(
                                columns: columns,
                                sortColumn: $sortColumn,
                                sortAscending: $sortAscending,
                                columnWidths: $columnWidths,
                                records: records,
                                onMoveColumn: onMoveColumn,
                                onColumnFilter: onCellFilter
                            )
                        }
                    }
                }
                .frame(minWidth: 400)

                if let selected = selectedRecord {
                    LogDetailView(record: selected)
                        .frame(minWidth: 300, idealWidth: 350)
                }
            }
            .opacity(isLoading ? 0.5 : 1.0)
            .overlay {
                if isLoading {
                    ProgressView()
                        .controlSize(.large)
                }
            }
            .onChange(of: records) { _, newRecords in
                recomputeColumnWidths(columns: columns, records: newRecords)
                debouncedRebuildSort()
            }
            .onChange(of: columns) { _, newColumns in
                // New columns (e.g. shown via the Column Manager) need widths
                // computed; the width task otherwise only runs on a records
                // change, leaving them at the default width until the next query.
                recomputeColumnWidths(columns: newColumns, records: records)
                // After a stream switch the previous sort column may not exist
                // in the new schema, which would silently produce a no-op sort
                // (every row compares as .null). Drop it so rows fall back to
                // their natural order.
                if let sortColumn, !newColumns.contains(sortColumn) {
                    self.sortColumn = nil
                    // The sortColumn change triggers its own rebuild below.
                } else {
                    // Columns changed without dropping the sort column (e.g.
                    // hiding/showing a severity column via the Column Manager).
                    // Rebuild so the severity column set — and therefore row
                    // tinting — reflects the new columns.
                    debouncedRebuildSort()
                }
            }
            .onChange(of: sortColumn) { _, _ in debouncedRebuildSort() }
            .onChange(of: sortAscending) { _, _ in debouncedRebuildSort() }
            .onAppear {
                recomputeColumnWidths(columns: columns, records: records)
                rebuildSort()
            }
        }
    }

    /// Computes column widths off the main actor and merges them into
    /// `columnWidths`, filling only columns that don't yet have a width.
    /// Preserves any width the user dragged or auto-fit; a wholesale overwrite
    /// would discard manual resizes on every re-query/filter/refresh. Runs on
    /// both records changes and columns-only changes so newly shown columns get
    /// a fitted width rather than the default.
    private func recomputeColumnWidths(columns cols: [String], records recs: [LogRecord]) {
        widthTask?.cancel()
        widthTask = Task.detached(priority: .userInitiated) {
            let widths = computeColumnWidths(columns: cols, records: recs)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                var merged = columnWidths
                for (col, width) in widths where merged[col] == nil {
                    merged[col] = width
                }
                columnWidths = merged
            }
        }
    }

    private func debouncedRebuildSort() {
        sortTask?.cancel()
        sortTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let recs = records
            let col = sortColumn
            let asc = sortAscending
            let sevCols = buildSeverityColumnSet(columns: columns)
            let indexed: [IndexedRecord] = await Task.detached(priority: .userInitiated) {
                let enumerated = Array(recs.enumerated())
                let sorted: [(offset: Int, element: LogRecord)]
                if let col {
                    sorted = enumerated.sorted { a, b in
                        let aVal = a.element[col] ?? .null
                        let bVal = b.element[col] ?? .null
                        // `sorted(by:)` is not guaranteed stable, so break ties on
                        // the original index to keep equal-keyed rows in a fixed
                        // order across re-sorts (otherwise low-cardinality columns
                        // like `level`/`status` would reshuffle on every refresh).
                        if aVal != bVal { return asc ? aVal < bVal : bVal < aVal }
                        return a.offset < b.offset
                    }
                } else {
                    sorted = enumerated
                }
                return sorted.map {
                    IndexedRecord(id: $0.offset, record: $0.element, severity: extractSeverity(from: $0.element, severityColumns: sevCols))
                }
            }.value
            guard !Task.isCancelled else { return }
            cachedSorted = indexed
            severityColumnSet = sevCols
            reconcileSelection()
        }
    }

    /// Re-establishes the current selection after `cachedSorted` is rebuilt.
    /// Prefers the stable row id so a plain re-sort keeps the exact selected row
    /// (rather than jumping to the first duplicate). Falls back to value matching
    /// only when the records themselves changed, and clears both the index and
    /// the bound record when nothing matches so the detail pane can't go stale.
    private func reconcileSelection() {
        if let selectedIndex,
           let match = cachedSorted.first(where: { $0.id == selectedIndex }),
           match.record == selectedRecord {
            return
        }
        if let selectedRecord,
           let match = cachedSorted.first(where: { $0.record == selectedRecord }) {
            selectedIndex = match.id
        } else {
            selectedIndex = nil
            self.selectedRecord = nil
        }
    }

    private func rebuildSort() {
        let sevCols = buildSeverityColumnSet(columns: columns)
        let enumerated = Array(records.enumerated())
        let sorted: [(offset: Int, element: LogRecord)]
        if let sortColumn {
            sorted = enumerated.sorted { a, b in
                let aVal = a.element[sortColumn] ?? .null
                let bVal = b.element[sortColumn] ?? .null
                // Stable tiebreak on original index — see the async path above.
                if aVal != bVal { return sortAscending ? aVal < bVal : bVal < aVal }
                return a.offset < b.offset
            }
        } else {
            sorted = enumerated
        }
        cachedSorted = sorted.map {
            IndexedRecord(id: $0.offset, record: $0.element, severity: extractSeverity(from: $0.element, severityColumns: sevCols))
        }
        severityColumnSet = sevCols
        reconcileSelection()
    }
}

// MARK: - ColumnResizeHandle

struct ColumnResizeHandle: View {
    @Binding var columnWidth: CGFloat
    @State private var isHovering = false
    @State private var initialWidth: CGFloat?

    var body: some View {
        Color.clear
            .frame(width: 6)
            .overlay(
                Rectangle()
                    .fill(Color.secondary.opacity(isHovering ? 0.5 : 0.2))
                    .frame(width: 1)
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { gesture in
                        if initialWidth == nil {
                            initialWidth = columnWidth
                        }
                        let newWidth = (initialWidth ?? columnWidth) + gesture.translation.width
                        columnWidth = min(max(newWidth, 40), 1000)
                    }
                    .onEnded { _ in
                        initialWidth = nil
                    }
            )
    }
}

// MARK: - LogHeaderView

struct LogHeaderView: View {
    let columns: [String]
    @Binding var sortColumn: String?
    @Binding var sortAscending: Bool
    @Binding var columnWidths: [String: CGFloat]
    let records: [LogRecord]
    var onMoveColumn: ((String, String) -> Void)?
    var onColumnFilter: ((_ column: String, _ value: JSONValue?, _ exclude: Bool) -> Void)?

    @State private var draggedColumn: String?
    @State private var dropTargetColumn: String?
    @State private var uniqueValuesCache: [String: [JSONValue]] = [:]

    private static let maxFilterValues = 20

    private func uniqueValues(for column: String) -> [JSONValue] {
        if let cached = uniqueValuesCache[column] {
            return cached
        }
        var seen = Set<JSONValue>()
        var result: [JSONValue] = []
        for record in records {
            let value = record[column] ?? .null
            if seen.insert(value).inserted {
                result.append(value)
            }
        }
        let sorted = result.sorted()
        uniqueValuesCache[column] = sorted
        return sorted
    }

    private func dropIndicatorAlignment(for targetColumn: String) -> Alignment {
        guard let dragged = draggedColumn,
              let fromIndex = columns.firstIndex(of: dragged),
              let toIndex = columns.firstIndex(of: targetColumn) else {
            return .leading
        }
        return fromIndex < toIndex ? .trailing : .leading
    }

    private func filterDisplayLabel(for value: JSONValue) -> String {
        let str = value.displayString
        if str.isEmpty { return "(empty)" }
        if str.count > 50 { return String(str.prefix(50)) + "..." }
        return str
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(columns, id: \.self) { column in
                HStack(spacing: 0) {
                    HStack(spacing: 2) {
                        Text(column)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        if sortColumn == column {
                            Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if sortColumn == column {
                            sortAscending.toggle()
                        } else {
                            sortColumn = column
                            sortAscending = true
                        }
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(sortColumn == column
                        ? "Sort by \(column), \(sortAscending ? "ascending" : "descending")"
                        : "Sort by \(column)")

                    Spacer(minLength: 0)

                    ColumnResizeHandle(
                        columnWidth: Binding(
                            get: { columnWidths[column] ?? 120 },
                            set: { columnWidths[column] = $0 }
                        )
                    )
                }
                .frame(width: columnWidths[column] ?? 120, alignment: .leading)
                .background {
                    if dropTargetColumn == column && draggedColumn != nil && draggedColumn != column {
                        Color.accentColor.opacity(0.15)
                    }
                }
                .overlay(alignment: dropIndicatorAlignment(for: column)) {
                    if dropTargetColumn == column && draggedColumn != nil && draggedColumn != column {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: 2)
                    }
                }
                .onDrag {
                    draggedColumn = column
                    return NSItemProvider(object: column as NSString)
                }
                .onDrop(of: [UTType.plainText], delegate: ColumnDropDelegate(
                    column: column,
                    draggedColumn: $draggedColumn,
                    dropTargetColumn: $dropTargetColumn,
                    onMoveColumn: onMoveColumn
                ))
                .contextMenu {
                    if let onMove = onMoveColumn {
                        if column != columns.first {
                            Button("Move Left") {
                                let idx = columns.firstIndex(of: column)!
                                onMove(column, columns[columns.index(before: idx)])
                            }
                        }
                        if column != columns.last {
                            Button("Move Right") {
                                let idx = columns.firstIndex(of: column)!
                                onMove(column, columns[columns.index(after: idx)])
                            }
                        }
                        Divider()
                    }
                    Button("Auto-fit Column") {
                        columnWidths[column] = idealColumnWidth(for: column, records: records)
                    }
                    Button("Auto-fit All Columns") {
                        columnWidths = computeColumnWidths(columns: columns, records: records)
                    }

                    if let onFilter = onColumnFilter {
                        let values = uniqueValues(for: column)
                        if !values.isEmpty {
                            Divider()

                            let displayValues = Array(values.prefix(Self.maxFilterValues))
                            let remaining = values.count - displayValues.count

                            Menu("Filter by Value") {
                                ForEach(displayValues, id: \.self) { value in
                                    Button(filterDisplayLabel(for: value)) {
                                        onFilter(column, value == .null ? nil : value, false)
                                    }
                                }
                                if remaining > 0 {
                                    Divider()
                                    Text("\(remaining) more values not shown")
                                }
                            }

                            Menu("Exclude Value") {
                                ForEach(displayValues, id: \.self) { value in
                                    Button(filterDisplayLabel(for: value)) {
                                        onFilter(column, value == .null ? nil : value, true)
                                    }
                                }
                                if remaining > 0 {
                                    Divider()
                                    Text("\(remaining) more values not shown")
                                }
                            }
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .border(Color.secondary.opacity(0.2), width: 0.5)
        .onChange(of: records) { _, _ in
            uniqueValuesCache = [:]
        }
    }
}

// MARK: - ColumnDropDelegate

private struct ColumnDropDelegate: DropDelegate {
    let column: String
    @Binding var draggedColumn: String?
    @Binding var dropTargetColumn: String?
    var onMoveColumn: ((String, String) -> Void)?

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedColumn, dragged != column else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            dropTargetColumn = column
        }
    }

    func dropExited(info: DropInfo) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if dropTargetColumn == column {
                dropTargetColumn = nil
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let dragged = draggedColumn, dragged != column else {
            draggedColumn = nil
            dropTargetColumn = nil
            return false
        }
        onMoveColumn?(dragged, column)
        draggedColumn = nil
        dropTargetColumn = nil
        return true
    }

    func validateDrop(info: DropInfo) -> Bool {
        draggedColumn != nil && draggedColumn != column
    }
}

// MARK: - LogRowView

struct LogRowView: View {
    let record: LogRecord
    let columns: [String]
    let columnWidths: [String: CGFloat]
    let isSelected: Bool
    let isAlternate: Bool
    var severity: SeverityLevel = .unknown
    var severityColumns: Set<String> = []
    var wrapText: Bool = false
    var onCellFilter: ((_ column: String, _ value: JSONValue?, _ exclude: Bool) -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(columns, id: \.self) { column in
                let value = record[column]
                Text(value?.displayString ?? "")
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(wrapText ? nil : 1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .frame(width: columnWidths[column] ?? 120, alignment: .topLeading)
                    .foregroundStyle(colorForValue(column: column, value: value))
                    .contextMenu {
                        Button("Copy Value") {
                            // Use exportString, not displayString: the latter
                            // renders nested arrays/objects as placeholders like
                            // "[3 items]", so copying would lose the real data.
                            let text = value?.exportString ?? ""
                            NSPasteboard.general.clearContents()
                            _ = NSPasteboard.general.setString(text, forType: .string)
                        }
                        Button("Copy Column Name") {
                            NSPasteboard.general.clearContents()
                            _ = NSPasteboard.general.setString(column, forType: .string)
                        }
                        if let onCellFilter {
                            Divider()
                            // Normalize a null cell to `nil` so this produces an
                            // IS NULL / IS NOT NULL filter, matching the header
                            // "Filter by Value" path. Passing `.null` straight
                            // through would build an `= null` value filter, which
                            // the live-tail in-memory matcher treats differently.
                            let filterValue: JSONValue? = value == .null ? nil : value
                            Button("Filter by This Value") {
                                onCellFilter(column, filterValue, false)
                            }
                            Button("Exclude This Value") {
                                onCellFilter(column, filterValue, true)
                            }
                        }
                    }
            }
        }
        .background {
            if isSelected {
                Color.accentColor.opacity(0.2)
            } else {
                ZStack {
                    if isAlternate {
                        Color.primary.opacity(0.02)
                    }
                    if let tint = severityRowTint(for: severity) {
                        tint
                    }
                }
            }
        }
    }

    private func colorForValue(column: String, value: JSONValue?) -> Color {
        guard let value else { return .secondary }
        if severityColumns.contains(column) {
            return levelColor(for: value.displayString)
        }
        return .primary
    }
}
