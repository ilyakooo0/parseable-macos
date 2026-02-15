import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            SidebarView()
        } detail: {
            if appState.isConnected {
                if appState.selectedStream != nil {
                    MainContentView()
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Select a stream")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("Choose a log stream from the sidebar to get started.")
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                WelcomeView()
            }
        }
        .sheet(isPresented: $appState.showConnectionSheet) {
            ConnectionSheet(connection: appState.editingConnection)
        }
        .alert("Error", isPresented: $appState.showError) {
            Button("OK") { appState.showError = false }
        } message: {
            Text(appState.errorMessage ?? "An unknown error occurred")
        }
    }
}

struct MainContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(AppState.AppTab.allCases) { tab in
                    TabButton(
                        title: tab.rawValue,
                        icon: tab.systemImage,
                        isSelected: appState.currentTab == tab
                    ) {
                        appState.currentTab = tab
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .background(.bar)

            Divider()

            // Content
            Group {
                switch appState.currentTab {
                case .query:
                    QueryView()
                case .liveTail:
                    LiveTailView()
                case .streamInfo:
                    StreamDetailView()
                case .alerts:
                    AlertsView()
                case .users:
                    UsersView()
                case .serverInfo:
                    ServerInfoView()
                }
            }
        }
    }
}

struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

struct WelcomeView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "server.rack")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            Text("Parseable Viewer")
                .font(.largeTitle)
                .fontWeight(.semibold)

            Text("Connect to a Parseable server to view and query your logs.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Add Connection") {
                appState.editingConnection = nil
                appState.showConnectionSheet = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if !appState.connections.isEmpty {
                Divider()
                    .frame(width: 200)

                Text("Recent Connections")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                ForEach(appState.connections.prefix(5)) { connection in
                    Button {
                        Task {
                            await appState.connect(to: connection)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "server.rack")
                            VStack(alignment: .leading) {
                                Text(connection.name)
                                    .fontWeight(.medium)
                                Text(connection.url)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 250, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 12)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
