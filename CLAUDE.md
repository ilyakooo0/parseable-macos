# Parseable Viewer - macOS App

Native macOS log viewer for [Parseable](https://www.parseable.com/) built with Swift and SwiftUI.

## Build

Requires macOS with Xcode 15+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project ParseableViewer.xcodeproj -scheme ParseableViewer -configuration Release build
```

CI builds run on `macos-14` runners via `.github/workflows/build.yml`.

## Architecture

- **Language**: Swift 5.9, SwiftUI, macOS 14.0+ (Sonoma)
- **Pattern**: MVVM with `@Observable` classes and `@Environment` injection
- **Networking**: `URLSession` async/await, no external dependencies
- **Project generation**: XcodeGen from `project.yml`
- **Persistence**: `UserDefaults` for connections and saved queries

### Source layout

```
ParseableViewer/
  App/           # @main entry point + AppState (central @Observable)
  Models/        # Codable data types (JSONValue, LogStream, ServerInfo, etc.)
  Services/      # ParseableClient (REST API), ConnectionStore (persistence)
  ViewModels/    # QueryViewModel, LiveTailViewModel
  Views/         # All SwiftUI views
  Resources/     # Asset catalog
```

### Key types

- `AppState` — singleton @Observable injected via `.environment()`. Holds connections, streams, selected stream, navigation state.
- `ParseableClient` — stateless HTTP client for all Parseable REST API calls. Uses Basic Auth. Created per-connection.
- `JSONValue` — recursive enum for type-safe arbitrary JSON (`null | bool | int | double | string | array | object`). Used as the core data type for log records (`LogRecord = [String: JSONValue]`).
- `QueryViewModel` — manages SQL text, time range, query execution, result columns, filtering, and CSV/JSON export.
- `LiveTailViewModel` — timer-based polling (2s interval) that queries recent logs, deduplicates by hash, and appends to a capped buffer.

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
- Models use defensive `try?` decoding for optional fields to tolerate API version differences
- Views follow the macOS pattern: `NavigationSplitView` sidebar + detail, with tab switching in the detail pane
- All API calls are `async` and dispatched from views via `Task { }`
- Entitlements: App Sandbox enabled with network.client for outbound connections
