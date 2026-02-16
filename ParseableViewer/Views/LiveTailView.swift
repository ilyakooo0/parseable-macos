import SwiftUI

struct LiveTailView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = LiveTailViewModel()
    @State private var selectedRecord: LogRecord?
    @State private var autoScroll = true
    @State private var pulseOpacity: Double = 1.0
    @State private var showColumnPopover = false
    @State private var wrapText = false
    @State private var sortColumn: String?
    @State private var sortAscending = false
    @State private var columnWidths: [String: CGFloat] = [:]
    @State private var cachedSorted: [LiveTailViewModel.LiveTailEntry] = []
    @State private var cachedSeverities: [SeverityLevel] = []
    @State private var severityColumnSet: Set<String> = []
    @State private var liveTailSortTask: Task<Void, Never>?

    var body: some View {
        @Bindable var vm = viewModel

        HSplitView {
            VStack(spacing: 0) {
                // Toolbar
                HStack {
                    if viewModel.isRunning {
                        Button {
                            viewModel.stop()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "stop.fill")
                                Text("Stop")
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .accessibilityLabel("Stop live tail")

                        Button {
                            viewModel.togglePause()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                                Text(viewModel.isPaused ? "Resume" : "Pause")
                            }
                        }
                        .keyboardShortcut("p", modifiers: .command)
                        .accessibilityLabel(viewModel.isPaused ? "Resume live tail" : "Pause live tail")
                    } else {
                        Button {
                            viewModel.start(
                                client: appState.client,
                                stream: appState.selectedStream
                            )
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                Text("Start Live Tail")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!appState.isConnected || appState.selectedStream == nil)
                        .accessibilityLabel("Start live tail")
                    }

                    Spacer()

                    // Filter
                    HStack {
                        Image(systemName: "line.3.horizontal.decrease")
                            .foregroundStyle(.secondary)
                        TextField("Filter...", text: $vm.filterText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                            .accessibilityLabel("Filter live tail entries")
                    }

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
                                if !viewModel.hiddenColumns.isEmpty {
                                    Text("(\(viewModel.visibleColumns.count)/\(viewModel.columns.count))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityLabel("Manage column visibility and order")
                        .help("Show, hide, and reorder columns")
                        .popover(isPresented: $showColumnPopover, arrowEdge: .bottom) {
                            LiveTailColumnManagerView(viewModel: viewModel)
                        }
                    }

                    Toggle("Auto-scroll", isOn: $autoScroll)
                        .toggleStyle(.checkbox)

                    Button {
                        viewModel.clear()
                        selectedRecord = nil
                        sortColumn = nil
                        columnWidths = [:]
                        cachedSorted = []
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Clear entries")
                    .keyboardShortcut(.delete, modifiers: .command)
                    .accessibilityLabel("Clear all entries")
                }
                .padding(8)

                Divider()

                // Status bar
                HStack {
                    if viewModel.isRunning {
                        Circle()
                            .fill(viewModel.isPaused ? .yellow : .green)
                            .frame(width: 8, height: 8)
                            .opacity(viewModel.isPaused ? 1.0 : pulseOpacity)
                            .accessibilityLabel(viewModel.isPaused ? "Status: Paused" : "Status: Streaming")
                            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulseOpacity)
                            .onAppear { pulseOpacity = 0.3 }
                            .onDisappear { pulseOpacity = 1.0 }
                        Text(viewModel.isPaused ? "Paused" : "Streaming")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let error = viewModel.errorMessage {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.yellow)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .lineLimit(1)
                    }

                    Spacer()

                    if viewModel.droppedCount > 0 {
                        Text("\(viewModel.droppedCount) dropped")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .help("Oldest entries were removed to stay within the \(viewModel.maxEntries)-entry buffer limit")
                    }

                    Text("\(viewModel.displayedCount) entries")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if (!viewModel.filterText.isEmpty || !viewModel.columnFilters.isEmpty) && viewModel.displayedCount != viewModel.entryCount {
                        Text("(of \(viewModel.entryCount) total)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.bar)

                Divider()

                // Active column filters
                if !viewModel.columnFilters.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(viewModel.columnFilters) { filter in
                                    HStack(spacing: 2) {
                                        Text(filter.displayLabel)
                                            .font(.caption)
                                            .lineLimit(1)
                                        Button {
                                            viewModel.removeColumnFilter(filter)
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 8, weight: .bold))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(filter.exclude
                                                  ? Color.red.opacity(0.15)
                                                  : Color.accentColor.opacity(0.15))
                                    )
                                }
                            }
                        }

                        Spacer()

                        Button("Clear All") {
                            viewModel.clearColumnFilters()
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)

                    Divider()
                }

                // Column table or empty state
                if viewModel.visibleColumns.isEmpty {
                    VStack(spacing: 8) {
                        if !viewModel.isRunning {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 32))
                                .foregroundStyle(.secondary)
                            Text("Start live tail to stream log entries")
                                .foregroundStyle(.secondary)
                        } else {
                            ProgressView()
                                .controlSize(.small)
                            Text("Waiting for entries...")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    liveTailTable
                }
            }
            .frame(minWidth: 400)

            // Detail pane
            if let record = selectedRecord {
                LogDetailView(record: record)
                    .frame(minWidth: 280, idealWidth: 320)
            }
        }
        .onDisappear {
            viewModel.stop()
        }
        .onChange(of: appState.selectedStream) { _, _ in
            if viewModel.isRunning {
                viewModel.stop()
            }
            viewModel.clear()
            selectedRecord = nil
            sortColumn = nil
            columnWidths = [:]
            cachedSorted = []
        }
        .onChange(of: viewModel.visibleColumns) { _, newColumns in
            // Compute widths for any newly visible columns
            let records = viewModel.cachedFilteredRecords
            for col in newColumns where columnWidths[col] == nil {
                columnWidths[col] = idealColumnWidth(for: col, records: records)
            }
        }
        .onAppear {
            rebuildSortedEntries()
        }
    }

    private func rebuildSortedEntries() {
        let entries = viewModel.cachedFilteredEntries
        let cols = viewModel.visibleColumns
        let sevCols = buildSeverityColumnSet(columns: cols)
        guard let col = sortColumn else {
            cachedSorted = entries
            cachedSeverities = entries.map { extractSeverity(from: $0.record, severityColumns: sevCols) }
            severityColumnSet = sevCols
            return
        }
        liveTailSortTask?.cancel()
        let asc = sortAscending
        liveTailSortTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let sorted = await Task.detached(priority: .userInitiated) {
                entries.sorted { a, b in
                    let aVal = a.record[col] ?? .null
                    let bVal = b.record[col] ?? .null
                    return asc ? aVal < bVal : bVal < aVal
                }
            }.value
            guard !Task.isCancelled else { return }
            cachedSorted = sorted
            cachedSeverities = sorted.map { extractSeverity(from: $0.record, severityColumns: sevCols) }
            severityColumnSet = sevCols
        }
    }

    private var liveTailTable: some View {
        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(Array(cachedSorted.enumerated()), id: \.element.id) { index, entry in
                            LogRowView(
                                record: entry.record,
                                columns: viewModel.visibleColumns,
                                columnWidths: columnWidths,
                                isSelected: selectedRecord == entry.record,
                                isAlternate: index % 2 == 1,
                                severity: index < cachedSeverities.count ? cachedSeverities[index] : .unknown,
                                severityColumns: severityColumnSet,
                                wrapText: wrapText,
                                onCellFilter: { column, value, exclude in
                                    viewModel.addColumnFilter(column: column, value: value, exclude: exclude)
                                }
                            )
                            .onTapGesture {
                                if selectedRecord == entry.record {
                                    selectedRecord = nil
                                } else {
                                    selectedRecord = entry.record
                                }
                            }
                        }
                    } header: {
                        LogHeaderView(
                            columns: viewModel.visibleColumns,
                            sortColumn: $sortColumn,
                            sortAscending: $sortAscending,
                            columnWidths: $columnWidths,
                            records: viewModel.cachedFilteredRecords,
                            onMoveColumn: { from, to in
                                viewModel.moveColumn(from, to: to)
                            },
                            onColumnFilter: { column, value, exclude in
                                viewModel.addColumnFilter(column: column, value: value, exclude: exclude)
                            }
                        )
                    }
                }
            }
            .onChange(of: viewModel.filteredEntriesGeneration) { _, _ in
                rebuildSortedEntries()
            }
            .onChange(of: sortColumn) { _, _ in
                rebuildSortedEntries()
            }
            .onChange(of: sortAscending) { _, _ in
                rebuildSortedEntries()
            }
            .onChange(of: viewModel.entries.count) { _, _ in
                guard autoScroll, sortColumn == nil else { return }
                let hasFilters = !viewModel.filterText.isEmpty || !viewModel.columnFilters.isEmpty
                let target = hasFilters
                    ? viewModel.cachedFilteredEntries.last
                    : viewModel.entries.last
                if let target {
                    proxy.scrollTo(target.id, anchor: .bottom)
                }
            }
        }
    }
}

// MARK: - Column Manager Popover

struct LiveTailColumnManagerView: View {
    let viewModel: LiveTailViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Columns")
                    .font(.headline)
                Spacer()
                if !viewModel.hiddenColumns.isEmpty || viewModel.columnOrder != viewModel.columns {
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
                    HStack {
                        Button {
                            viewModel.toggleColumnVisibility(column)
                        } label: {
                            Image(systemName: viewModel.hiddenColumns.contains(column)
                                  ? "eye.slash" : "eye")
                                .foregroundStyle(viewModel.hiddenColumns.contains(column)
                                                 ? .secondary : .primary)
                                .frame(width: 20)
                        }
                        .buttonStyle(.plain)
                        .help(viewModel.hiddenColumns.contains(column) ? "Show column" : "Hide column")

                        Text(column)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .foregroundStyle(viewModel.hiddenColumns.contains(column)
                                             ? .secondary : .primary)

                        Spacer()

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

            if !viewModel.hiddenColumns.isEmpty {
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
