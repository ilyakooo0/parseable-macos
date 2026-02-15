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
    @State private var isSaving = false
    @State private var testResult: TestResult?
    @State private var urlValidationError: String?

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
                    .accessibilityLabel("Connection name")

                TextField("Server URL:", text: $url)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Server URL")
                    .onChange(of: url) { _, newValue in
                        urlValidationError = Self.validateURL(newValue)
                    }

                if let urlError = urlValidationError, !url.isEmpty {
                    Text(urlError)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                TextField("Username:", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Username")

                SecureField("Password:", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Password")
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
                        password = ""
                        dismiss()
                    }
                    .accessibilityLabel("Delete connection")
                }

                Spacer()

                Button("Test Connection") {
                    testConnection()
                }
                .disabled(url.isEmpty || username.isEmpty || isTesting || urlValidationError != nil)
                .accessibilityLabel("Test connection")

                Button("Cancel") {
                    password = ""
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(isEditing ? "Save" : "Connect") {
                    saveAndConnect()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || url.isEmpty || username.isEmpty || isSaving || urlValidationError != nil)
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
                try await client.checkHealth()
                await MainActor.run {
                    testResult = .success("Connection successful")
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = .failure(ParseableError.userFriendlyMessage(for: error))
                    isTesting = false
                }
            }
        }
    }

    private func saveAndConnect() {
        guard !isSaving else { return }

        let conn: ServerConnection
        if let existing = connection {
            conn = ServerConnection(id: existing.id, name: name, url: url, username: username, password: password)
            appState.updateConnection(conn)
        } else {
            conn = ServerConnection(name: name, url: url, username: username, password: password)
            appState.addConnection(conn)
        }

        isSaving = true
        testResult = nil

        Task {
            await appState.connect(to: conn)
            await MainActor.run {
                isSaving = false
                if appState.errorMessage != nil {
                    testResult = .failure(appState.errorMessage ?? "Connection failed")
                } else {
                    password = ""
                    dismiss()
                }
            }
        }
    }

    private static func validateURL(_ urlString: String) -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var normalized = trimmed
        if !normalized.hasPrefix("http://") && !normalized.hasPrefix("https://") {
            normalized = "https://\(normalized)"
        }

        guard let url = URL(string: normalized),
              url.host != nil else {
            return "Invalid URL format"
        }
        guard let scheme = url.scheme, ["http", "https"].contains(scheme.lowercased()) else {
            return "URL must use HTTP or HTTPS"
        }
        return nil
    }
}
