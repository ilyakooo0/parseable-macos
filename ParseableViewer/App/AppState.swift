import Foundation
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

    // MARK: - Stream State
    var streams: [LogStream] = []
    var selectedStream: String?
    var isLoadingStreams = false

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

    init() {
        connections = ConnectionStore.loadConnections()
        savedQueries = SavedQueryStore.load()

        if let activeID = ConnectionStore.loadActiveConnectionID(),
           let connection = connections.first(where: { $0.id == activeID }) {
            Task { @MainActor in
                await connect(to: connection)
            }
        }
    }

    // MARK: - Connection Management

    @MainActor
    func connect(to connection: ServerConnection) async {
        isConnecting = true
        errorMessage = nil

        do {
            let newClient = try ParseableClient(connection: connection)

            // Test connection
            _ = try await newClient.checkHealth()

            self.client = newClient
            self.activeConnection = connection
            self.isConnected = true

            ConnectionStore.saveActiveConnectionID(connection.id)

            // Load server info and streams
            async let about = newClient.getAbout()
            async let streamList = newClient.listStreams()

            self.serverAbout = try? await about
            self.streams = (try? await streamList) ?? []
        } catch {
            self.errorMessage = error.localizedDescription
            self.showError = true
            self.isConnected = false
            self.client = nil
            self.activeConnection = nil
        }

        isConnecting = false
    }

    @MainActor
    func disconnect() {
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
        do {
            streams = try await client.listStreams()
        } catch {
            self.errorMessage = "Failed to load streams: \(error.localizedDescription)"
            self.showError = true
        }
        isLoadingStreams = false
    }

    // MARK: - Connection CRUD

    func addConnection(_ connection: ServerConnection) {
        connections.append(connection)
        ConnectionStore.saveConnections(connections)
    }

    func updateConnection(_ connection: ServerConnection) {
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = connection
            ConnectionStore.saveConnections(connections)
        }
    }

    func removeConnection(_ connection: ServerConnection) {
        connections.removeAll { $0.id == connection.id }
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
        await refreshStreams()
    }

    // MARK: - Saved Queries

    func addSavedQuery(_ query: SavedQuery) {
        savedQueries.append(query)
        SavedQueryStore.save(savedQueries)
    }

    func removeSavedQuery(_ query: SavedQuery) {
        savedQueries.removeAll { $0.id == query.id }
        SavedQueryStore.save(savedQueries)
    }

    // MARK: - Error Handling

    func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }
}
