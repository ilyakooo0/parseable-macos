import SwiftUI

struct LiveTailView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = LiveTailViewModel()
    @State private var selectedEntry: LiveTailViewModel.LiveTailEntry?
    @State private var autoScroll = true
    @State private var pulseOpacity: Double = 1.0

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

                    Toggle("Auto-scroll", isOn: $autoScroll)
                        .toggleStyle(.checkbox)

                    Button {
                        viewModel.clear()
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

                    if !viewModel.filterText.isEmpty && viewModel.displayedCount != viewModel.entryCount {
                        Text("(of \(viewModel.entryCount) total)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.bar)

                Divider()

                // Entries list
                ScrollViewReader { proxy in
                    List(viewModel.filteredEntries, selection: Binding(
                        get: { selectedEntry?.id },
                        set: { id in
                            selectedEntry = viewModel.filteredEntries.first { $0.id == id }
                        }
                    )) { entry in
                        LiveTailEntryRow(entry: entry)
                            .id(entry.id)
                            .tag(entry.id)
                    }
                    .listStyle(.plain)
                    .font(.system(.caption, design: .monospaced))
                    .onChange(of: viewModel.entries.count) { _, _ in
                        guard autoScroll else { return }
                        // When a filter is active, scroll to the last filtered entry;
                        // when no filter, scroll to the absolute last entry.
                        let target = viewModel.filterText.isEmpty
                            ? viewModel.entries.last
                            : viewModel.filteredEntries.last
                        if let target {
                            proxy.scrollTo(target.id, anchor: .bottom)
                        }
                    }
                }
            }

            // Detail pane
            if let entry = selectedEntry {
                LogDetailView(record: entry.record)
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
        }
    }
}

struct LiveTailEntryRow: View {
    let entry: LiveTailViewModel.LiveTailEntry

    var body: some View {
        HStack(spacing: 8) {
            Text(entry.displayTimestamp)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)

            if let level = entry.record["level"] ?? entry.record["severity"] {
                Text(level.displayString)
                    .fontWeight(.medium)
                    .foregroundStyle(levelColor(for: level.displayString))
                    .frame(width: 50, alignment: .leading)
            }

            Text(entry.summary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(entry.summary)
        }
    }
}
