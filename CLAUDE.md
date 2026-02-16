# Parseable Viewer - macOS App

Native macOS log viewer for [Parseable](https://www.parseable.com/) built with Swift and SwiftUI.

## Build

Requires macOS with Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project ParseableViewer.xcodeproj -scheme ParseableViewer -configuration Release build
```

Run tests:

```bash
xcodebuild test \
  -project ParseableViewer.xcodeproj \
  -scheme ParseableViewer \
  -configuration Debug \
  -destination 'platform=macOS'
```

CI builds on `macos-15` runners via `.github/workflows/build.yml`, producing arm64, x86_64, and universal binaries.

## Architecture

- **Language**: Swift 5.9, SwiftUI, macOS 14.0+ (Sonoma)
- **Pattern**: MVVM with `@Observable` classes and `@Environment` injection
- **Concurrency**: Swift structured concurrency (`async/await`, `@MainActor`, strict `Sendable` conformance)
- **Networking**: `URLSession` async/await, no external dependencies
- **Project generation**: XcodeGen from `project.yml`
- **Persistence**: Keychain (data-protection) for connections and passwords; `UserDefaults` for saved queries

### Source layout

```
ParseableViewer/
  App/           # @main entry point + AppState (central @Observable)
  Models/        # Codable data types (JSONValue, LogStream, ServerInfo, etc.)
  Services/      # ParseableClient (REST API), ConnectionStore (persistence), KeychainService
  ViewModels/    # QueryViewModel, LiveTailViewModel
  Views/         # All SwiftUI views
  Resources/     # Asset catalog
ParseableViewerTests/  # Unit tests for models, view models, and services
```

### Key types

- `AppState` — singleton `@Observable` injected via `.environment()`. Holds connections, streams, selected stream, navigation state. Clears stream-specific state when switching servers.
- `ParseableClient` — `Sendable` HTTP client for all Parseable REST API calls. Uses Basic Auth. Created per-connection. Uses `finishTasksAndInvalidate()` on deinit so in-flight requests complete gracefully.
- `JSONValue` — recursive `Codable`, `Hashable`, `Comparable` enum for type-safe arbitrary JSON (`null | bool | int | double | string | array | object`). Provides `displayString` (UI), `exportString` (CSV/JSON export with full nested serialization), and type-aware comparison (numeric values sort numerically, strings use `localizedStandardCompare`).
- `QueryViewModel` — manages SQL text, time range, query execution, result columns, filtering, CSV/JSON export, and query history. Auto-updates the default query when the user switches streams.
- `LiveTailViewModel` — timer-based polling that queries recent logs, deduplicates by FNV-1a content fingerprint, and appends to a capped buffer. Auto-stops after 5 consecutive poll failures.

### Parseable API endpoints used

All under `/api/v1/`. Auth: `Authorization: Basic <base64(user:pass)>`.

| Method | Path | Purpose |
|--------|------|---------|
| HEAD | `/liveness` | Health check |
| GET | `/about` | Server version, mode, storage info |
| GET | `/logstream` | List all streams |
| PUT/DELETE | `/logstream/{name}` | Create/delete stream |
| GET | `/logstream/{name}/schema` | Field names and types |
| GET | `/logstream/{name}/stats` | Ingestion/storage statistics |
| GET | `/logstream/{name}/info` | Creation time, partitioning config |
| POST | `/query` | SQL query with time range |
| GET | `/alerts` | Alert rules (also tries legacy `/logstream/{name}/alert`) |
| GET | `/logstream/{name}/retention` | Retention policy |
| GET | `/user` | List users |

The query endpoint accepts `{"query": "SQL", "startTime": "ISO8601", "endTime": "ISO8601"}` and returns either `[LogRecord]` or `{"records": [LogRecord], "fields": [...]}`.

Live tail in Parseable uses gRPC Arrow Flight streaming. This app approximates it via HTTP polling with a sliding time window.

## Conventions

- No external dependencies; the app uses only Apple frameworks
- All model types conform to `Sendable` for strict concurrency safety
- Models use defensive `try?` decoding for optional fields to tolerate API version differences
- Views follow the macOS pattern: `NavigationSplitView` sidebar + detail, with tab switching in the detail pane
- All API calls are `async` and dispatched from views via `Task { }`
- Connection metadata and passwords are stored in the Keychain (data-protection keychain, scoped by bundle ID to survive ad-hoc re-signing); `ServerConnection.password` is excluded from `Codable`
- Stream names are SQL-escaped via `escapeSQLIdentifier` (double-quote wrapping) and URL-encoded via `encodePathComponent` for API paths
- Views clear stale data before loading new content (e.g., switching streams clears previous schema/stats)
- Entitlements: App Sandbox enabled with network.client for outbound connections

## Common patterns

### Adding a new API endpoint

1. Add the method to `ParseableClient` using `performRequest(method:path:body:)` — it handles auth, status codes, and error mapping
2. Add any new response types to the appropriate model file with defensive `try?` decoding for optional fields
3. Call from the view layer via `Task { }` with appropriate loading/error state management

### Adding a new detail tab

1. Add a case to `AppState.AppTab` with a `systemImage`
2. Add the view to `StreamDetailView`'s tab switching logic
3. The sidebar tab bar auto-renders from `AppTab.allCases`

### Error handling

- Use `ParseableError.userFriendlyMessage(for:)` to convert any error (including `NSURLError` codes) into a human-readable string
- API methods throw `ParseableError` variants; views catch and display via `errorMessage` state
- Cancelled tasks (e.g., disconnect during auto-reconnect) are detected via `Task.isCancelled` to suppress spurious error alerts
