import SwiftUI

/// Shared column width logic used by both header and row views.
func columnWidth(for column: String) -> CGFloat {
    switch column {
    case "p_timestamp", "timestamp", "@timestamp", "time":
        return 200
    case "level", "severity", "log_level":
        return 80
    case "message", "msg", "body", "log":
        return 400
    default:
        return 160
    }
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

struct LogTableView: View {
    let records: [LogRecord]
    let columns: [String]
    @Binding var selectedRecord: LogRecord?
    @State private var sortColumn: String?
    @State private var sortAscending = false
    @State private var selectedIndex: Int?
    @State private var cachedSorted: [LogRecord] = []

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
                                    isSelected: selectedIndex == index,
                                    isAlternate: index % 2 == 1
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
                                sortAscending: $sortAscending
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
            .onChange(of: records.count) { _, _ in rebuildSort() }
            .onChange(of: sortColumn) { _, _ in rebuildSort() }
            .onChange(of: sortAscending) { _, _ in rebuildSort() }
            .onAppear { rebuildSort() }
        }
    }

    private func rebuildSort() {
        if let sortColumn {
            cachedSorted = records.sorted { a, b in
                let aVal = a[sortColumn]?.displayString ?? ""
                let bVal = b[sortColumn]?.displayString ?? ""
                return sortAscending ? aVal < bVal : aVal > bVal
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

struct LogHeaderView: View {
    let columns: [String]
    @Binding var sortColumn: String?
    @Binding var sortAscending: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach(columns, id: \.self) { column in
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
                .frame(width: columnWidth(for: column), alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .border(Color.secondary.opacity(0.2), width: 0.5)
    }
}

struct LogRowView: View {
    let record: LogRecord
    let columns: [String]
    let isSelected: Bool
    let isAlternate: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach(columns, id: \.self) { column in
                let value = record[column]
                Text(value?.displayString ?? "")
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .frame(width: columnWidth(for: column), alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .foregroundStyle(colorForValue(column: column, value: value))
                    .contextMenu {
                        Button("Copy Value") {
                            let text = value?.displayString ?? ""
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        }
                        Button("Copy Column Name") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(column, forType: .string)
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
