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
        let connID = appState.activeConnection?.id
        isLoading = true
        errorMessage = nil
        alertConfig = nil

        do {
            let config = try await client.getAlerts(stream: stream)
            // The manual Refresh/Retry buttons spawn detached Tasks not tied to
            // `.task(id: stream)` cancellation, so a slow refresh for the old stream
            // can resolve after a switch. Drop stale results. Check the connection
            // id too: two servers can expose a same-named stream, so a name-only
            // guard could write the previous server's alerts after a server switch.
            // Still clear isLoading on the stale path: this task set the spinner,
            // so leaving it true wedges the ProgressView and disables Refresh.
            guard stream == appState.selectedStream,
                  connID == appState.activeConnection?.id else { isLoading = false; return }
            alertConfig = config
        } catch {
            guard stream == appState.selectedStream,
                  connID == appState.activeConnection?.id else { isLoading = false; return }
            errorMessage = ParseableError.userFriendlyMessage(for: error)
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
                    .foregroundStyle(stateColor)
                Text(alert.displayName)
                    .fontWeight(.medium)
                Spacer()
                if let severity = alert.severity {
                    Text(severity)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(severityColor.opacity(0.15))
                        .foregroundStyle(severityColor)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                if let state = alert.state {
                    Text(state)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(stateColor.opacity(0.15))
                        .foregroundStyle(stateColor)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            if let message = alert.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                if let alertType = alert.alertType {
                    Label(alertType, systemImage: "gearshape")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                if let rule = alert.rule, let type = rule.type {
                    Label(type, systemImage: "gearshape")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                if let datasets = alert.datasets, !datasets.isEmpty {
                    Label(datasets.joined(separator: ", "), systemImage: "cylinder")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let tags = alert.tags, !tags.isEmpty {
                HStack {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.1))
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

    private var stateColor: Color {
        switch alert.state?.lowercased() {
        case "triggered": return .red
        case "disabled": return .gray
        // A reported-but-unrecognized state is a genuine "needs attention" signal,
        // so tint it orange; a missing state is simply unknown and stays neutral so
        // the bell icon isn't painted as a warning for every stateless alert.
        case .some: return .orange
        case nil: return .secondary
        }
    }

    private var severityColor: Color {
        switch alert.severity?.lowercased() {
        case "critical": return .red
        case "high": return .orange
        case "medium": return .yellow
        case "low": return .blue
        default: return .secondary
        }
    }
}
