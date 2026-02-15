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
        .task {
            await loadUsers()
        }
    }

    private func loadUsers() async {
        guard let client = appState.client else { return }
        isLoading = true
        errorMessage = nil

        do {
            users = try await client.listUsers()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
