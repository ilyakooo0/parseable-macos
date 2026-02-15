import SwiftUI

struct QueryView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = QueryViewModel()
    @State private var showSaveQuerySheet = false
    @State private var saveQueryName = ""
    @State private var exportError: String?
    @State private var showExportError = false
    @State private var showColumnPopover = false

    var body: some View {
        @Bindable var vm = viewModel

        VSplitView {
            // Query editor panel
            VStack(spacing: 0) {
                // Toolbar
                HStack {
                    TimeRangePicker(
                        option: $vm.timeRangeOption,
                        customStart: $vm.customStartDate,
                        customEnd: $vm.customEndDate
                    )

                    Spacer()

                    if !viewModel.queryHistory.isEmpty {
                        Menu {
                            if viewModel.historyIsFull {
                                Text("History limit reached (oldest entries removed)")
                                Divider()
                            }
                            ForEach(viewModel.queryHistory.prefix(15)) { entry in
                                Button {
                                    viewModel.sqlQuery = entry.sql
                                } label: {
                                    VStack(alignment: .leading) {
                                        Text(entry.sql.prefix(80))
                                        Text("\(entry.resultCount) rows - \(entry.executedAt.formatted(.dateTime.month().day().hour().minute()))")
                                            .font(.caption2)
                                    }
                                }
                            }
                            Divider()
                            Button("Clear History", role: .destructive) {
                                viewModel.clearHistory()
                            }
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                        .help(viewModel.historyIsFull ? "Query history (full)" : "Query history")
                        .accessibilityLabel("Query history")
                    }

                    Button {
                        showSaveQuerySheet = true
                    } label: {
                        Image(systemName: "bookmark")
                    }
                    .help("Save query")
                    .disabled(viewModel.sqlQuery.isEmpty)
                    .accessibilityLabel("Save query")

                    Menu {
                        Button("Export as JSON") { exportJSON() }
                        Button("Export as CSV") { exportCSV() }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(viewModel.results.isEmpty)
                    .accessibilityLabel("Export results")
                    .help("Export results")

                    if viewModel.isLoading {
                        Button {
                            viewModel.cancelQuery()
                        } label: {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Cancel")
                            }
                        }
                        .keyboardShortcut(.escape, modifiers: [])
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .accessibilityLabel("Cancel running query")
                    } else {
                        Button {
                            Task {
                                await viewModel.executeQuery(
                                    client: appState.client,
                                    stream: appState.selectedStream
                                )
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
                                Text("Run")
                            }
                        }
                        .keyboardShortcut(.return, modifiers: .command)
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(8)

                // SQL editor
                SQLEditorView(
                    text: $vm.sqlQuery,
                    streamNames: appState.streams.map(\.name),
                    schemaFields: viewModel.schemaFields
                )
                    .frame(minHeight: 60, maxHeight: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.2))
                    )
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                    .accessibilityLabel("SQL query editor")

                // Truncation warning
                if viewModel.resultsTruncated {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("Results may be truncated. Increase the LIMIT or narrow your query to see all data.")
                        Spacer()
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.1))
                }

                // Status bar
                HStack {
                    if let error = viewModel.errorMessage {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                        Text(error)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    } else if viewModel.resultCount > 0 {
                        Text("\(viewModel.resultCount) results")
                        if let duration = viewModel.queryDuration {
                            Text("(\(String(format: "%.2fs", duration)))")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Enter a SQL query or press Run to query the selected stream")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)

                Divider()
            }
            .frame(minHeight: 120)

            // Results panel
            VStack(spacing: 0) {
                // Filter bar
                if !viewModel.results.isEmpty {
                    HStack {
                        Image(systemName: "line.3.horizontal.decrease")
                            .foregroundStyle(.secondary)
                        TextField("Filter results...", text: $vm.filterText)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 300)
                            .accessibilityLabel("Filter query results")

                        if !viewModel.filterText.isEmpty {
                            Text("\(viewModel.filteredResults.count) of \(viewModel.results.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if !viewModel.columns.isEmpty {
                            Button {
                                showColumnPopover.toggle()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "eye")
                                    Text("Columns")
                                        .font(.caption)
                                    if !viewModel.hiddenColumns.isEmpty || !viewModel.autoHiddenColumns.isEmpty {
                                        Text("(\(viewModel.visibleColumns.count)/\(viewModel.columns.count))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .accessibilityLabel("Manage column visibility and order")
                            .help("Show, hide, and reorder columns")
                            .popover(isPresented: $showColumnPopover, arrowEdge: .bottom) {
                                ColumnManagerView(viewModel: viewModel)
                            }
                        }
                    }
                    .padding(6)
                }

                // Results table
                LogTableView(
                    records: viewModel.filteredResults,
                    columns: viewModel.visibleColumns,
                    selectedRecord: $vm.selectedLogEntry,
                    isLoading: viewModel.isLoading,
                    onCellFilter: { column, value, exclude in
                        viewModel.addColumnFilter(column: column, value: value, exclude: exclude)
                        Task {
                            await viewModel.executeQuery(
                                client: appState.client,
                                stream: appState.selectedStream
                            )
                        }
                    },
                    onMoveColumn: { from, to in
                        viewModel.moveColumn(from, to: to)
                    }
                )
            }
        }
        .onChange(of: appState.selectedStream) { oldValue, newValue in
            viewModel.clearResults()
            if let stream = newValue {
                let didSetDefault = viewModel.setDefaultQuery(stream: stream, previousStream: oldValue)
                Task {
                    await viewModel.loadSchema(client: appState.client, stream: stream)
                }
                if didSetDefault {
                    Task {
                        await viewModel.executeQuery(
                            client: appState.client,
                            stream: stream
                        )
                    }
                }
            }
        }
        .onAppear {
            if let stream = appState.selectedStream {
                if viewModel.schemaFields.isEmpty {
                    Task {
                        await viewModel.loadSchema(client: appState.client, stream: stream)
                    }
                }
                let didSetDefault = viewModel.setDefaultQuery(stream: stream)
                if didSetDefault && viewModel.results.isEmpty {
                    Task {
                        await viewModel.executeQuery(
                            client: appState.client,
                            stream: stream
                        )
                    }
                }
            }
        }
        .onDisappear {
            if viewModel.isLoading {
                viewModel.cancelQuery()
            }
        }
        .onChange(of: appState.pendingSavedQuerySQL) { _, newSQL in
            if let sql = newSQL {
                viewModel.sqlQuery = sql
                appState.pendingSavedQuerySQL = nil
            }
        }
        .alert("Export Error", isPresented: $showExportError) {
            Button("OK") {}
        } message: {
            Text(exportError ?? "Unknown error")
        }
        .sheet(isPresented: $showSaveQuerySheet) {
            VStack(spacing: 16) {
                Text("Save Query")
                    .font(.headline)
                TextField("Query name", text: $saveQueryName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Cancel") { showSaveQuerySheet = false }
                    Spacer()
                    Button("Save") {
                        let query = SavedQuery(
                            name: saveQueryName,
                            sql: viewModel.sqlQuery,
                            stream: appState.selectedStream ?? ""
                        )
                        appState.addSavedQuery(query)
                        saveQueryName = ""
                        showSaveQuerySheet = false
                    }
                    .disabled(saveQueryName.isEmpty)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .frame(width: 350)
        }
    }

    private func exportJSON() {
        let results = viewModel.results
        saveToFile(type: "json") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            do {
                let data = try encoder.encode(results)
                return String(data: data, encoding: .utf8) ?? "[]"
            } catch {
                return nil
            }
        }
    }

    private func exportCSV() {
        let results = viewModel.results
        let columns = viewModel.visibleColumns
        saveToFile(type: "csv") {
            QueryViewModel.buildCSV(records: results, columns: columns)
        }
    }

    private func saveToFile(type: String, generate: @Sendable @escaping () -> String?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = type == "json" ? [.json] : [.commaSeparatedText]
        panel.nameFieldStringValue = "export.\(type)"
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            Task.detached(priority: .userInitiated) {
                guard let content = generate() else {
                    await MainActor.run {
                        exportError = "Failed to encode data for export"
                        showExportError = true
                    }
                    return
                }
                do {
                    try content.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    await MainActor.run {
                        exportError = "Export failed: \(error.localizedDescription)"
                        showExportError = true
                    }
                }
            }
        }
    }
}

// MARK: - Column Manager Popover

struct ColumnManagerView: View {
    let viewModel: QueryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Columns")
                    .font(.headline)
                Spacer()
                if !viewModel.hiddenColumns.isEmpty || !viewModel.autoHiddenColumns.isEmpty || viewModel.columnOrder != viewModel.columns {
                    Button("Reset") {
                        viewModel.resetColumnConfig()
                    }
                    .font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()

            List {
                ForEach(viewModel.columnOrder, id: \.self) { column in
                    let isHidden = viewModel.hiddenColumns.contains(column)
                        || viewModel.autoHiddenColumns.contains(column)
                    HStack {
                        Button {
                            viewModel.toggleColumnVisibility(column)
                        } label: {
                            Image(systemName: isHidden ? "eye.slash" : "eye")
                                .foregroundStyle(isHidden ? .secondary : .primary)
                                .frame(width: 20)
                        }
                        .buttonStyle(.plain)
                        .help(isHidden ? "Show column" : "Hide column")

                        Text(column)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .foregroundStyle(isHidden ? .secondary : .primary)

                        Spacer()

                        if viewModel.autoHiddenColumns.contains(column) {
                            Text("empty")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .padding(.trailing, 4)
                        }

                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                    }
                    .padding(.vertical, 2)
                }
                .onMove { source, destination in
                    viewModel.moveColumn(from: source, to: destination)
                }
            }
            .listStyle(.plain)

            if !viewModel.hiddenColumns.isEmpty || !viewModel.autoHiddenColumns.isEmpty {
                Divider()
                Button("Show All Columns") {
                    viewModel.showAllColumns()
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .frame(width: 280, height: min(CGFloat(viewModel.columnOrder.count) * 32 + 80, 400))
    }
}
