import SwiftUI

struct ServerInfoView: View {
    @Environment(AppState.self) private var appState
    @State private var about: ServerAbout?
    @State private var isLoading = false
    @State private var isHealthy = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Server Information")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                    Button {
                        Task { await loadInfo() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                    .accessibilityLabel("Refresh server info")
                }

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }

                if let error = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                        Text(error)
                    }
                    .foregroundStyle(.red)
                    .font(.caption)
                }

                // Health status
                GroupBox("Health") {
                    HStack {
                        Circle()
                            .fill(isHealthy ? .green : .red)
                            .frame(width: 12, height: 12)
                            .accessibilityLabel(isHealthy ? "Healthy" : "Unhealthy")
                        Text(isHealthy ? "Healthy" : "Unhealthy")
                            .fontWeight(.medium)
                        Spacer()
                    }
                    .padding(8)
                }

                if let about {
                    GroupBox("Server Details") {
                        VStack(alignment: .leading, spacing: 8) {
                            InfoRow(label: "Version", value: about.version ?? "N/A")
                            InfoRow(label: "UI Version", value: about.uiVersion ?? "N/A")
                            InfoRow(label: "Commit", value: about.commit ?? "N/A")
                            InfoRow(label: "Deployment ID", value: about.deploymentId ?? "N/A")
                            InfoRow(label: "Mode", value: about.mode ?? "N/A")
                            InfoRow(label: "Staging", value: about.staging ?? "N/A")
                            InfoRow(label: "License", value: about.license ?? "N/A")
                            if let port = about.grpcPort {
                                InfoRow(label: "gRPC Port", value: String(port))
                            }
                            if let llm = about.llmActive {
                                InfoRow(label: "LLM Active", value: llm ? "Yes" : "No")
                            }
                            if let oidc = about.oidcActive {
                                InfoRow(label: "OIDC Active", value: oidc ? "Yes" : "No")
                            }
                            if let update = about.updateAvailable, update {
                                InfoRow(label: "Update Available", value: about.latestVersion ?? "Yes")
                            }
                        }
                        .padding(8)
                    }

                    if let store = about.store {
                        GroupBox("Storage") {
                            VStack(alignment: .leading, spacing: 8) {
                                InfoRow(label: "Type", value: store.type ?? "N/A")
                                InfoRow(label: "Path", value: store.path ?? "N/A")
                            }
                            .padding(8)
                        }
                    }
                }

                // Connection info
                if let connection = appState.activeConnection {
                    GroupBox("Connection") {
                        VStack(alignment: .leading, spacing: 8) {
                            InfoRow(label: "Name", value: connection.name)
                            InfoRow(label: "URL", value: connection.url)
                            InfoRow(label: "Username", value: connection.username)
                        }
                        .padding(8)
                    }
                }

                // Stream summary
                GroupBox("Streams") {
                    HStack {
                        Text("\(appState.streams.count) log streams")
                            .font(.headline)
                        Spacer()
                    }
                    .padding(8)
                }

                // App version
                GroupBox("Parseable Viewer") {
                    HStack {
                        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
                        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
                        InfoRow(label: "App Version", value: "\(appVersion) (\(buildNumber))")
                    }
                    .padding(8)
                }
            }
            .padding()
        }
        // Key on the active connection so switching (or reconnecting to a
        // different) server reloads instead of showing the previous server's info.
        .task(id: appState.activeConnection?.id) {
            await loadInfo()
        }
    }

    private func loadInfo() async {
        guard let client = appState.client else { return }
        let connID = appState.activeConnection?.id
        isLoading = true
        errorMessage = nil
        // Seed from the app-wide cache so first load isn't blank, but never fall
        // back to it on refresh failure (that would show stale data under the error).
        if about == nil { about = appState.serverAbout }

        async let healthCheck: Void = client.checkHealth()
        async let aboutResult = client.getAbout()

        let healthy: Bool
        do {
            try await healthCheck
            healthy = true
        } catch {
            healthy = false
        }
        let aboutValue: ServerAbout?
        let aboutError: String?
        do {
            aboutValue = try await aboutResult
            aboutError = nil
        } catch {
            aboutValue = nil
            aboutError = ParseableError.userFriendlyMessage(for: error)
        }

        // Drop results if the active connection changed while awaiting, so a slow
        // load for the previous server can't overwrite the current one's state.
        guard connID == appState.activeConnection?.id else { return }
        isHealthy = healthy
        about = aboutValue
        errorMessage = aboutError
        isLoading = false
    }
}
