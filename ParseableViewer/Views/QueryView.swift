import SwiftUI

struct QueryView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = QueryViewModel()
    @State private var showSaveQuerySheet = false
    @State private var saveQueryName = ""
    @State private var exportError: String?
    @State private var showExportError = false

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
                        .help("Query history")
                    }

                    Button {
                        showSaveQuerySheet = true
                    } label: {
                        Image(systemName: "bookmark")
                    }
                    .help("Save query")
                    .disabled(viewModel.sqlQuery.isEmpty)

                    Menu {
                        Button("Export as JSON") { exportJSON() }
                        Button("Export as CSV") { exportCSV() }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(viewModel.results.isEmpty)

                    Button {
                        Task {
                            await viewModel.executeQuery(
                                client: appState.client,
                                stream: appState.selectedStream
                            )
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if viewModel.isLoading {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "play.fill")
                            }
                            Text("Run")
                        }
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(viewModel.isLoading)
                    .buttonStyle(.borderedProminent)
                }
                .padding(8)

                // SQL editor
                TextEditor(text: $vm.sqlQuery)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 60, maxHeight: 120)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.2))
                    )
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)

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

                        if !viewModel.filterText.isEmpty {
                            Text("\(viewModel.filteredResults.count) of \(viewModel.results.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(6)
                }

                // Results table
                LogTableView(
                    records: viewModel.filteredResults,
                    columns: viewModel.columns,
                    selectedRecord: $vm.selectedLogEntry
                )
            }
        }
        .onChange(of: appState.selectedStream) { _, newValue in
            if let stream = newValue {
                viewModel.setDefaultQuery(stream: stream)
            }
        }
        .onAppear {
            if let stream = appState.selectedStream {
                viewModel.setDefaultQuery(stream: stream)
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
        let json = viewModel.exportAsJSON()
        saveToFile(content: json, type: "json")
    }

    private func exportCSV() {
        let csv = viewModel.exportAsCSV()
        saveToFile(content: csv, type: "csv")
    }

    private func saveToFile(content: String, type: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = type == "json" ? [.json] : [.commaSeparatedText]
        panel.nameFieldStringValue = "export.\(type)"
        panel.begin { result in
            if result == .OK, let url = panel.url {
                do {
                    try content.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    exportError = "Export failed: \(error.localizedDescription)"
                    showExportError = true
                }
            }
        }
    }
}
