# Parseable Viewer

A native macOS log viewer for [Parseable](https://www.parseable.com/), built with Swift and SwiftUI.

Browse log streams, run SQL queries, tail logs in real time, and inspect server configuration — all from a lightweight desktop app with zero external dependencies.

## Features

- **SQL Query Editor** — Write and execute SQL queries against any log stream with configurable time ranges (presets or custom), result filtering, column sorting, and query history
- **Live Tail** — Stream logs in near-real-time via HTTP polling with automatic deduplication, pause/resume, and a configurable entry buffer
- **Stream Management** — List, create, and delete log streams; view schema, ingestion stats, storage usage, retention policies, and partitioning config
- **Multiple Connections** — Save and switch between Parseable server connections with Keychain-backed password storage
- **Export** — Export query results as CSV or JSON via the system save dialog
- **Saved Queries** — Bookmark frequently-used SQL queries per stream for quick access from the sidebar
- **Alerts & Users** — View configured alert rules and user accounts on the connected server
- **Server Info** — Health status, version, deployment mode, storage backend, and update availability at a glance

## Install

```bash
brew install ilyakooo0/tap/parseable-viewer
```

## Requirements

- macOS 14.0+ (Sonoma)
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Build from source

```bash
# Install XcodeGen (one-time)
brew install xcodegen

# Generate the Xcode project and build
xcodegen generate
xcodebuild -project ParseableViewer.xcodeproj \
  -scheme ParseableViewer \
  -configuration Release \
  build
```

The built app is located at `build/Build/Products/Release/Parseable Viewer.app`.

To run tests:

```bash
xcodebuild test \
  -project ParseableViewer.xcodeproj \
  -scheme ParseableViewer \
  -configuration Debug \
  -destination 'platform=macOS'
```

## CI

GitHub Actions builds and tests on every push and PR via [`.github/workflows/build.yml`](.github/workflows/build.yml). The pipeline:

1. Builds for both `arm64` and `x86_64`
2. Runs tests on `arm64`
3. Creates a universal binary via `lipo`
4. On tagged releases (`v*`), creates a draft GitHub Release with all three zips

## Architecture

| Layer | Description |
|-------|-------------|
| **App** | `@main` entry point, `AppState` (central `@Observable` singleton injected via `.environment()`) |
| **Models** | `Codable` data types — `JSONValue` (recursive enum for arbitrary JSON), `LogStream`, `ServerAbout`, `AlertConfig`, etc. |
| **Services** | `ParseableClient` (stateless HTTP client, Basic Auth, `URLSession` async/await), `ConnectionStore` (UserDefaults + Keychain persistence) |
| **ViewModels** | `QueryViewModel` (SQL execution, filtering, export, history), `LiveTailViewModel` (timer-based polling, deduplication) |
| **Views** | SwiftUI views — `NavigationSplitView` sidebar + tabbed detail pane |

### Key design decisions

- **No external dependencies** — the app uses only Apple frameworks (`Foundation`, `SwiftUI`, `Network`, `Security`)
- **Defensive decoding** — models use `try?` for optional API fields to tolerate version differences across Parseable releases
- **Passwords in Keychain** — `ServerConnection` excludes `password` from its `Codable` conformance; the password is stored/loaded via `KeychainService` separately from the UserDefaults data
- **Live tail via HTTP polling** — Parseable's native live tail uses gRPC Arrow Flight streaming; this app approximates it with a sliding time window and content-based deduplication (FNV-1a fingerprinting)

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
| GET | `/alerts` | Alert rules |
| GET | `/logstream/{name}/retention` | Retention policy |
| GET | `/user` | List users |

## Project structure

```
ParseableViewer/
  App/
    ParseableViewerApp.swift    # @main, window/menu setup
    AppState.swift              # Central observable: connections, streams, navigation
  Models/
    JSONValue.swift             # Recursive JSON enum (null|bool|int|double|string|array|object)
    LogStream.swift             # Stream, schema, stats, info models
    ServerInfo.swift            # ServerAbout, RetentionConfig, UserInfo
    AlertModels.swift           # AlertConfig, AlertRule, AlertTarget
    ServerConnection.swift      # Connection model with Keychain integration
  Services/
    ParseableClient.swift       # HTTP client + ParseableError
    ConnectionStore.swift       # UserDefaults persistence, SavedQuery store
    KeychainService.swift       # Keychain read/write/delete
  ViewModels/
    QueryViewModel.swift        # Query execution, filtering, export, history
    LiveTailViewModel.swift     # Polling, deduplication, entry buffer
  Views/
    ContentView.swift           # Root layout: sidebar + detail
    SidebarView.swift           # Stream list, saved queries, connection switching
    QueryView.swift             # SQL editor, time picker, results table
    LiveTailView.swift          # Real-time log streaming UI
    StreamDetailView.swift      # Schema, stats, retention for selected stream
    LogTableView.swift          # Sortable log record table with detail pane
    LogDetailView.swift         # Formatted + raw JSON record inspector
    AlertsView.swift            # Alert rule listing
    UsersView.swift             # User listing
    ServerInfoView.swift        # Server health, version, storage info
    ConnectionSheet.swift       # Add/edit/test connection dialog
    TimeRangePicker.swift       # Preset + custom date range selector
    SettingsView.swift          # Preferences: query defaults, live tail config
  Resources/
    Assets.xcassets             # App icon, accent color
```

## Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd+Shift+N` | New connection |
| `Cmd+R` | Refresh streams |
| `Cmd+Enter` | Run query |
| `Cmd+P` | Pause/resume live tail |
| `Cmd+Delete` | Clear live tail entries |
| `Cmd+Ctrl+S` | Toggle sidebar |

## License

See [LICENSE](LICENSE) for details.
