# Remaining Improvements

Potential improvements for Parseable Viewer, cataloged after a thorough audit of every source file. Organized by category and severity.

---

## High Priority

### Keychain access control too permissive
**`KeychainService.swift:15-19`** — Passwords are stored with `kSecClassGenericPassword` using only `kSecAttrService` and `kSecAttrAccount`. No access control list (ACL) or `kSecAttrAccessible` value is set, so the default accessibility applies. Adding `kSecAttrAccessibleWhenUnlocked` (or `AfterFirstUnlock`) would restrict access to when the device is unlocked, following Keychain best practices.

### Auth header silently degrades on encoding failure
**`ParseableClient.swift:88-93`** — If `"\(username):\(password)".data(using: .utf8)` returns `nil`, `authHeader` returns the string `"Basic "` (no credentials). Every subsequent API call sends this empty auth header, receiving 401s with no indication that the root cause is a credential encoding issue. Should throw or log a clear error.

### No data migration for persisted stores
**`ConnectionStore.swift:7-11`, `SavedQueryStore.swift:46-50`** — Both stores decode from UserDefaults with `try? JSONDecoder().decode(...)`, falling back to `[]` on failure. If the schema ever changes (e.g., a new required field on `SavedQuery` or `ServerConnection`), all stored data silently disappears. Adding a version key and migration logic would prevent data loss across app updates.

### No auto-reconnect on network recovery
**`AppState.swift:77-82`** — The `NWPathMonitor` updates `isNetworkAvailable` but doesn't trigger reconnection when the network comes back. If the user was connected and the network drops then recovers, the app stays disconnected. The user must manually click Connect. A reconnect-on-recovery flow (with the last active connection) would be a significant UX improvement.

---

## Medium Priority

### No keyboard navigation in log table
**`LogTableView.swift:53-63`** — Row selection is mouse-only via `onTapGesture`. macOS users expect arrow-key navigation through table rows. Would require either switching to `List(selection:)` (which provides this for free) or adding a custom `.onKeyPress` handler.

### Loading skeleton / empty state ambiguity
**`ContentView.swift:16-24`** — After connecting, the detail pane shows "Select a stream" even while streams are still loading. There's no visual distinction between "loading streams" and "streams loaded, none selected." A loading indicator in the detail pane (checking `appState.isLoadingStreams`) would clarify the state.

### Log level colors only — no text fallback for colorblind users
**`LogTableView.swift:193-199`, `LiveTailEntryRow:189-194`, `LogDetailView.swift:136-183`** — Error/warn/info levels are distinguished solely by color (red/orange/blue). Colorblind users can't differentiate them. Adding a small icon or text badge alongside the color would improve accessibility.

### Server error messages may expose sensitive info
**`ParseableError.swift:31-32`** — `.serverError(code, message)` includes the raw server response body in the user-facing error. If the server returns a stack trace or internal paths, these get shown in the UI. Truncating the message or stripping known sensitive patterns would be safer.

### Reduce-motion support for LiveTail pulse animation
**`LiveTailView.swift:88-95`** — The pulsing green circle animates continuously with `repeatForever`. Users with vestibular sensitivity (who enable "Reduce motion" in System Settings) still see the animation. Checking `@Environment(\.accessibilityReduceMotion)` and showing a static indicator when enabled would respect the system preference.

### Stream deletion doesn't debounce stats fetch
**`SidebarView.swift:62-78`** — The "Delete..." context menu item fires an async `getStreamStats` call before showing the confirmation dialog. Rapid right-click → Delete on multiple streams triggers parallel stats fetches with no debouncing. Minor, but could be noisy on slow connections.

### SettingsView has hard-coded frame size
**`SettingsView.swift:102`** — `frame(width: 500, height: 400)` doesn't adapt to user text size preferences or longer translations. Using `minWidth`/`minHeight` with flexible layout would handle more scenarios.

### Poll error backoff is all-or-nothing
**`LiveTailViewModel.swift:153-162`** — The auto-stop fires after exactly 5 consecutive errors regardless of error type. A transient 503 (server restarting) is treated the same as a permanent 404 (stream deleted). Exponential backoff for retryable errors with immediate stop for permanent errors would be more nuanced.

