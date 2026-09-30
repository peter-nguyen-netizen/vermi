import Foundation
import Combine

struct HashField: Identifiable, Sendable, Equatable {
    var id: String { field }
    let field: String
    let value: String
}

struct ZSetMember: Identifiable, Sendable, Equatable {
    var id: String { member }
    let member: String
    let score: Double
}

enum TypedKeyValue: Sendable, Equatable {
    case none
    case string(String)
    case list([String])
    case hash([HashField])
    case set([String])
    case zset([ZSetMember])
}

@MainActor
final class KeyBrowserViewModel: NSObject, ObservableObject {
    @Published var keys: [String] = []
    @Published var selectedKey: String?
    @Published var typedValue: TypedKeyValue = .none
    @Published var selectedKeyType: String = ""
    @Published var selectedKeyTTL: Int = -1
    /// Memory footprint of the selected key (MEMORY USAGE, bytes). Same source
    /// as the key-list size badge so the two always agree.
    @Published var selectedKeySize: Int = 0
    /// Element count (list/set/hash/zset) or byte length (string) of the value.
    @Published var selectedKeyCount: Int = 0
    @Published var searchText: String = ""
    /// Loading the key LIST (scan / load-more). Independent of the value panel.
    @Published var isLoading: Bool = false
    /// Loading the selected key's VALUE/detail. Drives only the value panel.
    @Published var isLoadingValue: Bool = false
    @Published var errorMessage: String?
    @Published var cursor: Int = 0
    @Published var hasMore: Bool = false
    /// Multi-select (bulk) mode for the key list.
    @Published var selectionMode = false
    @Published var selectedKeys: Set<String> = []
    /// Approx total keys in the DB/node (DBSIZE), for scan-progress context.
    @Published var totalKeys: Int = 0

    /// Non-nil when the selected key's value is large and was NOT auto-loaded;
    /// holds its byte size so the UI can offer an explicit "Load value".
    @Published var deferredValueBytes: Int?

    /// Per-key byte size (MEMORY USAGE) + type (TYPE), fetched lazily per row.
    @Published var keySizes: [String: Int] = [:]
    @Published var keyTypes: [String: String] = [:]

    /// Value byte-size threshold above which we don't auto-load on selection.
    private let autoLoadByteLimit = 512 * 1024   // 512 KB

    /// Cap for list/zset reads so huge keys don't freeze the UI
    private let elementLimit = 200

    private var redisClient: RedisClientProtocol?
    /// Server-side hint per SCAN call. Higher = fewer round-trips when MATCH is selective.
    private let scanCount: Int = 500
    /// How many keys to collect per page (default browse + each "Load more")
    /// Keys fetched per page. Configurable in Settings ("Keys per page").
    private var pageSize: Int {
        let v = UserDefaults.standard.integer(forKey: "keyPageSize")
        return v > 0 ? v : 100
    }
    /// Safety cap on SCAN round-trips per page so a huge keyspace can't hang the UI
    private let maxIterationsPerPage: Int = 50

    /// Last pattern used, so "Load more" continues the same query
    private var currentPattern: String = "*"
    /// Surplus keys from a SCAN that returned more than one page; served to the
    /// next page before scanning again.
    private var scanBuffer: [String] = []
    /// True once the SCAN cursor returned 0 (whole keyspace iterated).
    private var scanExhausted = false
    /// Bumped on every scan() entry. An older in-flight scan whose generation no
    /// longer matches bails out — so a search started during the initial
    /// auto-fetch can't interleave and corrupt the key list.
    private var scanGeneration = 0
    /// Bumped only when the key list is reset (new search / reload). Background
    /// metadata loaders check it so they stop after a reset but keep running
    /// across "Load more" (which appends, not resets).
    private var metaToken = 0

    /// True once the first key listing has run. Prevents re-scanning (and wiping
    /// an active search) every time the user returns to the Keys tab.
    private(set) var didInitialLoad = false

    /// Incremented to request the search field take focus (⌘F).
    @Published var focusSearchToken = 0

    /// Shared per-connection history (search patterns + command history).
    private(set) var historyStore: ConnectionHistoryStore?

    var savedPatterns: [String] { historyStore?.searchPatterns ?? [] }

    func setClient(_ client: RedisClientProtocol) {
        self.redisClient = client
    }

    func setConnectionID(_ id: String) {
        let store = ConnectionHistoryStore.shared(for: id)
        self.historyStore = store
        storeCancellable = store.$searchPatterns
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }

    private var storeCancellable: AnyCancellable?

    func savePattern(_ pattern: String) {
        historyStore?.savePattern(pattern)
    }

