import SwiftUI

struct UsersView: View {
    @Environment(AppState.self) private var appState
    @State private var users: [UserInfo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Users")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await loadUsers() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
                .accessibilityLabel("Refresh users")
            }
            .padding()

            Divider()

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text(error)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task { await loadUsers() }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if users.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.2")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No users found")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(users) { user in
                        HStack {
                            Image(systemName: "person.circle")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading) {
                                Text(user.id)
                                    .fontWeight(.medium)
                                if let method = user.method {
                                    Text("Auth: \(method)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        // Key on the active connection so switching (or reconnecting to a
        // different) server reloads instead of showing the previous server's users.
        .task(id: appState.activeConnection?.id) {
            await loadUsers()
        }
    }

    private func loadUsers() async {
        guard let client = appState.client else { return }
        let connID = appState.activeConnection?.id
        isLoading = true
        errorMessage = nil

        let loaded: [UserInfo]?
        let loadError: String?
        do {
            loaded = try await client.listUsers()
            loadError = nil
        } catch {
            loaded = nil
            loadError = ParseableError.userFriendlyMessage(for: error)
        }

        // Drop results if the active connection changed while awaiting. Still clear
        // isLoading: this task set the spinner, so leaving it true on the stale path
        // wedges the ProgressView and disables Refresh.
        guard connID == appState.activeConnection?.id else { isLoading = false; return }
        if let loaded { users = loaded }
        errorMessage = loadError
        isLoading = false
    }
}
