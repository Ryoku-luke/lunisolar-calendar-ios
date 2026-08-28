import Foundation
import Observation

// MARK: - 事件同步协调器（夹在 EventStore 与 ICloudSyncProvider 中间）

/// 职责：
/// 1. EventStore 每次 add/update/delete 后调 `didChangeLocal(events:)` 或直接调 `push(event:)` 推到云端
/// 2. 定期调用 `pullAndMerge()` 拉云端增量 → 合并进本地 EventStore（last-write-wins + 墓碑删除）
/// 3. 持久化 lastSyncMs（写入 UserDefaults，下次启动继续增量同步）
/// 4. 对外暴露 status / lastResult（iOS 17+ 用 @Observable，UI 自动追踪）
@MainActor
@Observable
public final class EventSyncCoordinator: @unchecked Sendable {

    // MARK: - 对外状态（@Observable 自动追踪属性访问，UI 读取即订阅）

    public private(set) var status: SyncStatus = .idle
    /// 最近一次同步结果（成功/失败均记录）
    public private(set) var lastResult: SyncResult?

    /// 同步开关（默认 true；用户可在设置里关掉"iCloud 同步"）
    public var isEnabled: Bool = true {
        didSet {
            if !isEnabled { status = .idle }
        }
    }

    // MARK: - 依赖

    public unowned let eventStore: EventStore
    public let provider: any ICloudSyncProvider

    // MARK: - 内部状态

    private let defaults: UserDefaults
    private let lastSyncKeyLo = "Lunisolar.sync.lastSyncMs.lo"
    private let lastSyncKeyHi = "Lunisolar.sync.lastSyncMs.hi"
    private let versionTrackingKey = "Lunisolar.sync.versionMap"

    /// 每个 event.id 当前同步版本号（每次 push version++，云端以它决定 last-write-wins）
    private var versionMap: [String: Int64] = [:]

    /// 上次成功同步的毫秒时间戳（增量同步起点）
    public private(set) var lastSyncMs: Int64 {
        get {
            // BUG #31 修复：UserDefaults 没有原生 Int64 setter；
            // 直接 set(Int(...),forKey:) 在 32-bit 平台会把 >2^31 的时间戳截断。
            // 改为位拆分持久化为两个 32-bit 半字（完全不依赖平台 Int 宽度）。
            // 使用 Int(truncatingIfNeeded:) 适配 32/64-bit。
            let loVal = defaults.integer(forKey: lastSyncKeyLo)
            let hiVal = defaults.integer(forKey: lastSyncKeyHi)
            let lo = UInt32(truncatingIfNeeded: loVal)
            let hi = UInt32(truncatingIfNeeded: hiVal)
            return Int64(bitPattern: (UInt64(hi) << 32) | UInt64(lo))
        }
        set {
            let bits = UInt64(bitPattern: newValue)
            let lo = UInt32(truncatingIfNeeded: bits)
            let hi = UInt32(truncatingIfNeeded: bits >> 32)
            // UInt32 → Int：先扩到 UInt(平台字长) 再用 bitPattern 转 Int，
            // 这样 32/64-bit 平台都能正确落盘且不损失位。
            defaults.set(Int(bitPattern: UInt(truncatingIfNeeded: lo)), forKey: lastSyncKeyLo)
            defaults.set(Int(bitPattern: UInt(truncatingIfNeeded: hi)), forKey: lastSyncKeyHi)
        }
    }

    // MARK: - Init

    /// - Parameters:
    ///   - eventStore: 事件库（unowned 防止循环引用；App 一般是 EventStore.shared）
    ///   - provider:   云端提供者（Mock 用于测试，RealCloudKitProvider 用于真机）
    ///   - defaults:   持久化位置（默认 .standard；测试可传临时 init(suiteName:)）
    public init(
        eventStore: EventStore,
        provider: any ICloudSyncProvider,
        defaults: UserDefaults = .standard
    ) {
        self.eventStore = eventStore
        self.provider = provider
        self.defaults = defaults
        // BUG #31 修复：优先走 JSON 无损加载；失败则回退旧的 [String:Int] 字典格式
        self.loadVersionMap()
        if self.versionMap.isEmpty,
           let raw = defaults.dictionary(forKey: versionTrackingKey) as? [String: Int] {
            self.versionMap = raw.mapValues { Int64($0) }
        }
    }

