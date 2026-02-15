import SwiftUI

struct AlertsView: View {
    @Environment(AppState.self) private var appState
    @State private var alertConfig: AlertConfig?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let stream = appState.selectedStream {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text("Alerts for \(stream)")
                            .font(.headline)
                        Spacer()
                        Button {
                            Task { await loadAlerts(stream: stream) }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(isLoading)
                        .accessibilityLabel("Refresh alerts")
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
                                Task { await loadAlerts(stream: stream) }
                            }
                            .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let alerts = alertConfig?.alerts, !alerts.isEmpty {
                        List {
                            ForEach(alerts) { alert in
                                AlertRowView(alert: alert)
                            }
                        }
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "bell.slash")
                                .font(.system(size: 32))
                                .foregroundStyle(.secondary)
                            Text("No alerts configured")
                                .foregroundStyle(.secondary)
                            Text("Configure alerts via the Parseable API or web UI")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .task(id: stream) {
                    await loadAlerts(stream: stream)
                }
            } else {
                Text("Select a stream to view alerts")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func loadAlerts(stream: String) async {
        guard let client = appState.client else { return }
        isLoading = true
        errorMessage = nil

        do {
            alertConfig = try await client.getAlerts(stream: stream)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

struct AlertRowView: View {
    let alert: AlertRule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "bell.fill")
                    .foregroundStyle(.orange)
                Text(alert.name)
                    .fontWeight(.medium)
            }

            if let message = alert.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let rule = alert.rule {
                HStack {
                    if let type = rule.type {
                        Label(type, systemImage: "gearshape")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }

            if let targets = alert.targets, !targets.isEmpty {
                HStack {
                    Text("Targets:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ForEach(Array(targets.enumerated()), id: \.offset) { _, target in
                        if let type = target.type {
                            Text(type)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
