import SwiftUI

struct ConnectionSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let connection: ServerConnection?

    @State private var name = ""
    @State private var url = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isTesting = false
    @State private var testResult: TestResult?

    enum TestResult {
        case success(String)
        case failure(String)
    }

    var isEditing: Bool { connection != nil }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEditing ? "Edit Connection" : "New Connection")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            // Form
            Form {
                TextField("Name:", text: $name)
                    .textFieldStyle(.roundedBorder)

                TextField("Server URL:", text: $url)
                    .textFieldStyle(.roundedBorder)

                TextField("Username:", text: $username)
                    .textFieldStyle(.roundedBorder)

                SecureField("Password:", text: $password)
                    .textFieldStyle(.roundedBorder)
            }
            .formStyle(.grouped)
            .padding()

            // Test result
            if let testResult {
                HStack {
                    switch testResult {
                    case .success(let msg):
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(msg)
                            .foregroundStyle(.green)
                    case .failure(let msg):
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(msg)
                            .foregroundStyle(.red)
                    }
                    Spacer()
                }
                .font(.caption)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            Divider()

            // Actions
            HStack {
                if isEditing {
                    Button("Delete", role: .destructive) {
                        if let connection {
                            appState.removeConnection(connection)
                        }
                        dismiss()
                    }
                }

                Spacer()

                Button("Test Connection") {
                    testConnection()
                }
                .disabled(url.isEmpty || username.isEmpty || isTesting)

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(isEditing ? "Save" : "Connect") {
                    saveAndConnect()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || url.isEmpty || username.isEmpty)
            }
            .padding()
        }
        .frame(width: 450)
        .onAppear {
            if let connection {
                name = connection.name
                url = connection.url
                username = connection.username
                password = connection.password
            }
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil

        Task {
            do {
                let conn = ServerConnection(name: name, url: url, username: username, password: password)
                let client = try ParseableClient(connection: conn)
                let healthy = try await client.checkHealth()
                await MainActor.run {
                    if healthy {
                        testResult = .success("Connection successful")
                    } else {
                        testResult = .failure("Server is not healthy")
                    }
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = .failure(error.localizedDescription)
                    isTesting = false
                }
            }
        }
    }

    private func saveAndConnect() {
        let conn: ServerConnection
        if let existing = connection {
            conn = ServerConnection(id: existing.id, name: name, url: url, username: username, password: password)
            appState.updateConnection(conn)
        } else {
            conn = ServerConnection(name: name, url: url, username: username, password: password)
            appState.addConnection(conn)
        }

        Task {
            await appState.connect(to: conn)
        }

        dismiss()
    }
}
