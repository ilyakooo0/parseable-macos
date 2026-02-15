import SwiftUI

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
    for i in 0..<sampleCount {
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

// MARK: - LogTableView

struct LogTableView: View {
    let records: [LogRecord]
    let columns: [String]
    @Binding var selectedRecord: LogRecord?
    var onCellFilter: ((_ column: String, _ value: JSONValue?, _ exclude: Bool) -> Void)?
    var onMoveColumn: ((String, String) -> Void)?
    @State private var sortColumn: String?
    @State private var sortAscending = false
    @State private var selectedIndex: Int?
    @State private var cachedSorted: [LogRecord] = []
    @State private var sortTask: Task<Void, Never>?
    @State private var columnWidths: [String: CGFloat] = [:]

    var body: some View {
        if records.isEmpty {
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
                            ForEach(cachedSorted.indices, id: \.self) { index in
                                LogRowView(
                                    record: cachedSorted[index],
                                    columns: columns,
                                    columnWidths: columnWidths,
                                    isSelected: selectedIndex == index,
                                    isAlternate: index % 2 == 1,
                                    onCellFilter: onCellFilter
                                )
                                .onTapGesture {
                                    selectedIndex = index
                                    selectedRecord = cachedSorted[index]
                                }
                            }
                        } header: {
                            LogHeaderView(
                                columns: columns,
                                sortColumn: $sortColumn,
                                sortAscending: $sortAscending,
                                columnWidths: $columnWidths,
                                records: records,
                                onMoveColumn: onMoveColumn
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
            .onChange(of: records) { _, _ in
                columnWidths = computeColumnWidths(columns: columns, records: records)
                debouncedRebuildSort()
            }
            .onChange(of: sortColumn) { _, _ in debouncedRebuildSort() }
            .onChange(of: sortAscending) { _, _ in debouncedRebuildSort() }
            .onAppear {
                columnWidths = computeColumnWidths(columns: columns, records: records)
                rebuildSort()
            }
        }
    }

    private func debouncedRebuildSort() {
        sortTask?.cancel()
        sortTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            rebuildSort()
        }
    }

    private func rebuildSort() {
        if let sortColumn {
            cachedSorted = records.sorted { a, b in
                let aVal = a[sortColumn] ?? .null
                let bVal = b[sortColumn] ?? .null
                return sortAscending ? aVal < bVal : bVal < aVal
            }
        } else {
            cachedSorted = records
        }
        if let selectedRecord,
           let idx = cachedSorted.firstIndex(where: { $0 == selectedRecord }) {
            selectedIndex = idx
        } else {
            selectedIndex = nil
        }
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
                DragGesture(minimumDistance: 1)
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

    var body: some View {
        HStack(spacing: 0) {
            ForEach(columns, id: \.self) { column in
                HStack(spacing: 0) {
                    Button {
                        if sortColumn == column {
                            sortAscending.toggle()
                        } else {
                            sortColumn = column
                            sortAscending = true
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Text(column)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            if sortColumn == column {
                                Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                    .font(.caption2)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
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
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .border(Color.secondary.opacity(0.2), width: 0.5)
    }
}

// MARK: - LogRowView

struct LogRowView: View {
    let record: LogRecord
    let columns: [String]
    let columnWidths: [String: CGFloat]
    let isSelected: Bool
    let isAlternate: Bool
    var onCellFilter: ((_ column: String, _ value: JSONValue?, _ exclude: Bool) -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(columns, id: \.self) { column in
                let value = record[column]
                Text(value?.displayString ?? "")
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .frame(width: columnWidths[column] ?? 120, alignment: .leading)
                    .foregroundStyle(colorForValue(column: column, value: value))
                    .contextMenu {
                        Button("Copy Value") {
                            let text = value?.displayString ?? ""
                            NSPasteboard.general.clearContents()
                            _ = NSPasteboard.general.setString(text, forType: .string)
                        }
                        Button("Copy Column Name") {
                            NSPasteboard.general.clearContents()
                            _ = NSPasteboard.general.setString(column, forType: .string)
                        }
                        if let onCellFilter {
                            Divider()
                            Button("Filter by This Value") {
                                onCellFilter(column, value, false)
                            }
                            Button("Exclude This Value") {
                                onCellFilter(column, value, true)
                            }
                        }
                    }
            }
        }
        .background(
            isSelected
                ? Color.accentColor.opacity(0.2)
                : (isAlternate ? Color.primary.opacity(0.02) : Color.clear)
        )
    }

    private func colorForValue(column: String, value: JSONValue?) -> Color {
        guard let value else { return .secondary }
        if column == "level" || column == "severity" || column == "log_level" {
            return levelColor(for: value.displayString)
        }
        return .primary
    }
}
