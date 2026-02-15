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
                        Text(isHealthy ? "Healthy" : "Unhealthy")
                            .fontWeight(.medium)
                        Spacer()
                    }
                    .padding(8)
                }

                if let about = about ?? appState.serverAbout {
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
            }
            .padding()
        }
        .task {
            await loadInfo()
        }
    }

    private func loadInfo() async {
        guard let client = appState.client else { return }
        isLoading = true
        errorMessage = nil

        do {
            async let healthResult = client.checkHealth()
            async let aboutResult = client.getAbout()

            isHealthy = (try? await healthResult) ?? false
            about = try? await aboutResult
        }

        isLoading = false
    }
}
