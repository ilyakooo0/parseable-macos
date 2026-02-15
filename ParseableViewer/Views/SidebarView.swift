import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @State private var showCreateStream = false
    @State private var newStreamName = ""
    @State private var showDeleteConfirm = false
    @State private var streamToDelete: String?
    @State private var deleteStreamDetail: String?

    /// Validates a stream name, returning an error message or nil if valid.
    static func validateStreamName(_ name: String) -> String? {
        if name.count > 255 {
            return "Stream name must be 255 characters or fewer."
        }
        // Allow alphanumeric, hyphens, underscores, and dots
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        if !name.unicodeScalars.allSatisfy({ allowed.contains($0) }) {
            return "Stream name can only contain letters, numbers, hyphens, underscores, and dots."
        }
        if name.hasPrefix(".") || name.hasPrefix("-") {
            return "Stream name cannot start with a dot or hyphen."
        }
        return nil
    }

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
                                        deleteStreamDetail = nil
                                        Task {
                                            if let client = appState.client,
                                               let stats = try? await client.getStreamStats(stream: stream.name) {
                                                var parts: [String] = []
                                                if let count = stats.ingestion?.lifetime_count {
                                                    parts.append("\(count) total records ingested")
                                                }
                                                if let size = stats.storage?.lifetime_size ?? stats.storage?.size {
                                                    parts.append("\(size) storage used")
                                                }
                                                if !parts.isEmpty {
                                                    deleteStreamDetail = parts.joined(separator: ", ")
                                                }
                                            }
                                            showDeleteConfirm = true
                                        }
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

                // Stream load error with retry
                if let streamError = appState.streamLoadError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text(streamError)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Spacer()
                        Button("Retry") {
                            Task { await appState.refreshStreams() }
                        }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.08))
                }

                // Bottom toolbar
                HStack {
                    Button {
                        showCreateStream = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Create new stream")
                    .accessibilityLabel("Create new stream")

                    Button {
                        Task { await appState.refreshStreams() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh streams")
                    .disabled(appState.isLoadingStreams)
                    .accessibilityLabel("Refresh streams")

                    Spacer()

                    if appState.isLoadingStreams {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Loading streams")
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
                if let error = Self.validateStreamName(name) {
                    appState.showErrorMessage(error)
                    return
                }
                Task {
                    do {
                        try await appState.createStream(name: name)
                        newStreamName = ""
                    } catch {
                        appState.showErrorMessage(ParseableError.userFriendlyMessage(for: error))
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
                            appState.showErrorMessage(ParseableError.userFriendlyMessage(for: error))
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let detail = deleteStreamDetail {
                Text("Are you sure you want to delete \"\(streamToDelete ?? "")\"? This stream has \(detail). All data will be removed and this cannot be undone.")
            } else {
                Text("Are you sure you want to delete \"\(streamToDelete ?? "")\"? This will remove all data and cannot be undone.")
            }
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
                        .accessibilityLabel(appState.isConnected ? "Connected" : "Disconnected")
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
                    .accessibilityLabel("Connection options")
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

    private var streamExists: Bool {
        appState.streams.contains { $0.name == query.stream }
    }

    var body: some View {
        Button {
            appState.selectedStream = query.stream
            appState.pendingSavedQuerySQL = query.sql
            appState.currentTab = .query
        } label: {
            HStack {
                Image(systemName: "bookmark")
                    .foregroundStyle(streamExists ? .orange : .secondary)
                VStack(alignment: .leading) {
                    Text(query.name)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(query.stream)
                        if !streamExists {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .help("Stream \"\(query.stream)\" no longer exists")
                        }
                    }
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
