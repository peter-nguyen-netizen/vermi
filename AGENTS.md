# AGENTS.md — Vermi (macOS Redis client)

Native macOS Redis client, product name **Vermi** (SPM target/module is still `RedisClient`). Swift 5.9+, SwiftUI, macOS 13+, zero external dependencies. Built with Swift Package Manager (no `.xcodeproj` — open `Package.swift` in Xcode or use `swift build`). App icon (vermilion "V") generated into `Resources/AppIcon.png`/`.icns`, applied at runtime via `NSApp.applicationIconImage` in AppDelegate.

## Required workflow (every request)

Follow this flow for ANY change request; do not skip steps:

1. **Brainstorm** — understand intent; note options/edge cases (esp. cluster, large values, concurrency).
2. **Plan** — decide the approach + files to touch; scope it.
3. **Verify** — confirm the plan against the actual code (read the files; check assumptions) before writing.
4. **Implement** — make the change, matching existing conventions.
5. **Review bug & technical debt** — re-read the diff for correctness, concurrency (actor reentrancy, `@MainActor`), leaks, dead code, edge cases.
6. **Fix** — resolve whatever the review found.
7. **Test** — `swift build` (0 warnings) + `swift test` (all pass); add/adjust tests for the change; verify behavior.
8. **Done** — summarize what changed; rebuild the `.dmg` if the user is running the packaged app.

⚠️ **Packaging gotcha (cost real trust once):** the `.dmg` is assembled from `.build/release/Vermi`. `swift build` (debug) does NOT update that binary. Always run `swift build -c release` BEFORE packaging, or the DMG ships a stale binary and none of your changes appear. The build-dmg script now runs the release build itself — keep it that way. After packaging, verify `dist/Vermi.app/Contents/MacOS/Vermi` has a fresh timestamp.

## Build & Test

```bash
swift build            # build (debug)
swift test             # run unit tests — testTarget wired in Package.swift
swift run Vermi        # run app from CLI (product is "Vermi", target is "RedisClient")
./scripts/build-dmg.sh # build RELEASE + package dist/Vermi.app + Vermi.dmg (run this to ship)
```

Target: macOS 13+. Do NOT use APIs newer than macOS 13 (e.g. `.cursor()` modifier, `CommandGroupPlacement.appMenu` — both already caused build failures and were removed).

## Architecture

```
RedisClient/
├── App/            RedisClientApp.swift (entry), AppDelegate.swift (window/activation)
├── Models/         RedisConnection.swift (Codable, persisted to UserDefaults key "RedisConnections")
├── Network/
│   ├── NetworkChannel.swift          actor; TCP/TLS via Network.framework
│   └── RESPProtocol/                 RESPValue, RESPParser, RESPEncoder (RESP3)
├── Services/       RedisClient.swift (actor; RedisClientProtocol impl, per-node channel pool, MOVED/ASK routing)
├── ViewModels/     AppState (@MainActor root store, per-tab VMs), KeyBrowser/CommandExecutor/PubSub/Monitoring VMs
├── Views/          MainWindowView (custom titlebar TopBar: TrafficLightButtons + connection tabs + FunctionTabStrip + DetailPane), per-feature views,
│                   Common/ (ConnectionCard, JSONEditor, Toast, Appearance, HandCursor, CopyButton, HighlightingTextEditor, ResizeHandle), PlaceholderViews (EmptyState + ConnectionDetailsView sheet)
└── Utilities/      Theme.swift (dynamic light/dark colors, button styles, components), RedisCommandCatalog.swift
```

### Key flows

