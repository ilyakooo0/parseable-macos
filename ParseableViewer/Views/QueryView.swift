import SwiftUI

/// Composite of the inputs that decide which query QueryView should run. Watched
/// by a single `.onChange` so a stream switch and a pending saved-filter (which
/// arrive in the same update) are handled together in one pass — two separate
/// `.onChange` handlers would race and could clobber the filter with the default
/// query depending on their firing order.
private struct QueryViewContext: Equatable {
    let stream: String?
    let pendingSQL: String?
}

struct QueryView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = QueryViewModel()
    @State private var showSaveFilterSheet = false
    @State private var saveFilterName = ""
    @State private var isSavingFilter = false
    @State private var saveFilterError: String?
    @State private var exportError: String?
    @State private var showExportError = false
    @State private var showColumnPopover = false
    @State private var wrapText = false

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
                        customEnd: $vm.customEndDate,
                        onCommit: {
                            guard appState.selectedStream != nil else { return }
                            Task {
                                await viewModel.executeQuery(
                                    client: appState.client,
                                    stream: appState.selectedStream
                                )
                            }
                        }
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
                        showSaveFilterSheet = true
                    } label: {
                        Text("Save view")
                    }
                    .help("Save filter")
                    .disabled(viewModel.sqlQuery.isEmpty)
                    .accessibilityLabel("Save filter")

                    Button {
                        exportResults()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(viewModel.filteredResults.isEmpty)
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
                    schemaFields: viewModel.schemaFields,
                    errorRange: viewModel.errorRange
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

                        Button {
                            wrapText.toggle()
                        } label: {
                            Image(systemName: wrapText ? "text.word.spacing" : "text.line.first.and.arrowtriangle.forward")
                        }
                        .help(wrapText ? "Disable text wrapping" : "Enable text wrapping")
                        .accessibilityLabel(wrapText ? "Disable text wrapping" : "Enable text wrapping")

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
                    wrapText: wrapText,
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
        .onChange(of: QueryViewContext(stream: appState.selectedStream, pendingSQL: appState.pendingFilterSQL)) { old, new in
            guard let stream = new.stream else {
                viewModel.clearResults()
                return
            }
            let streamChanged = old.stream != new.stream
            if streamChanged {
                viewModel.clearResults()
                Task {
                    await viewModel.loadSchema(client: appState.client, stream: stream)
                }
            }
            // A pending saved filter (set together with the stream switch, or on
            // its own for the already-selected stream) takes priority over the
            // default query. Consuming it here in the same handler that owns the
            // stream switch avoids the previous two-handler race.
            if let sql = appState.pendingFilterSQL {
                appState.pendingFilterSQL = nil
                viewModel.sqlQuery = sql
                Task {
                    await viewModel.executeQuery(client: appState.client, stream: stream)
                }
            } else if streamChanged {
                let didSetDefault = viewModel.setDefaultQuery(stream: stream, previousStream: old.stream)
                if didSetDefault {
                    Task {
                        await viewModel.executeQuery(client: appState.client, stream: stream)
                    }
                }
            }
        }
        .onChange(of: viewModel.timeRangeOption) { _, newValue in
            guard newValue != .custom, appState.selectedStream != nil else { return }
            Task {
                await viewModel.executeQuery(
                    client: appState.client,
                    stream: appState.selectedStream
                )
            }
        }
        .onAppear {
            if let stream = appState.selectedStream {
                // Reload the schema when it's missing OR when the loaded schema
                // belongs to a different stream than the current one — otherwise a
                // viewModel that survives with another stream's schema would keep
                // autocomplete pointed at the wrong stream's fields until the next
                // stream switch.
                if viewModel.schemaFields.isEmpty || viewModel.latestSchemaStream != stream {
                    Task {
                        await viewModel.loadSchema(client: appState.client, stream: stream)
                    }
                }
                // A saved filter may have set pendingFilterSQL before this view was
                // mounted (e.g. the filter was launched from another tab). .onChange
                // doesn't fire for a value that changed before the view entered the
                // hierarchy, so honor it here instead of overwriting the editor with
                // the default query.
                if let sql = appState.pendingFilterSQL {
                    viewModel.sqlQuery = sql
                    appState.pendingFilterSQL = nil
                    Task {
                        await viewModel.executeQuery(
                            client: appState.client,
                            stream: stream
                        )
                    }
                } else {
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
        }
        .onDisappear {
            if viewModel.isLoading {
                viewModel.cancelQuery()
            }
        }
        .onChange(of: appState.queryRefreshToken) { _, _ in
            // Guard on a selected stream like every sibling query trigger in this
            // view. Without it, a refresh (Cmd+R) with no stream selected and an
            // empty editor surfaces a spurious "Select a stream..." error.
            guard appState.selectedStream != nil else { return }
            Task {
                await viewModel.executeQuery(
                    client: appState.client,
                    stream: appState.selectedStream
                )
            }
        }
        .alert("Export Error", isPresented: $showExportError) {
            Button("OK") {}
        } message: {
            Text(exportError ?? "Unknown error")
        }
        .sheet(isPresented: $showSaveFilterSheet) {
            VStack(spacing: 16) {
                Text("Save Filter")
                    .font(.headline)
                TextField("Filter name", text: $saveFilterName)
                    .textFieldStyle(.roundedBorder)
                if let error = saveFilterError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                HStack {
                    Button("Cancel") {
                        saveFilterError = nil
                        showSaveFilterSheet = false
                    }
                    Spacer()
                    Button("Save") {
                        isSavingFilter = true
                        saveFilterError = nil
                        Task {
                            do {
                                try await appState.saveFilter(
                                    name: saveFilterName,
                                    sql: viewModel.sqlQuery,
                                    stream: appState.selectedStream ?? ""
                                )
                                saveFilterName = ""
                                showSaveFilterSheet = false
                            } catch {
                                saveFilterError = ParseableError.userFriendlyMessage(for: error)
                            }
                            isSavingFilter = false
                        }
                    }
                    .disabled(saveFilterName.isEmpty || isSavingFilter)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .frame(width: 350)
        }
    }

    private func exportResults() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json, .commaSeparatedText]
        panel.nameFieldStringValue = "export.json"
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            let isCSV = url.pathExtension.lowercased() == "csv"
            // Export what's on screen: the table renders `filteredResults`, so a
            // user who has typed a result filter expects the export to contain
            // those rows, not the full unfiltered set.
            let results = viewModel.filteredResults
            let columns = viewModel.visibleColumns
            Task.detached(priority: .userInitiated) {
                let content: String?
                if isCSV {
                    content = QueryViewModel.buildCSV(records: results, columns: columns)
                } else {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    // Project to visible columns so JSON export matches CSV and
                    // doesn't leak hidden fields.
                    let projected = QueryViewModel.projectRecords(results, to: columns)
                    content = (try? encoder.encode(projected))
                        .flatMap { String(data: $0, encoding: .utf8) }
                }
                guard let content else {
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
