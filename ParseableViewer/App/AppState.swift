import Foundation
import Network
import SwiftUI

@Observable
final class AppState {
    // MARK: - Connection State
    var connections: [ServerConnection] = []
    var activeConnection: ServerConnection?
    var client: ParseableClient?
    var isConnected = false
    var isConnecting = false
    var serverAbout: ServerAbout?
    private(set) var isNetworkAvailable = true
    private let networkMonitor = NWPathMonitor()
    private let networkMonitorQueue = DispatchQueue(label: "com.parseableviewer.network-monitor")
    private var connectTask: Task<Bool, Never>?

    // MARK: - Stream State
    var streams: [LogStream] = []
    var selectedStream: String?
    var isLoadingStreams = false
    var streamLoadError: String?

    // MARK: - Navigation
    var showConnectionSheet = false
    var editingConnection: ServerConnection?
    var currentTab: AppTab = .query
    var streamSearchText = ""

    // MARK: - Error
    var errorMessage: String?
    var showError = false

    // MARK: - Filters
    var filters: [ParseableFilter] = []
    var isLoadingFilters = false
    /// Set by sidebar when user clicks a filter; consumed by QueryView.
    var pendingFilterSQL: String?

    // MARK: - Query Refresh
    /// Incremented by the Cmd+R shortcut; QueryView observes changes to re-execute the current query.
    var queryRefreshToken = UUID()