- **Layout**: no-connection state = `EmptyStateView` → `ConnectionListSidebar` (in `PlaceholderViews.swift`) using shared `ConnectionCard`. Once a tab is open, `MainWindowView` shows custom titlebar `TopBar` (row 1: `TrafficLightButtons` + connection tab chips + "+" Menu + spacer + host/latency meta + `AppearanceToggle`; row 2: `FunctionTabStrip` Keys/Console/Pub-Sub/Monitor/Analysis) above `DetailPane`. Active function tab shows accent-tinted bg + soft shadow.
- **Connect**: double-click / hover-play / context-menu on `ConnectionCard` → `AppState.openConnectionTab(connection)` → `RedisClient(isCluster: type == .cluster)` → `client.connect()` establishes the primary node (TCP + AUTH + PING + SELECT for non-cluster) and runs `CLUSTER SLOTS` discovery for cluster → appends `ConnectionTab`, sets `activeTabId`.
- **Cluster / auto-reconnect**: `RedisClient` holds a per-node `NetworkChannel` pool + `slotMap`. `executeCluster` routes by CRC16 slot, follows MOVED/ASK (updates slotMap, sends ASKING before ASK retry). `channel(for:)` re-establishes a dropped node on the next command; single-node `execute` retries once. Helpers in `Network/RedisCluster.swift`.
- **Value panel** (`TypedValueViewer`): `canonicalText` is cached in `@State cachedJSON` and formatted asynchronously off main thread via `Task.detached` — never recomputed synchronously during render. `.task(id:)` triggers reformatting when key/mode changes; loading overlay shown during formatting. `isJSON` check during editing is debounced (500ms). String keys have opt-in **Edit** mode (TextEditor + Format + Save → SET via `saveStringValue`). Has find-in-value (highlights matches). `JSONHighlightedText` caches `AttributedString` via `@State`, precompiles regexes as `static let`, raises highlight limit to 50K chars. `JSONTreeView` is deleted (was dead code).
- **Console**: `CommandExecutorViewModel.tokenize` splits input honoring single/double quotes + backslash (so `HMGET k "field with space"` works — don't revert to naive `split(" ")`). Input is `CommandEditor` (NSViewRepresentable wrapping NSTextView, multi-line) — reports `contentHeight` for auto-sizing and `caret` position for arg-aware suggestions. Syntax highlighting: command name in accent color, quoted strings in jsonString color (via `AccentTheme.current`). Enter = run, Shift+Enter = newline, Tab = accept suggestion. Autocomplete: unified `Sugg` type (command/subcommand/key), 190+ commands from `RedisCommandCatalog` incl. subcommands, debounced key suggestions via SCAN. Single current result (not REPL log), Raw/JSON toggle with RESP→JSON conversion (`jsonPretty` handles HGETALL→object, nested JSON expansion). Per-connection command history + favorites.
- **Key search**: single field, auto-detects glob (`*?[]` → verbatim pattern) vs plain term (`*term*` substring). Recent patterns saved (`savedPatterns`, UserDefaults) as clickable chips. No manual Pattern/Exact toggle. Browse (`*`) uses SCAN with pagination + infinite scroll (auto-loads next page on scroll near bottom via sentinel `onAppear` in `LazyVStack`). Search (any non-`*` pattern) uses `KEYS` command for instant results (single round-trip, no pagination). Falls back to SCAN if KEYS fails. `isLoading` guard prevents concurrent loads from rapid scroll.
- **State**: `AppState` is `@MainActor ObservableObject`, injected via `.environmentObject`. Tabs = `ConnectionTab` structs holding their own `RedisClientProtocol`.
- **RESP**: commands encoded via `RESPEncoder`; `NetworkChannel.drainBuffer()` parses every complete frame on receive (keeps leftover bytes via `RESPParser.consumedOffset`), routes push frames to `pushHandler`, queues the rest in `pendingResponses`. Responses are delivered **event-driven** via `responseWaiter` (a `CheckedContinuation` resumed by `fulfillWaiterIfReady()` the instant enough frames arrive — no polling); `commandTimeout` 10s tears down the socket on timeout (buffers reset, next command auto-reconnects) — prevents "Expected CR/LF" desync from a late reply. `performSendAndWait` clears `receivedData`+`pendingResponses` before each send.
- **Pipelining**: `NetworkChannel.pipeline([[String]])` sends many commands in one write and reads N replies in order (`waiterGen` invalidates a superseded waiter's timeout). `RedisClient.pipeline` sends to the primary (redirects NOT followed — best-effort batch). `RedisClient.keyMeta(keys)` uses 2 pipelines (TYPE + MEMORY USAGE) so a 30-key page's metadata is ~2 round-trips, not 60. Key-list meta is prefetched via `keyMeta` before revealing a page.
- **Per-tab view models**: `ConnectionTab` owns `keyBrowserViewModel` / `commandExecutorViewModel` / `pubSubViewModel`, created + configured in `openConnectionTab`. Feature views read them via `AppState.active*ViewModel` computed props (NOT `@StateObject`) so Console input, search/results/selection, and subscriptions survive function-tab switches. `KeyBrowserViewModel.didInitialLoad` gates the one-time scan so returning to Keys never wipes an active search.
- **Multi-tab same connection**: same connection can open in multiple tabs — each gets independent `RedisClient` + TCP socket + ViewModels. Tab names disambiguated with "(N)" suffix when duplicated. "Open Saved" menu shows all connections (green dot for already-open). Search patterns and command history sync across tabs sharing a connection via `ConnectionHistoryStore` — a `@MainActor ObservableObject` singleton registry keyed by `connection.id`. VMs subscribe via Combine (`$searchPatterns`/`$commandHistory` sink) to forward changes to SwiftUI. Store released from registry when last tab for that connection closes.

## Conventions

- **ALL ObservableObjects are `@MainActor`** (AppState + 4 ViewModels). Never remove the annotation — mutating `@Published` off-main triggers SwiftUI's purple "Publishing changes from background threads" runtime warnings. Callbacks from actors/timers hop via `Task { @MainActor in ... }`. Never mutate `@Published`/`AppState` inside a SwiftUI Binding setter synchronously during a view update — defer with `Task { @MainActor in ... }` (see DetailPane's TabView binding).
- `NetworkChannel` is an actor — never mutate its state from nonisolated closures; hop through `Task { await self... }`.
- **Commands are serialized via `NetworkChannel.enqueue` (a Task chain) — do not bypass it.** Being an actor is NOT enough: `send` awaits mid-flight, so a concurrent caller reenters, sends a second command, and races the shared `pendingResponses` queue → responses matched to the wrong command (symptom: `type()`/`get()` receive another command's reply, throw, and the key detail shows "No value"). Exposed by the multi-iteration SCAN loop running alongside `loadKeyDetails`. Any new request path must go through `send`/`sendRaw` → `enqueue`.
- NWConnection state handlers are `@Sendable` and MUST resume the continuation exactly once — use `ResumeGuard` (NSLock latch in NetworkChannel.swift). `.ready` then `.cancelled` both fire; double-resume = fatal `SWIFT TASK CONTINUATION MISUSE` crash, already happened once.
- `String(format:)`: use `%@` for Swift String args, never `%s` (C-string specifier → NSCocoaErrorDomain 2048 crash at runtime). Bit us twice.
- Logging: `os.Logger` (subsystem `io.clearer.redis-client`) + `print()` duplicates for Xcode console visibility during debugging.
- UI text: English. Theme constants from `Theme.colors/spacing/sizes` — no hardcoded colors.
- **Toasts**: `ToastCenter.shared.success/error/info(_:)` (a `@MainActor` singleton) posts to a bottom-left `ToastOverlay` (overlaid at MainWindowView root). Auto-dismiss 20s, manual close, dedupes consecutive identical. Post from any `@MainActor` VM/service. Feature views forward their VM `errorMessage` via `.onChange`; `AppState.errorMessage` is forwarded + cleared in MainWindowView. `GridBackground` (in Toast.swift) is the dotted grid behind `EmptyStateView`.
- **Light/Dark**: every `Theme.colors.*` is a dynamic `Color(light:dark:)` (NSColor dynamic provider) that adapts to appearance automatically — never hardcode a single-appearance `Color(red:…)` for UI chrome; add both variants in Theme. Appearance is an `@AppStorage("appearanceMode")` (`AppearanceMode`: system/light/dark) applied via `.preferredColorScheme` at MainWindowView root; `AppearanceToggle` cycles it. `GradientBackground` + `GridBackground` (Common) sit behind screens.
- **Design system is claymorphism/soft-UI** (`Theme.swift`). Warm cream ground (`#F5F0EA` light / `#1C1814` dark), generous radii (10/14/20px), dual-direction soft shadows (`.softShadow()` / `.softShadowSmall()`), inset search fields. Accent-driven neutrals tint toward the selected `AccentTheme` (7 presets). Font: system `.rounded`. Conditional modifier `.if(condition) { transform }` available on all Views.
- **Buttons**: `PrimaryButtonStyle` / `SecondaryButtonStyle` / `GhostButtonStyle` / `DestructiveButtonStyle` — all include `.softShadowSmall()`. Inputs: `.inputField()` (inset shadow + focus accent ring). Reusable: `FormField`, `ToggleRow`, `InlineBanner` (in PlaceholderViews.swift), `TypeBadge`/`Badge`/`SectionDivider`/`StatusIndicator` (in Theme.swift), `HResizeHandle`/`VResizeHandle`, `MetadataBadge` (KeyBrowserView). Don't hand-roll buttons/inputs with raw colors — use these.
- **Custom titlebar**: native macOS titlebar hidden (`.windowStyle(.hiddenTitleBar)` + `standardWindowButton.isHidden`). Custom `TrafficLightButtons` (red/yellow/green dots with hover icons) + connection tabs on same row. `window.isMovableByWindowBackground = true` for drag. `.edgesIgnoringSafeArea(.top)` removes titlebar safe area gap.
- User communicates in Vietnamese; code, comments, and commits in English.
- Xcode note: purple runtime warnings persist in the Issue Navigator from the PREVIOUS run — always Clean Build Folder + re-run before trusting them.

## Current status (2026-07-31)

Target environment: staging AWS ElastiCache cluster endpoint (`*.clustercfg.usw2.cache.amazonaws.com`), no in-transit encryption → connect with TLS=false. Cluster nodes may advertise VPC-internal IPs (e.g. `10.x`); MOVED to an unreachable node surfaces a clear "Cannot reach node …" toast.

Working end-to-end: connect (standalone + cluster), key browse/search, typed value view + string edit, Console with multi-line editor + autocomplete + RESP→JSON, Pub/Sub, Monitoring, Analysis. Soft/claymorphism design, custom titlebar, 7 accent themes, per-connection history, multi-tab same connection with synced history, hand cursor on all interactive elements. Build clean, 0 warnings.

### Notable behaviors / gotchas

- **Every connection follows MOVED/ASK** (`RedisClient.executeRouted`), not just those opened as "Cluster" — a connection opened as Standalone against a cluster now works (slot map learned lazily). Standalone servers never send MOVED, so it's harmless.
- **Server error replies throw** `RESPError.serverError(message)` (via `execute`), so `MOVED`/`WRONGTYPE`/`NOAUTH` show their real text instead of masquerading as a value. `RESPError` is `LocalizedError` — don't regress to raw "error N" messages.
- **INFO parsing**: `RedisInfo.parse` must check the `# Section` header BEFORE skipping comment lines (a past bug skipped all `#` lines → empty metrics). Splits values on the first `:` only.
- **RESPParser incomplete frames**: `readLine`/`skipCRLF` throw `.incompleteData` (NOT `.invalidFormat`) when the buffer ends mid-frame — this is the real root cause of the old "Expected CR/LF" desync (a frame split across TCP packets). `drainBuffer` catches `.incompleteData` and waits for more bytes. Don't change these to format errors. Regression tests cover it.
- **RedisJSON**: keys of type `ReJSON-RL` are read via `JSON.GET key` and shown as a JSON string (loadKeyDetails switch). RedisJSON commands are in `RedisCommandCatalog` for Console autocomplete.
- **Key list**: flat or **tree** (namespace grouping by `:`, `KeyTree.build` + `KeyTreePane`, toggle in header). Infinite scroll in both modes (sentinel `onAppear` at end of `LazyVStack`). Keys reveal immediately; type/size badges fill in progressively via `loadMetaProgressively` (background, chunked, `metaToken` cancels on reset). Density toggle (`compactKeyList`), skeleton rows while first page loads, keyboard nav (↑↓).
- **Key editing**: string value (edit mode + Save → SET), add string key (`AddKeySheet`), rename (RENAME), set/remove TTL (EXPIRE/PERSIST), delete (DEL). Per-element hash/list/set/zset editing via `StructuredValueEditor` (Edit/JSON toggle) — HSET/HDEL, LSET/RPUSH/LREM, SADD/SREM, ZADD/ZREM; each mutation reloads the key.
- **Console history/favorites**: `CommandExecutorViewModel` persists `CommandHistory` + `CommandFavorites`; header star toggles favorite, history menu lists favorites + recent.
- **Bulk ops**: key-list select mode (`selectionMode`/`selectedKeys`) → `BulkActionBar` bulk-delete (per-key DEL, cluster-safe) / bulk-set-TTL, both confirmed. Selection state unit-tested; writes verified on local Redis only (prod is read-only, see memory).
- **Memory analysis** (`AnalysisViewModel`, Analysis tab / ⌘5): samples keyspace, sizes keys, aggregates top keys + by-type + by-namespace; per-tab VM; `aggregate` is `nonisolated` + unit-tested; live-verified read-only.
- **Large values**: string/JSON values are size-checked first (STRLEN / `JSON.DEBUG MEMORY`, best-effort). Above 512 KB the value is NOT auto-loaded — `deferredValueBytes` drives a `LargeValuePrompt` with an explicit "Load value". Even once loaded, the viewer skips prettify above 256 KB, truncates rendered text to 200 KB (Copy grabs full value), and syntax highlighting is capped at 50 KB. JSON formatting runs off main thread via `Task.detached`; `AttributedString` is cached and only rebuilt when content changes. This keeps clicking a multi-MB JSON key responsive.
- **Edit connection**: `ConnectionDetailsView(editing:)` prefills + updates in place (uses `@Environment(\.dismiss)`, not an isPresented binding). Presented via `.sheet(item: $appState.editingConnection)`; trigger from `ConnectionCard` context-menu "Edit…".
- **Monitoring**: `isLoading` set only on first fetch (periodic refresh must not toggle layout — caused jitter). Interval selector + Export-INFO in the header menu.

- **SSH tunnel** (`SSHTunnel.swift`): spawns system `/usr/bin/ssh -N -L 127.0.0.1:<free>:<host>:<port> user@bastion` (key/agent auth; password SSH not supported). `AppState.openConnectionTab` starts the tunnel then points `RedisClient` at the local port; stops it on close/failure. Connection form has an SSH section (`useSSH` + host/port/user/identity). Works for single-node / single-shard cluster; multi-shard MOVED to VPC-internal IPs won't route through one tunnel. E2E needs a real bastion (not in test env); arg-builder + free-port are unit-tested.
- **Passwords** are stored in the **Keychain** (`Keychain.swift`, generic password keyed by connection UUID). UserDefaults persists connections with `password` stripped; `loadConnections` rehydrates from Keychain; `removeSavedConnection` deletes the item. Keychain I/O isn't unit-tested (CLI/sandbox-dependent) — verify in the signed app.

### Still missing

- **Sentinel discovery** (enum/form option only; needs a master-name field + `SENTINEL get-master-addr-by-name` resolution; no sentinel env to verify).
- **Cluster replica reads** (per-node pipeline for metadata IS done via `RedisCluster.groupByNode` + `metaOnNode`; READONLY replica read-routing deferred — needs a live multi-node cluster to test safely).
- ~~Multi-line Console editor~~ — DONE: `CommandEditor` (NSTextView-based) with syntax highlighting, auto-height, caret-aware arg suggestions.
- ~~Multi-tab same connection~~ — DONE: open multiple tabs for same connection; shared `ConnectionHistoryStore` syncs search patterns + command history via Combine.
