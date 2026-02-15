import SwiftUI

struct LogDetailView: View {
    let record: LogRecord
    @State private var viewMode: ViewMode = .formatted

    enum ViewMode: String, CaseIterable {
        case formatted = "Formatted"
        case raw = "Raw JSON"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Log Entry")
                    .font(.headline)
                Spacer()
                Picker("View", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)

                Button {
                    copyToClipboard()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy to clipboard")
            }
            .padding(8)

            Divider()

            // Content
            ScrollView {
                switch viewMode {
                case .formatted:
                    FormattedRecordView(record: record)
                case .raw:
                    RawJSONView(record: record)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func copyToClipboard() {
        let dict = record.mapValues { $0 }
        if let data = try? JSONEncoder().encode(dict),
           let json = String(data: data, encoding: .utf8) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(json, forType: .string)
        }
    }
}

struct FormattedRecordView: View {
    let record: LogRecord

    var sortedKeys: [String] {
        let priority = ["p_timestamp", "level", "severity", "message", "msg"]
        var keys = record.keys.sorted()
        var result: [String] = []

        for p in priority {
            if let idx = keys.firstIndex(of: p) {
                result.append(keys.remove(at: idx))
            }
        }
        result.append(contentsOf: keys)
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(sortedKeys, id: \.self) { key in
                HStack(alignment: .top, spacing: 8) {
                    Text(key)
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .frame(width: 120, alignment: .trailing)

                    if let value = record[key] {
                        JSONValueView(value: value)
                    }

                    Spacer()
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .background(
                    sortedKeys.firstIndex(of: key).map { $0 % 2 == 1 }
                        ?? false ? Color.primary.opacity(0.03) : Color.clear
                )
            }
        }
        .padding(.vertical, 4)
    }
}

struct JSONValueView: View {
    let value: JSONValue

    var body: some View {
        switch value {
        case .null:
            Text("null")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        case .bool(let v):
            Text(v ? "true" : "false")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.purple)
        case .int(let v):
            Text(String(v))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.blue)
        case .double(let v):
            Text(String(v))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.blue)
        case .string(let v):
            Text(v)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        case .array(let items):
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .top) {
                        Text("[\(idx)]")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                        JSONValueView(value: item)
                    }
                }
            }
        case .object(let dict):
            VStack(alignment: .leading, spacing: 2) {
                ForEach(dict.keys.sorted(), id: \.self) { key in
                    HStack(alignment: .top) {
                        Text("\(key):")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                        if let val = dict[key] {
                            JSONValueView(value: val)
                        }
                    }
                }
            }
        }
    }
}

struct RawJSONView: View {
    let record: LogRecord

    var jsonString: String {
        let obj = JSONValue.object(record)
        return obj.prettyPrinted()
    }

    var body: some View {
        Text(jsonString)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
