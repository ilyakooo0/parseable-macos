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
    private var connectTask: Task<Void, Never>?

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

    // MARK: - Saved Queries
    var savedQueries: [SavedQuery] = []
    /// Set by sidebar when user clicks a saved query; consumed by QueryView.
    var pendingSavedQuerySQL: String?

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
    }

    var filteredStreams: [LogStream] {
        if streamSearchText.isEmpty {
            return streams
        }
        return streams.filter { $0.name.localizedCaseInsensitiveContains(streamSearchText) }
    }

    deinit {
        networkMonitor.cancel()
    }

    init() {
        connections = ConnectionStore.loadConnections()
        savedQueries = SavedQueryStore.load()

        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.isNetworkAvailable = path.status == .satisfied
            }
        }
        networkMonitor.start(queue: networkMonitorQueue)

        if let activeID = ConnectionStore.loadActiveConnectionID(),
           let connection = connections.first(where: { $0.id == activeID }) {
            connectTask = Task { @MainActor in
                await connect(to: connection)
            }
        }
    }

    // MARK: - Connection Management

    @MainActor
    func connect(to connection: ServerConnection) async {
        guard !isConnecting else { return }

        if !isNetworkAvailable {
            self.errorMessage = "No internet connection. Check your network and try again."
            self.showError = true
            return
        }

        isConnecting = true
        errorMessage = nil

        do {
            let newClient = try ParseableClient(connection: connection)

            // Test connection — throws on non-200 or network failure
            try await newClient.checkHealth()

            self.client = newClient
            self.activeConnection = connection
            self.isConnected = true

            ConnectionStore.saveActiveConnectionID(connection.id)

            // Load server info and streams (best-effort; don't fail the connection)
            async let about = newClient.getAbout()
            async let streamList = newClient.listStreams()

            self.serverAbout = try? await about
            do {
                self.streams = try await streamList
                self.streamLoadError = nil
            } catch {
                self.streams = []
                self.streamLoadError = ParseableError.userFriendlyMessage(for: error)
            }
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
            }
        }

        isConnecting = false
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
        ConnectionStore.saveActiveConnectionID(nil)
    }

    @MainActor
    func refreshStreams() async {
        guard let client else { return }
        isLoadingStreams = true
        streamLoadError = nil
        do {
            streams = try await client.listStreams()
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
        // Remove saved queries that referenced the deleted stream
        let orphaned = savedQueries.filter { $0.stream == name }
        if !orphaned.isEmpty {
            savedQueries.removeAll { $0.stream == name }
            SavedQueryStore.save(savedQueries)
        }
        await refreshStreams()
    }

    // MARK: - Saved Queries

    @MainActor
    func addSavedQuery(_ query: SavedQuery) {
        savedQueries.append(query)
        SavedQueryStore.save(savedQueries)
    }

    @MainActor
    func removeSavedQuery(_ query: SavedQuery) {
        savedQueries.removeAll { $0.id == query.id }
        SavedQueryStore.save(savedQueries)
    }

    // MARK: - Error Handling

    @MainActor
    func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }
}