    // MARK: - 1. 推：本地变更 → 云端

    /// 推送单条事件（add/update 用）
    @discardableResult
    public func push(event: CalendarEvent, isDeleted: Bool = false) async throws -> SyncResult {
        try await push(events: [event], deletedIDs: isDeleted ? [event.id.uuidString] : [])
    }

    /// 批量推送（事件列表 + 要删的 ID 集合）
    @discardableResult
    public func push(events: [CalendarEvent], deletedIDs: Set<String> = []) async throws -> SyncResult {
        let start = Date()
        status = .inProgress(.push)

        let available = await provider.isAvailable
        guard isEnabled else {
            let r = SyncResult(direction: .push, pushed: 0, pulled: 0, conflictsResolved: 0,
                               errors: [], startedAt: start, finishedAt: Date())
            status = .succeeded(r)
            lastResult = r
            return r
        }
        guard available else {
            let err = SyncError.notAvailable
            status = .failed(err)
            throw err
        }

        // 编码事件记录（递增版本号，但**暂不写入 versionMap**，推送成功后才真正提交，避免"云没收到本地已 advance 版本"导致永久丢失推送）
        var records: [SyncRecord] = []
        var proposedVersions: [String: Int64] = [:]   // id → 计划中的新版本号
        for ev in events {
            let nextVer = (versionMap[ev.id.uuidString] ?? 0) + 1
            let rec = try SyncRecord.eventRecord(
                for: ev,
                version: nextVer,
                originDevice: provider.currentDeviceID
            )
            records.append(rec)
            proposedVersions[ev.id.uuidString] = nextVer
        }

        // 墓碑：deletedIDs 中如果没在上面被覆盖（即删除了一个不在 events 列表的本地记录）
        for delID in deletedIDs {
            guard !records.contains(where: { $0.id == delID }) else { continue }
            let nextVer = (versionMap[delID] ?? 0) + 1
            let existing = eventStore.events.first(where: { $0.id.uuidString == delID })
            let ms: Int64 = {
                if let d = existing?.updatedAt { return Int64(d.timeIntervalSince1970 * 1000) }
                return Int64(Date().timeIntervalSince1970 * 1000)
            }()
            let tomb = SyncRecord(
                id: delID, kind: .event,
                version: nextVer, originDevice: provider.currentDeviceID,
                updatedAtMs: ms, isDeleted: true, payloadJSON: "{}"
            )
            records.append(tomb)
            proposedVersions[delID] = nextVer
        }

        let (written, perRecordErrors) = try await provider.push(records: records)

        // ---- provider.push 成功（没有抛异常）才真正提交版本号 ----
        for (id, v) in proposedVersions {
            // 若有逐记录错误，只跳过失败的那些（不 advance version），其余仍可标记已推送
            if perRecordErrors[id] != nil { continue }
            versionMap[id] = v
        }
        persistVersionMap()

        var errors: [SyncError] = []
        for (_, e) in perRecordErrors { errors.append(e) }

        // push 成功后推进 lastSyncMs（避免下次 pull 把自己刚推上去的记录再拉回来）
        // 只看"成功写入"的那些记录：perRecordErrors 里没有 error 的 id
        let successUpdatedMs = records.compactMap { r -> Int64? in
            if perRecordErrors[r.id] != nil { return nil }
            return r.updatedAtMs
        }
        if let maxMs = successUpdatedMs.max(), maxMs > lastSyncMs {
            lastSyncMs = maxMs
            // lastSyncMs 的 setter 已持久化到 lo/hi 两个 key，无需再写
        }

        let end = Date()
        let r = SyncResult(direction: .push, pushed: written, pulled: 0,
                           conflictsResolved: 0, errors: errors,
                           startedAt: start, finishedAt: end)
        if errors.isEmpty {
            status = .succeeded(r)
        } else if let first = errors.first {
            status = .failed(first)
        }
        lastResult = r
        return r
    }

