import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @State private var showCreateStream = false
    @State private var newStreamName = ""
    @State private var showDeleteConfirm = false
    @State private var streamToDelete: String?

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {
            // Connection status
            ConnectionStatusView()

            Divider()

            if appState.isConnected {
                // Stream list
                List(selection: $appState.selectedStream) {
                    Section("Log Streams (\(appState.filteredStreams.count))") {
                        ForEach(appState.filteredStreams) { stream in
                            StreamRowView(stream: stream)
                                .tag(stream.name)
                                .contextMenu {
                                    Button("View Info") {
                                        appState.selectedStream = stream.name
                                        appState.currentTab = .streamInfo
                                    }
                                    Button("Query") {
                                        appState.selectedStream = stream.name
                                        appState.currentTab = .query
                                    }
                                    Button("Live Tail") {
                                        appState.selectedStream = stream.name
                                        appState.currentTab = .liveTail
                                    }
                                    Divider()
                                    Button("Delete...", role: .destructive) {
                                        streamToDelete = stream.name
                                        showDeleteConfirm = true
                                    }
                                }
                        }
                    }

                    if !appState.savedQueries.isEmpty {
                        Section("Saved Queries") {
                            ForEach(appState.savedQueries) { query in
                                SavedQueryRow(query: query)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .searchable(text: $appState.streamSearchText, prompt: "Filter streams")

                // Bottom toolbar
                HStack {
                    Button {
                        showCreateStream = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Create new stream")

                    Button {
                        Task { await appState.refreshStreams() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh streams")
                    .disabled(appState.isLoadingStreams)

                    Spacer()

                    if appState.isLoadingStreams {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .padding(8)
                .background(.bar)
            } else {
                VStack {
                    Spacer()
                    Text("Not connected")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .frame(minWidth: 220)
        .alert("Create Log Stream", isPresented: $showCreateStream) {
            TextField("Stream name", text: $newStreamName)
            Button("Create") {
                let name = newStreamName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                Task {
                    do {
                        try await appState.createStream(name: name)
                        newStreamName = ""
                    } catch {
                        appState.showErrorMessage(error.localizedDescription)
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                newStreamName = ""
            }
        }
        .alert("Delete Stream", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let name = streamToDelete {
                    Task {
                        do {
                            try await appState.deleteStream(name: name)
                        } catch {
                            appState.showErrorMessage(error.localizedDescription)
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(streamToDelete ?? "")\"? This will remove all data and cannot be undone.")
        }
    }
}

struct ConnectionStatusView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let connection = appState.activeConnection {
                HStack {
                    Circle()
                        .fill(appState.isConnected ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(connection.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Menu {
                        ForEach(appState.connections) { conn in
                            Button(conn.name) {
                                Task { await appState.connect(to: conn) }
                            }
                        }
                        Divider()
                        Button("Add Connection...") {
                            appState.editingConnection = nil
                            appState.showConnectionSheet = true
                        }
                        Button("Edit Connection...") {
                            appState.editingConnection = connection
                            appState.showConnectionSheet = true
                        }
                        Divider()
                        Button("Disconnect") {
                            appState.disconnect()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 24)
                }
                Text(connection.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if appState.isConnecting {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Connecting...")
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Connect to Server...") {
                    appState.editingConnection = nil
                    appState.showConnectionSheet = true
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(10)
    }
}

struct StreamRowView: View {
    let stream: LogStream

    var body: some View {
        HStack {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
            Text(stream.name)
                .lineLimit(1)
        }
    }
}

struct SavedQueryRow: View {
    @Environment(AppState.self) private var appState
    let query: SavedQuery

    var body: some View {
        Button {
            appState.selectedStream = query.stream
            appState.currentTab = .query
        } label: {
            HStack {
                Image(systemName: "bookmark")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading) {
                    Text(query.name)
                        .lineLimit(1)
                    Text(query.stream)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete", role: .destructive) {
                appState.removeSavedQuery(query)
            }
        }
    }
}
