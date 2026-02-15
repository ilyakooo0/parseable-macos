import SwiftUI

struct LogTableView: View {
    let records: [LogRecord]
    let columns: [String]
    @Binding var selectedRecord: LogRecord?
    @State private var sortColumn: String?
    @State private var sortAscending = false

    var sortedRecords: [LogRecord] {
        guard let sortColumn else { return records }
        return records.sorted { a, b in
            let aVal = a[sortColumn]?.displayString ?? ""
            let bVal = b[sortColumn]?.displayString ?? ""
            return sortAscending ? aVal < bVal : aVal > bVal
        }
    }

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
                // Table
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(Array(sortedRecords.enumerated()), id: \.offset) { index, record in
                                LogRowView(
                                    record: record,
                                    columns: columns,
                                    isSelected: selectedRecord == record,
                                    isAlternate: index % 2 == 1
                                )
                                .onTapGesture {
                                    selectedRecord = record
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

                // Detail pane
                if let selected = selectedRecord {
                    LogDetailView(record: selected)
                        .frame(minWidth: 300, idealWidth: 350)
                }
            }
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

    private func columnWidth(for column: String) -> CGFloat {
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
            }
        }
        .background(
            isSelected
                ? Color.accentColor.opacity(0.2)
                : (isAlternate ? Color.primary.opacity(0.02) : Color.clear)
        )
    }

    private func columnWidth(for column: String) -> CGFloat {
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

    private func colorForValue(column: String, value: JSONValue?) -> Color {
        guard let value else { return .secondary }
        if column == "level" || column == "severity" || column == "log_level" {
            let str = value.displayString.lowercased()
            switch str {
            case "error", "fatal", "critical", "panic": return .red
            case "warn", "warning": return .orange
            case "info": return .blue
            case "debug", "trace": return .secondary
            default: return .primary
            }
        }
        return .primary
    }
}