    // MARK: - 2. 拉：云端 → 本地，合并进 EventStore

    @discardableResult
    public func pullAndMerge() async throws -> SyncResult {
        let start = Date()
        status = .inProgress(.pull)

        let available = await provider.isAvailable
        guard isEnabled else {
            let r = SyncResult(direction: .pull, pushed: 0, pulled: 0, conflictsResolved: 0,
                               errors: [], startedAt: start, finishedAt: Date())
            status = .succeeded(r); lastResult = r; return r
        }
        guard available else {
            let err = SyncError.notAvailable; status = .failed(err); throw err
        }

        let remote = try await provider.pull(sinceMs: lastSyncMs)
        var merged = 0, conflicts = 0, errors: [SyncError] = []

        for remoteRec in remote {
            // 解码
            let remoteEvent: CalendarEvent?
            if remoteRec.isDeleted {
                remoteEvent = nil
            } else {
                do {
                    remoteEvent = try remoteRec.decodedEvent()
                } catch {
                    errors.append(.invalidPayload("\(remoteRec.id) 解码失败"))
                    continue
                }
            }

            let localVersion = versionMap[remoteRec.id] ?? 0
            // last-write-wins：云端 version > local → 采纳云端；否则丢弃（本地更新）
            if remoteRec.version > localVersion {
                // 冲突：本地版本追踪落后于云端，并且本地已经有这个 ID 的事件
                // （若本地不存在这个 ID，就是"云端新增"，不算冲突）
                let localExisting = eventStore.events.first(where: { $0.id.uuidString == remoteRec.id })
                let isConflict: Bool = (localExisting != nil) && (localVersion > 0)
                if isConflict { conflicts += 1 }

                if remoteRec.isDeleted {
                    // 云端墓碑 → 本地删除（按 ID 查后删）
                    if let l = localExisting {
                        eventStore.delete(l, skipSync: true)
                    }
                } else if let ev = remoteEvent {
                    // 写入本地；若已存在 update，否则 add
                    if localExisting != nil {
                        var updated = ev
                        updated.updatedAt = Date()
                        eventStore.update(updated, skipSync: true)
                    } else {
                        var inserted = ev
                        inserted.updatedAt = Date()
                        eventStore.add(inserted, skipSync: true)
                    }
                }
                versionMap[remoteRec.id] = remoteRec.version
                merged += 1
            }
        }
        persistVersionMap()

        if let max = remote.map(\.updatedAtMs).max(), max > lastSyncMs { lastSyncMs = max }

        let end = Date()
        let r = SyncResult(direction: .pull, pushed: 0, pulled: merged,
                           conflictsResolved: conflicts, errors: errors,
                           startedAt: start, finishedAt: end)
        if errors.isEmpty { status = .succeeded(r) } else if let f = errors.first { status = .failed(f) }
        lastResult = r
        return r
    }

    // MARK: - 3. 双向同步（先 push 本地更改 → 再 pull 合并云端增量）

