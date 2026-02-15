import SwiftUI

struct StreamDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var schema: StreamSchema?
    @State private var stats: StreamStats?
    @State private var info: StreamInfo?
    @State private var retention: [RetentionConfig] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let stream = appState.selectedStream {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Header
                        HStack {
                            VStack(alignment: .leading) {
                                Text(stream)
                                    .font(.title2)
                                    .fontWeight(.semibold)

                                if let info {
                                    if let created = info.createdAt {
                                        Text("Created: \(created)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            Spacer()

                            Button {
                                Task { await loadData(stream: stream) }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .disabled(isLoading)
                            .accessibilityLabel("Refresh stream details")
                        }

                        if isLoading {
                            ProgressView("Loading stream information...")
                                .frame(maxWidth: .infinity)
                        }

                        if let error = errorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.triangle")
                                Text(error)
                                Spacer()
                                Button("Retry") {
                                    Task { await loadData(stream: stream) }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .foregroundStyle(.red)
                            .font(.caption)
                        }

                        // Stats section
                        if let stats {
                            GroupBox("Statistics") {
                                LazyVGrid(columns: [
                                    GridItem(.flexible()),
                                    GridItem(.flexible()),
                                    GridItem(.flexible())
                                ], spacing: 12) {
                                    if let ingestion = stats.ingestion {
                                        StatCard(title: "Event Count", value: ingestion.count.map(String.init) ?? "N/A")
                                        StatCard(title: "Ingestion Size", value: ingestion.size ?? "N/A")
                                        StatCard(title: "Format", value: ingestion.format ?? "N/A")
                                        if let lc = ingestion.lifetime_count {
                                            StatCard(title: "Lifetime Count", value: String(lc))
                                        }
                                        if let ls = ingestion.lifetime_size {
                                            StatCard(title: "Lifetime Size", value: ls)
                                        }
                                    }
                                    if let storage = stats.storage {
                                        StatCard(title: "Storage Size", value: storage.size ?? "N/A")
                                        StatCard(title: "Storage Type", value: storage.type ?? "N/A")
                                        if let ls = storage.lifetime_size {
                                            StatCard(title: "Lifetime Storage", value: ls)
                                        }
                                    }
                                }
                                .padding(8)
                            }
                        }

                        // Info section
                        if let info {
                            GroupBox("Stream Configuration") {
                                VStack(alignment: .leading, spacing: 8) {
                                    InfoRow(label: "Created At", value: info.createdAt ?? "N/A")
                                    InfoRow(label: "First Event At", value: info.firstEventAt ?? "N/A")
                                    InfoRow(label: "Cache Enabled", value: info.cacheEnabled.map { $0 ? "Yes" : "No" } ?? "N/A")
                                    InfoRow(label: "Time Partition", value: info.timePartition ?? "N/A")
                                    InfoRow(label: "Static Schema", value: info.staticSchemaFlag.map { $0 ? "Yes" : "No" } ?? "N/A")
                                }
                                .padding(8)
                            }
                        }

                        // Retention section
                        if !retention.isEmpty {
                            GroupBox("Retention Policy") {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(Array(retention.enumerated()), id: \.offset) { _, config in
                                        VStack(alignment: .leading, spacing: 4) {
                                            if let desc = config.description {
                                                Text(desc)
                                            }
                                            if let duration = config.duration {
                                                InfoRow(label: "Duration", value: duration)
                                            }
                                            if let action = config.action {
                                                InfoRow(label: "Action", value: action)
                                            }
                                        }
                                    }
                                }
                                .padding(8)
                            }
                        }

                        // Schema section
                        if let schema {
                            GroupBox("Schema (\(schema.fields.count) fields)") {
                                VStack(spacing: 0) {
                                    // Header
                                    HStack {
                                        Text("Field Name")
                                            .fontWeight(.semibold)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text("Data Type")
                                            .fontWeight(.semibold)
                                            .frame(width: 200, alignment: .leading)
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.primary.opacity(0.05))

                                    ForEach(schema.fields) { field in
                                        HStack {
                                            Text(field.name)
                                                .font(.system(.caption, design: .monospaced))
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            Text(field.dataType)
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                                .frame(width: 200, alignment: .leading)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
                .task(id: stream) {
                    await loadData(stream: stream)
                }
            } else {
                VStack {
                    Text("Select a stream to view its details")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func loadData(stream: String) async {
        guard let client = appState.client else { return }
        isLoading = true
        errorMessage = nil
        // Clear previous stream's data so it isn't shown under the new header
        schema = nil
        stats = nil
        info = nil
        retention = []

        // Fetch all stream data concurrently
        async let schemaResult = Result { try await client.getStreamSchema(stream: stream) }
        async let statsResult = Result { try await client.getStreamStats(stream: stream) }
        async let infoResult = Result { try await client.getStreamInfo(stream: stream) }
        async let retentionResult = Result { try await client.getRetention(stream: stream) }

        let results = await (schemaResult, statsResult, infoResult, retentionResult)

        var failures: [String] = []
        var sawNotFound = false

        func checkNotFound(_ error: Error) {
            if case .serverError(let code, _) = error as? ParseableError, code == 404 { sawNotFound = true }
        }

        switch results.0 {
        case .success(let v): schema = v
        case .failure(let e): schema = nil; failures.append("schema"); checkNotFound(e)
        }

        switch results.1 {
        case .success(let v): stats = v
        case .failure(let e): stats = nil; failures.append("stats"); checkNotFound(e)
        }

        switch results.2 {
        case .success(let v): info = v
        case .failure(let e): info = nil; failures.append("info"); checkNotFound(e)
        }

        switch results.3 {
        case .success(let v): retention = v
        case .failure(let e): retention = []; failures.append("retention"); checkNotFound(e)
        }

        if sawNotFound && failures.count == 4 {
            errorMessage = "Stream \"\(stream)\" was not found. It may have been deleted."
        } else if !failures.isEmpty {
            errorMessage = "Failed to load: \(failures.joined(separator: ", "))"
        }

        isLoading = false
    }
}

struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .trailing)
            Text(value)
                .textSelection(.enabled)
            Spacer()
        }
        .font(.caption)
    }
}
