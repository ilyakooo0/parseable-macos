import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("defaultTimeRange") private var defaultTimeRange = "last1Hour"
    @AppStorage("maxQueryResults") private var maxQueryResults = 1000
    @AppStorage("liveTailPollInterval") private var liveTailPollInterval = 2.0
    @AppStorage("liveTailMaxEntries") private var liveTailMaxEntries = 5000
    var body: some View {
        TabView {
            // General settings
            Form {
                Section("Query Defaults") {
                    Picker("Default Time Range", selection: $defaultTimeRange) {
                        Text("Last 5 minutes").tag("last5Min")
                        Text("Last 15 minutes").tag("last15Min")
                        Text("Last 30 minutes").tag("last30Min")
                        Text("Last 1 hour").tag("last1Hour")
                        Text("Last 6 hours").tag("last6Hours")
                        Text("Last 24 hours").tag("last24Hours")
                        Text("Last 7 days").tag("last7Days")
                        Text("Last 30 days").tag("last30Days")
                    }

                    Stepper("Max Results: \(maxQueryResults)",
                            value: $maxQueryResults,
                            in: 100...10000,
                            step: 100)
                }

                Section("Live Tail") {
                    HStack {
                        Text("Poll Interval:")
                        Slider(value: $liveTailPollInterval, in: 1...10, step: 0.5)
                        Text("\(String(format: "%.1f", liveTailPollInterval))s")
                            .frame(width: 40)
                    }

                    Stepper("Max Entries: \(liveTailMaxEntries)",
                            value: $liveTailMaxEntries,
                            in: 1000...50000,
                            step: 1000)
                }

            }
            .formStyle(.grouped)
            .tabItem {
                Label("General", systemImage: "gear")
            }

            // Connections
            VStack {
                List {
                    ForEach(appState.connections) { connection in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(connection.name)
                                    .fontWeight(.medium)
                                Text(connection.url)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("User: \(connection.username)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }

                            Spacer()

                            if appState.activeConnection?.id == connection.id {
                                Text("Active")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(.green.opacity(0.1))
                                    .foregroundStyle(.green)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }

                            Button(role: .destructive) {
                                appState.removeConnection(connection)
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                HStack {
                    Spacer()
                    Button("Add Connection...") {
                        appState.editingConnection = nil
                        appState.showConnectionSheet = true
                    }
                }
                .padding()
            }
            .tabItem {
                Label("Connections", systemImage: "server.rack")
            }
        }
        .frame(width: 500, height: 400)
    }
}