    @discardableResult
    public func syncBidirectional() async throws -> SyncResult {
        // 防止并发：如果已经在同步，直接返回上次结果
        guard !isSyncing else {
            if let last = lastResult {
                return last
            }
            throw SyncError.notAvailable
        }
        isSyncing = true
        defer { isSyncing = false }

        let start = Date()
        status = .inProgress(.both)

        var pushed = 0, pulled = 0, conflicts = 0, allErrors: [SyncError] = []

        // 1. 先 push 本地脏事件
        let (dirtyEvents, deletedIDs) = eventStore.consumeDirtyEvents()
        if !dirtyEvents.isEmpty || !deletedIDs.isEmpty {
            do {
                let r1 = try await push(events: dirtyEvents, deletedIDs: deletedIDs)
                pushed += r1.pushed; allErrors.append(contentsOf: r1.errors)
                if allErrors.isEmpty {
                    eventStore.clearDirtyFlags()
                }
            } catch {
                allErrors.append(mapError(error))
            }
        }

        // 2. 再 pull 合并云端增量
        do {
            let r2 = try await pullAndMerge()
            pulled += r2.pulled; conflicts += r2.conflictsResolved
            allErrors.append(contentsOf: r2.errors)
        } catch {
            allErrors.append(mapError(error))
        }

        // 3. 墓碑 TTL 清理（P3 修复）：默认 30 天 = 30 * 86400 * 1000 ms
        //    失败不影响整体同步结果，只把错误追加（用户可在日志里看到）
        do {
            let ttlMs: Int64 = 30 * 86400 * 1000
            let cutoffMs = Int64(Date().timeIntervalSince1970 * 1000) - ttlMs
            _ = try await provider.purgeExpiredTombstones(olderThanMs: cutoffMs)
        } catch {
            allErrors.append(mapError(error))
        }

        let end = Date()
        let r = SyncResult(direction: .both, pushed: pushed, pulled: pulled,
                           conflictsResolved: conflicts, errors: allErrors,
                           startedAt: start, finishedAt: end)
        if allErrors.isEmpty { status = .succeeded(r) } else if let f = allErrors.first { status = .failed(f) }
        lastResult = r
        return r
    }

    /// 防止 syncBidirectional 并发执行的标记
    private var isSyncing = false
    /// 墓碑 TTL（毫秒）：30 天
    public static let tombstoneTTLMs: Int64 = 30 * 86400 * 1000

    // MARK: - 4. 订阅开启（实时推送）

    /// 开启/关闭 CKQuerySubscription，真机 CloudKit 支持后可实现"改动立刻推"
    @discardableResult
    public func enableSubscription(_ enable: Bool) async -> Bool {
        await provider.setupSubscription(enabled: enable)
    }

    // MARK: - 辅助

    private func persistVersionMap() {
        // BUG #31 修复：直接用 Int(clamping:) 会把超过 Int.max 的版本号截断（32-bit 平台）。
        // 改为 JSONEncoder 把 [String: Int64] 编码为 Data，写入 UserDefaults，无损且跨平台。
        do {
            let data = try JSONEncoder().encode(versionMap)
            defaults.set(data, forKey: versionTrackingKey)
        } catch {
            AppLogger.sync.error("persistVersionMap 编码失败: \(error)")
        }
    }

    private func loadVersionMap() {
        guard let data = defaults.data(forKey: versionTrackingKey) else { return }
        do {
            versionMap = try JSONDecoder().decode([String: Int64].self, from: data)
        } catch {
            // 向后兼容：读旧的 [String: Int] 格式
            if let raw = defaults.dictionary(forKey: versionTrackingKey) as? [String: Int] {
                versionMap = raw.mapValues { Int64($0) }
            }
            AppLogger.sync.warning("loadVersionMap 失败: \(error)，\(versionMap.isEmpty ? "已清空" : "已回退旧格式")")
        }
    }

    private func mapError(_ e: Error) -> SyncError {
        e as? SyncError ?? .unknown(String(describing: e))
    }

    // MARK: - 测试/调试辅助

    /// 清除版本追踪和 lastSyncMs（单测 tearDown）
    public func resetSyncMetadata() {
        versionMap.removeAll()
        lastSyncMs = 0
        defaults.removeObject(forKey: versionTrackingKey)
        defaults.removeObject(forKey: lastSyncKeyLo)
        defaults.removeObject(forKey: lastSyncKeyHi)
    }
}

// MARK: - EventStore 集成：CRUD 后自动 push（通过 skipSync 防止回环）

/// 关键：EventStore 的 add/update/delete 增加 `skipSync: Bool` 参数。
/// 默认 `skipSync = false`，会把变更自动同步（fire-and-forget，不阻塞 UI）。
/// `skipSync = true` 供 Coordinator 在 pull 合并回本地时调用，避免再次推回云端形成回环。

// 本模块只提供分类，实际修改在 EventStore.swift