    func removeSavedPattern(_ pattern: String) {
        historyStore?.removePattern(pattern)
    }

    /// Collects up to `pageSize` keys, looping SCAN internally because a single
    /// SCAN call may return zero keys with a non-zero cursor (it scans COUNT
    /// buckets then applies MATCH). Without the loop, browsing/pattern search
    /// looks empty even when keys exist.
    func scan(pattern: String = "*", reset: Bool = false) async {
        guard let client = redisClient else {
            errorMessage = "No connection"
            isLoading = false
            return
        }
        guard !isLoading || reset else { return }

        let effectivePattern = pattern.isEmpty ? "*" : pattern

        scanGeneration += 1
        let gen = scanGeneration

        if reset {
            currentPattern = effectivePattern
            cursor = 0
            keys = []
            keySizes = [:]
            keyTypes = [:]
            scanBuffer = []
            scanExhausted = false
            metaToken += 1
            if let size = try? await client.dbsize() { totalKeys = size }
            guard gen == scanGeneration else { return }

            if effectivePattern != "*" {
                do {
                    isLoading = true
                    errorMessage = nil
                    let allKeys = try await client.keys(pattern: effectivePattern)
                    guard gen == scanGeneration else { return }
                    keys = allKeys.sorted()
                    scanExhausted = true
                    scanBuffer = []
                    hasMore = false
                    didInitialLoad = true
                    if !keys.isEmpty {
                        let token = metaToken
                        Task { [weak self] in await self?.loadMetaProgressively(allKeys, token: token) }
                    }
                    isLoading = false
                    return
                } catch {
                    // KEYS failed — fall through to SCAN
                }
            }
        }

        do {
            isLoading = true
            errorMessage = nil

            // Collect EXACTLY up to pageSize. A single SCAN can return far more
            // than pageSize (COUNT is a hint), so surplus is buffered and reused
            // by the next "Load more" instead of overshooting the page.
            var page: [String] = []
            var iterations = 0

            while page.count < pageSize {
                if scanBuffer.isEmpty {
                    if scanExhausted { break }
                    guard iterations < maxIterationsPerPage else { break }
                    let (nextCursor, scanKeys) = try await client.scan(
                        cursor: cursor,
                        pattern: currentPattern,
                        count: scanCount
                    )
                    // A newer scan superseded us — abort without touching state.
                    guard gen == scanGeneration else { return }
                    cursor = nextCursor
                    if nextCursor == 0 { scanExhausted = true }
                    iterations += 1
                    scanBuffer.append(contentsOf: scanKeys)
                    continue
                }
                let take = min(pageSize - page.count, scanBuffer.count)
                page.append(contentsOf: scanBuffer.prefix(take))
                scanBuffer.removeFirst(take)
            }

            // Reveal keys immediately; type/size fill in progressively in the
            // background (badges live in fixed-width slots → no layout jump).
            keys.append(contentsOf: page)
            hasMore = !scanExhausted || !scanBuffer.isEmpty
            didInitialLoad = true

            // Leave errorMessage nil on an empty result — the view shows a
            // dedicated "No keys found" empty state, distinct from real errors.
            if !keys.isEmpty {
                let token = metaToken
                Task { [weak self] in await self?.loadMetaProgressively(page, token: token) }
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Background: fetch type + size for `page` in small chunks, updating the
    /// UI progressively. Stops if the list was reset (metaToken changed).
    private func loadMetaProgressively(_ page: [String], token: Int) async {
        guard let client = redisClient else { return }
        let chunkSize = 10
        var i = 0
        while i < page.count {
            guard token == metaToken else { return }
            let chunk = Array(page[i..<min(i + chunkSize, page.count)])
            let meta = await client.keyMeta(chunk)
            guard token == metaToken else { return }
            for (k, m) in meta {
                keyTypes[k] = m.type
                keySizes[k] = m.size
            }
            i += chunkSize
        }
    }

    func loadKeyDetails(_ key: String) async {
        guard let client = redisClient else {
            errorMessage = "No connection"
            return
        }

        selectedKey = key
        isLoadingValue = true
        errorMessage = nil
        typedValue = .none
        selectedKeyType = ""
        selectedKeySize = 0
        selectedKeyCount = 0
        selectedKeyTTL = -1
        deferredValueBytes = nil

        // Fetch metadata (type + ttl) first and independently, so the badges
        // always populate even if reading the value later fails.
        let type: String
        do {
            type = try await client.type(key)
            selectedKeyType = type
            selectedKeyTTL = Int(try await client.ttl(key))
            // Memory footprint via the SAME path as the list badge (keyMeta →
            // MEMORY USAGE), so detail and list always show the same size.
            selectedKeySize = await client.keyMeta([key])[key]?.size ?? keySizes[key] ?? 0
            keySizes[key] = selectedKeySize   // keep the list row in sync too
        } catch {
            errorMessage = error.localizedDescription
            ToastCenter.shared.error("Load failed: \(error.localizedDescription)")
            isLoadingValue = false
            return
        }

        do {
            switch type {
            case "string", "ReJSON-RL":
                // These can be huge (esp. RedisJSON). Check byte size first and
                // defer loading if it's over the auto-load limit, so a click
                // doesn't freeze fetching/rendering tens of MB.
                let bytes = try await valueByteSize(key: key, type: type)
                selectedKeyCount = bytes
                if bytes > autoLoadByteLimit {
                    deferredValueBytes = bytes
                } else {
                    try await fetchScalarValue(key: key, type: type)
                }

            case "list":
                let items = try await client.lrange(key, start: 0, stop: elementLimit - 1)
                typedValue = .list(items)
                selectedKeyCount = try await client.llen(key)

            case "hash":
                let fields = try await client.hgetall(key)
                typedValue = .hash(fields.map { HashField(field: $0.field, value: $0.value) })
                selectedKeyCount = fields.count

            case "set":
                let members = try await client.smembers(key)
                typedValue = .set(members)
                selectedKeyCount = members.count

            case "zset":
                let members = try await client.zrangeWithScores(key, start: 0, stop: elementLimit - 1)
                typedValue = .zset(members.map { ZSetMember(member: $0.member, score: $0.score) })
                selectedKeyCount = try await client.zcard(key)

            default:
                typedValue = .string("(unsupported type: \(type))")
                selectedKeyCount = 0
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingValue = false
    }


    /// Best-effort byte size of a string/JSON value without transferring it.
    private func valueByteSize(key: String, type: String) async throws -> Int {
        guard let client = redisClient else { return 0 }
        if type == "ReJSON-RL" {
            // JSON.DEBUG MEMORY returns the document's memory usage in bytes.
            // Best-effort: if the module lacks it, fall back to loading (0).
            let r = try? await client.execute(["JSON.DEBUG", "MEMORY", key])
            return Int(r?.intValue ?? 0)
        }
        return (try? await client.strlen(key)) ?? 0
    }

    /// Fetch a string / RedisJSON value into typedValue.
    private func fetchScalarValue(key: String, type: String) async throws {
        guard let client = redisClient else { return }
        if type == "ReJSON-RL" {
            let value = try await client.execute(["JSON.GET", key])
            typedValue = .string(value.stringValue ?? "(nil)")
            return
        }
        let value = try await client.get(key)
        if case .bulkString(let data) = value, let d = data {
            if let str = String(data: d, encoding: .utf8) {
                typedValue = .string(str)
            } else {
                typedValue = .string("[\(d.count) bytes of binary data]")
            }
        } else {
            typedValue = .string(value.stringValue ?? "(nil)")
        }
    }

    /// Load a value that was deferred because it exceeded the auto-load limit.
    func loadDeferredValue() async {
        guard let key = selectedKey else { return }
        let type = selectedKeyType
        deferredValueBytes = nil
        isLoadingValue = true
        errorMessage = nil
        do {
            try await fetchScalarValue(key: key, type: type)
        } catch {
            errorMessage = error.localizedDescription
            ToastCenter.shared.error("Load failed: \(error.localizedDescription)")
        }
        isLoadingValue = false
    }

    // MARK: - Bulk selection

    func toggleSelectionMode() {
        selectionMode.toggle()
        if !selectionMode { selectedKeys = [] }
    }

    func toggleSelected(_ key: String) {
        if selectedKeys.contains(key) { selectedKeys.remove(key) } else { selectedKeys.insert(key) }
    }

    func selectAllVisible() { selectedKeys = Set(keys) }
    func clearSelection() { selectedKeys = [] }

    /// Delete all selected keys (per-key DEL so it works across cluster slots).
    func bulkDelete() async {
        guard let client = redisClient else { return }
        let targets = Array(selectedKeys)
        var deleted = 0
        for key in targets {
            if (try? await client.del([key])) != nil {
                deleted += 1
                keys.removeAll { $0 == key }
                keySizes[key] = nil; keyTypes[key] = nil
                if selectedKey == key { selectedKey = nil; typedValue = .none }
            }
        }
        selectedKeys = []
        selectionMode = false
        ToastCenter.shared.success("Deleted \(deleted) key\(deleted == 1 ? "" : "s")")
    }

    /// Set TTL on all selected keys.
    func bulkSetTTL(seconds: Int) async {
        guard let client = redisClient, seconds > 0 else { return }
        var done = 0
        for key in selectedKeys {
            if (try? await client.expire(key, seconds: seconds)) == true { done += 1 }
        }
        selectedKeys = []
        selectionMode = false
        ToastCenter.shared.success("Set TTL on \(done) key\(done == 1 ? "" : "s")")
    }

    func deleteKey(_ key: String) async {
        guard let client = redisClient else {
            errorMessage = "No connection"
            return
        }

        // Snapshot a string value so the delete can be undone (only the common
        // string case — restoring collections/streams is out of scope).
        var undoValue: String?
        var undoTTL: Int?
        if selectedKey == key, case .string(let v) = typedValue {
            undoValue = v
            undoTTL = selectedKeyTTL > 0 ? selectedKeyTTL : nil
        }

        do {
            isLoadingValue = true
            _ = try await client.del([key])
            keys.removeAll { $0 == key }
            if selectedKey == key {
                selectedKey = nil
                typedValue = .none
            }
            if let v = undoValue {
                ToastCenter.shared.show("Deleted \(key)", kind: .success, actionLabel: "Undo") { [weak self] in
                    Task { await self?.restoreStringKey(key, value: v, ttl: undoTTL) }
                }
            } else {
                ToastCenter.shared.success("Deleted \(key)")
            }
        } catch {
            errorMessage = error.localizedDescription
            ToastCenter.shared.error("Delete failed: \(error.localizedDescription)")
        }

        isLoadingValue = false
    }

    /// Re-create a string key deleted moments ago (the Undo action on the
    /// delete toast). Restores the value and, if it had one, the TTL.
    func restoreStringKey(_ key: String, value: String, ttl: Int?) async {
        guard let client = redisClient else { return }
        do {
            _ = try await client.execute(["SET", key, value])
            if let ttl = ttl, ttl > 0 {
                _ = try await client.expire(key, seconds: ttl)
            }
            if !keys.contains(key) { keys.insert(key, at: 0) }
            ToastCenter.shared.success("Restored \(key)")
        } catch {
            errorMessage = error.localizedDescription
            ToastCenter.shared.error("Restore failed: \(error.localizedDescription)")
        }
    }

    /// Save an edited string value (SET). Only valid for string keys.
    func saveStringValue(_ newValue: String) async {
        guard let client = redisClient, let key = selectedKey else {
            errorMessage = "No connection"
            return
        }
        guard selectedKeyType == "string" else {
            errorMessage = "Editing is only supported for string keys"
            return
        }

        do {
            isLoadingValue = true
            errorMessage = nil
            _ = try await client.set(key, value: newValue)
            typedValue = .string(newValue)
            selectedKeyCount = newValue.utf8.count
            // Memory footprint changed — refresh from the same source as the list.
            selectedKeySize = await client.keyMeta([key])[key]?.size ?? selectedKeySize
            keySizes[key] = selectedKeySize
            ToastCenter.shared.success("Saved \(key)")
        } catch {
            errorMessage = error.localizedDescription
            ToastCenter.shared.error("Save failed: \(error.localizedDescription)")
        }
        isLoadingValue = false
    }

    // MARK: - Per-element editing (hash / list / set / zset)

    /// Run a mutating command against the selected key, then reload its value.
    private func mutateSelected(_ command: [String], success: String) async {
        guard let client = redisClient, let key = selectedKey else { return }
        do {
            _ = try await client.execute(command)
            ToastCenter.shared.success(success)
            await loadKeyDetails(key)   // refresh the structured view
        } catch {
            errorMessage = error.localizedDescription
            ToastCenter.shared.error("\(command.first ?? "") failed: \(error.localizedDescription)")
        }
    }

    func setHashField(_ field: String, value: String) async {
        guard let key = selectedKey else { return }
        await mutateSelected(["HSET", key, field, value], success: "Set \(field)")
    }
    func deleteHashField(_ field: String) async {
        guard let key = selectedKey else { return }
        await mutateSelected(["HDEL", key, field], success: "Deleted \(field)")
    }
    func setListIndex(_ index: Int, value: String) async {
        guard let key = selectedKey else { return }
        await mutateSelected(["LSET", key, String(index), value], success: "Updated [\(index)]")
    }
    func appendList(_ value: String) async {
        guard let key = selectedKey else { return }
        await mutateSelected(["RPUSH", key, value], success: "Appended")
    }
    func removeListValue(_ value: String) async {
        guard let key = selectedKey else { return }
        await mutateSelected(["LREM", key, "0", value], success: "Removed")
    }
    /// Delete the element at a specific index. Redis has no delete-by-index, so
    /// mark it with a unique sentinel (LSET) then remove that sentinel (LREM).
    /// This avoids removing the wrong/duplicate elements that share a value.
    func removeListIndex(_ index: Int) async {
        guard let key = selectedKey, let client = redisClient else { return }
        let sentinel = "__vermi_del_\(UUID().uuidString)__"
        do {
            _ = try await client.execute(["LSET", key, String(index), sentinel])
            _ = try await client.execute(["LREM", key, "1", sentinel])
            ToastCenter.shared.success("Removed [\(index)]")
            await loadKeyDetails(key)
        } catch {
            errorMessage = error.localizedDescription
            ToastCenter.shared.error("Remove failed: \(error.localizedDescription)")
        }
    }
    func addSetMember(_ member: String) async {
        guard let key = selectedKey else { return }
        await mutateSelected(["SADD", key, member], success: "Added")
    }
    func removeSetMember(_ member: String) async {
        guard let key = selectedKey else { return }
        await mutateSelected(["SREM", key, member], success: "Removed")
    }
    func addZSetMember(_ member: String, score: Double) async {
        guard let key = selectedKey else { return }
        await mutateSelected(["ZADD", key, String(score), member], success: "Added \(member)")
    }
    func removeZSetMember(_ member: String) async {
        guard let key = selectedKey else { return }
        await mutateSelected(["ZREM", key, member], success: "Removed \(member)")
    }

    func setTTL(_ key: String, seconds: Int) async {
        guard let client = redisClient else {
            errorMessage = "No connection"
            return
        }

        do {
            let success = try await client.expire(key, seconds: seconds)
            if success {
                selectedKeyTTL = seconds
                ToastCenter.shared.success("TTL set: \(seconds)s")
            } else {
                errorMessage = "Failed to set TTL"
            }
        } catch {
            errorMessage = error.localizedDescription
            ToastCenter.shared.error("Set TTL failed: \(error.localizedDescription)")
        }
    }

    /// Remove a key's TTL (PERSIST).
    func persistKey(_ key: String) async {
        guard let client = redisClient else { return }
        do {
            _ = try await client.execute(["PERSIST", key])
            selectedKeyTTL = -1
            ToastCenter.shared.success("TTL removed")
        } catch {
            errorMessage = error.localizedDescription
            ToastCenter.shared.error("Persist failed: \(error.localizedDescription)")
        }
    }

    /// Rename the selected key (RENAME). Updates the list + selection.
    func renameKey(_ oldKey: String, to newKey: String) async {
        let target = newKey.trimmingCharacters(in: .whitespaces)
        guard let client = redisClient, !target.isEmpty, target != oldKey else { return }
        do {
            _ = try await client.execute(["RENAME", oldKey, target])
            if let i = keys.firstIndex(of: oldKey) { keys[i] = target }
            keyTypes[target] = keyTypes[oldKey]; keyTypes[oldKey] = nil
            keySizes[target] = keySizes[oldKey]; keySizes[oldKey] = nil
            if selectedKey == oldKey { selectedKey = target }
            ToastCenter.shared.success("Renamed to \(target)")
        } catch {
            errorMessage = error.localizedDescription
            ToastCenter.shared.error("Rename failed: \(error.localizedDescription)")
        }
    }

    /// Create a new string key (SET), then select it.
    func addStringKey(_ key: String, value: String, ttlSeconds: Int?) async {
        let name = key.trimmingCharacters(in: .whitespaces)
        guard let client = redisClient, !name.isEmpty else {
            errorMessage = "Key name required"
            return
        }
        do {
            _ = try await client.set(name, value: value)
            if let ttl = ttlSeconds, ttl > 0 { _ = try? await client.expire(name, seconds: ttl) }
            if !keys.contains(name) { keys.insert(name, at: 0) }
            keyTypes[name] = "string"
            keySizes[name] = value.utf8.count
            ToastCenter.shared.success("Created \(name)")
            await loadKeyDetails(name)
        } catch {
            errorMessage = error.localizedDescription
            ToastCenter.shared.error("Create failed: \(error.localizedDescription)")
        }
    }

    func reset() {
        keys = []
        keySizes = [:]
        keyTypes = [:]
        scanBuffer = []
        scanExhausted = false
        selectedKey = nil
        typedValue = .none
        selectedKeyType = ""
        selectedKeyTTL = -1
        selectedKeySize = 0
        searchText = ""
        cursor = 0
        hasMore = false
        didInitialLoad = false
    }
}