### URLSession has no retry logic for transient failures
**`ParseableClient.swift:116-134`** — `performRequest` makes a single attempt. Transient errors (timeout, connection reset) fail immediately. Adding a single automatic retry with a short delay for idempotent GET requests would improve reliability without changing semantics.

### No results context in empty table state
**`LogTableView.swift:39-47`** — "No results" shows whether no query has been run or the query returned zero rows. Could distinguish with "Run a query to see results" vs "Query returned 0 rows."

---

## Low Priority

### `TimeRangePicker` "Done" button validation gap
**`TimeRangePicker.swift:79-83`** — The "Done" button is disabled when `customEnd < customStart`, but the user can still close the popover by clicking outside it, leaving the invalid date range active. The query will fail at the API level with a confusing error.

### Copy-to-clipboard not debounced
**`LogDetailView.swift:54-69`** — Rapid clicks on the copy button trigger multiple clipboard operations and the checkmark animation restarts. A simple `guard !showCopyConfirmation` would prevent redundant copies.

### No character counter on stream name input
**`SidebarView.swift:155-176`** — The stream name validation enforces a 255-character limit, but the user only discovers this after clicking "Create." A live character counter in the text field would prevent surprise validation failures.

### Query history is per-app, not per-connection
**`QueryViewModel.swift:300-311`** — Query history is stored in a single UserDefaults key. If the user has two servers with different schemas, history from Server A shows in the dropdown while connected to Server B. Keying history by connection ID would scope it correctly.

### `prettyPrinted` String padding is rebuilt per line
**`JSONValue.swift:90-91`** — `String(repeating: "  ", count: indent)` allocates a new string for every line of deeply nested JSON. For very large records this is wasteful, though in practice the cost is negligible for typical log entries.

### `exportAsJSON` swallows encoding errors
**`QueryViewModel.swift:232-241`** — If `JSONEncoder().encode(results)` fails, it silently returns `"[]"` instead of surfacing the error. The caller has no way to know the export was empty due to failure vs. genuinely empty results.

### Tab state not persisted across app launches
**`AppState.swift:28`** — `currentTab` defaults to `.query` on every launch. Saving the last active tab to UserDefaults would restore the user's context.

### LiveTail filter doesn't search nested values
**`LiveTailViewModel.swift:52-58`** — `filteredEntries` checks `entry.summary` and `record.values` using `displayString`, which shows `"[3 items]"` for arrays. Searching for content inside nested objects won't match. Using `exportString` for filter matching would search actual content, but at a performance cost.

### `FormattedRecordView.sortedKeys` recomputed on every render
**`LogDetailView.swift:75-87`** — The `sortedKeys` computed property does `firstIndex` + `remove(at:)` for each priority key on every view update. For typical records (~20 fields) this is negligible, but memoizing with the record as the key would be cleaner.

### Saved query creation has no duplicate detection
**`QueryView.swift:232-244`** — The user can save the same SQL query with the same name multiple times. No check for duplicate names or SQL text before appending to the list.

### No export progress for large result sets
**`QueryView.swift:273-297`** — Export runs in a `Task.detached` with no progress feedback. For 10k+ rows with nested JSON, the CSV/JSON generation could take seconds. The UI appears frozen with no indication that the export is in progress.

---

## Already Fixed (for reference)

The following issues were identified and fixed during this audit:

| Commit | Fix |
|--------|-----|
| `06299ee` | Clipboard false-success, export silent failure, orphaned connect task |
| `f4a6e8d` | Orphaned queries on tab switch, input validation, queue retention |
| `3740f3e` | Malformed API responses returning empty data instead of throwing |
| `1554c22` | Inconsistent error messages across views |
| `05a9fb4` | CSV escaping for carriage returns, clipboard warnings |
| `3eda714` | Stale keychain password, silent stream load failure |
| `56ab0c0` | False truncation warning for custom SQL, cancel-on-disconnect alert |
| `8b7eed0` | Silent request cancellation on deinit, CSV export data loss, queryLimit bounds |
| `840c7e4` | LiveTail fingerprint collisions, auto-stop on persistent errors |
| `8fda678` | Stale stream selection on server switch, cached date formatter |
| `4574ca2` | Numeric column sorting, stale query on stream switch |
| `b89a537` | Stale cross-stream data in detail/alerts views |