    enum AppTab: String, CaseIterable, Identifiable {
        case query = "Query"
        case liveTail = "Live Tail"
        case streamInfo = "Stream Info"
        case alerts = "Alerts"
        case users = "Users"
        case serverInfo = "Server Info"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .query: return "magnifyingglass"
            case .liveTail: return "antenna.radiowaves.left.and.right"
            case .streamInfo: return "info.circle"
            case .alerts: return "bell"
            case .users: return "person.2"
            case .serverInfo: return "server.rack"
            }
        }

        /// Whether the tab's content is scoped to a selected stream. Server-level
        /// tabs (Users, Server Info) stay reachable even with no stream selected.
        var requiresStream: Bool {
            switch self {
            case .query, .liveTail, .streamInfo, .alerts: return true
            case .users, .serverInfo: return false
            }
        }
    }

    var filteredStreams: [LogStream] {
        if streamSearchText.isEmpty {
            return streams.sorted()
        }
        return streams.filter { $0.name.localizedCaseInsensitiveContains(streamSearchText) }.sorted()
    }

    deinit {
        networkMonitor.cancel()
    }

    init() {
        connections = ConnectionStore.loadConnections()

        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.isNetworkAvailable = path.status == .satisfied
            }
        }
        networkMonitor.start(queue: networkMonitorQueue)

        if let activeID = ConnectionStore.loadActiveConnectionID(),
           let connection = connections.first(where: { $0.id == activeID }) {
            connectTask = Task { @MainActor [weak self] in
                await self?.performConnect(to: connection) ?? false
            }
        }
    }

    // MARK: - Connection Management

    @MainActor
    @discardableResult
    func connect(to connection: ServerConnection) async -> Bool {
        // Supersede any connect already in flight (e.g. the launch auto-reconnect
        // or a prior request) instead of silently dropping this one — which would
        // surface as a spurious "Connection failed". Cancel it and wait for it to
        // unwind so two connects never run concurrently.
        if let existing = connectTask {
            existing.cancel()
            _ = await existing.value
        }
        let task = Task { @MainActor [weak self] in
            await self?.performConnect(to: connection) ?? false
        }
        connectTask = task
        return await task.value
    }

    @MainActor
    private func performConnect(to connection: ServerConnection) async -> Bool {
        guard !isConnecting else { return false }

        if !isNetworkAvailable {
            self.errorMessage = "No internet connection. Check your network and try again."
            self.showError = true
            return false
        }

        isConnecting = true
        defer { isConnecting = false }
        errorMessage = nil

        // When switching to a different server, clear stream-specific state
        // so stale selections don't reference streams that don't exist.
        if activeConnection?.id != connection.id {
            selectedStream = nil
            streamLoadError = nil
            // Drop the previous server's cached `about` so views seeding from it
            // (ServerInfoView) don't paint the old server's details while the new
            // one loads. It's repopulated below once the new server responds.
            serverAbout = nil
            // Reset the sidebar search filter and tab too: a stale filter would
            // silently hide the new server's streams, and a stream-specific tab
            // would have no valid selection behind it.
            streamSearchText = ""
            currentTab = .query
        }

        do {
            let newClient = try ParseableClient(connection: connection)

            // Test connection — throws on non-200 or network failure
            try await newClient.checkHealth()

            // If the task was cancelled while awaiting (e.g. user clicked
            // Disconnect during auto-reconnect), bail before installing the
            // client so we don't resurrect a connection disconnect() just cleared.
            if Task.isCancelled { return false }

            self.client = newClient
            self.activeConnection = connection
            self.isConnected = true

            ConnectionStore.saveActiveConnectionID(connection.id)

            // Load server info, streams, and filters (best-effort; don't fail the connection)
            async let about = newClient.getAbout()
            async let streamList = newClient.listStreams()
            async let filterList = newClient.listFilters()

            let aboutResult = try? await about
            let filterResult = (try? await filterList) ?? []
            let streamResult: Result<[LogStream], Error>
            do {
                streamResult = .success(try await streamList)
            } catch {
                streamResult = .failure(error)
            }

            // Re-check after the loads above: a disconnect could have landed
            // while awaiting, in which case committing these would show stale data.
            if Task.isCancelled { return false }

            self.serverAbout = aboutResult
            self.filters = filterResult
            switch streamResult {
            case .success(let list):
                self.streams = list
                self.streamLoadError = nil
            case .failure(let error):
                self.streams = []
                self.streamLoadError = ParseableError.userFriendlyMessage(for: error)
            }
            return true
        } catch {
            // If the task was cancelled (e.g. user clicked Disconnect during
            // auto-reconnect), skip the error alert — disconnect() already
            // cleaned up the state.
            if !Task.isCancelled {
                self.errorMessage = ParseableError.userFriendlyMessage(for: error)
                self.showError = true
                self.isConnected = false
                self.client = nil
                self.activeConnection = nil
                // Clear stream-specific state so the sidebar doesn't keep showing
                // the previous server's streams/selection after a failed connect.
                self.streams = []
                self.selectedStream = nil
                self.streamLoadError = nil
                self.serverAbout = nil
                self.filters = []
            }
            return false
        }
    }

    @MainActor
    func disconnect() {
        connectTask?.cancel()
        connectTask = nil
        client = nil
        activeConnection = nil
        isConnected = false
        streams = []
        selectedStream = nil
        serverAbout = nil
        filters = []
        // Clear transient stream/UI state too, otherwise a leftover stream-load
        // error keeps rendering in the sidebar after disconnect and a stale search
        // filter / tab carries into the next connection.
        streamLoadError = nil
        isLoadingStreams = false
        streamSearchText = ""
        currentTab = .query
        ConnectionStore.saveActiveConnectionID(nil)
    }

    @MainActor
    func refreshStreams() async {
        guard let client else { return }
        isLoadingStreams = true
        streamLoadError = nil
        do {
            streams = try await client.listStreams()
            // Drop a selection that no longer exists server-side (e.g. the stream
            // was deleted from another client); otherwise the detail tabs keep
            // querying a missing stream and surface 404s.
            if let selected = selectedStream, !streams.contains(where: { $0.name == selected }) {
                selectedStream = nil
            }
        } catch {
            let message = ParseableError.userFriendlyMessage(for: error)
            streamLoadError = message
            self.errorMessage = "Failed to load streams: \(message)"
            self.showError = true
        }
        isLoadingStreams = false
    }

    // MARK: - Connection CRUD

    @MainActor
    func addConnection(_ connection: ServerConnection) {
        connections.append(connection)
        ConnectionStore.saveConnections(connections)
    }

    @MainActor
    func updateConnection(_ connection: ServerConnection) {
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = connection
            ConnectionStore.saveConnections(connections)
        }
        // If the active connection was edited, its URL or credentials may now point
        // at a different server, so swapping the client alone isn't enough — the
        // displayed streams/selection/server-info would be stale and queries would
        // 404. Reconnect end to end (re-validate health, reload streams/filters/
        // about). Clear the stream selection first so a now-missing stream doesn't
        // keep driving detail-tab requests during the reconnect.
        if activeConnection?.id == connection.id {
            // `performConnect` skips its stale-state cleanup because the id is
            // unchanged, but the edited URL/credentials may point at a different
            // server. Clear the stream-specific UI state here so a leftover sidebar
            // search filter doesn't hide the new server's streams and a
            // stream-specific tab doesn't linger with no valid selection.
            selectedStream = nil
            streamSearchText = ""
            currentTab = .query
            Task { await connect(to: connection) }
        }
    }

    @MainActor
    func removeConnection(_ connection: ServerConnection) {
        connections.removeAll { $0.id == connection.id }
        ConnectionStore.deleteConnection(connection)
        ConnectionStore.saveConnections(connections)
        if activeConnection?.id == connection.id {
            disconnect()
        }
    }

    // MARK: - Stream Management

    @MainActor
    func createStream(name: String) async throws {
        guard let client else { throw ParseableError.notConnected }
        try await client.createStream(name: name)
        await refreshStreams()
    }

    @MainActor
    func deleteStream(name: String) async throws {
        guard let client else { throw ParseableError.notConnected }
        try await client.deleteStream(name: name)
        if selectedStream == name {
            selectedStream = nil
        }
        await refreshFilters()
        await refreshStreams()
    }

    // MARK: - Filters

    @MainActor
    func refreshFilters() async {
        guard let client else { return }
        isLoadingFilters = true
        filters = (try? await client.listFilters()) ?? []
        isLoadingFilters = false
    }

    @MainActor
    func saveFilter(name: String, sql: String, stream: String) async throws {
        guard let client else { throw ParseableError.notConnected }
        let filter = ParseableFilter(
            filterName: name,
            streamName: stream,
            query: FilterQuery(filterType: "sql", filterQuery: sql)
        )
        let saved = try await client.createFilter(filter)
        filters.append(saved)
    }

    @MainActor
    func deleteFilter(_ filter: ParseableFilter) async throws {
        guard let client else { throw ParseableError.notConnected }
        guard let filterId = filter.filterId else { return }
        try await client.deleteFilter(id: filterId)
        filters.removeAll { $0.id == filter.id }
    }

    // MARK: - Error Handling

    @MainActor
    func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }
}
