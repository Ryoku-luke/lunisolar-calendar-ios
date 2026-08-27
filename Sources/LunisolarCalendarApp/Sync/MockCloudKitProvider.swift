import Foundation

// MARK: - Mock CloudKit 提供者（本地测试 & Preview 可直接使用）

/// 内存级 Mock，行为尽量贴近真实 CloudKit 私有数据库 Custom Zone：
///   - last-write-wins 冲突解决（比较 version，若相等再比 updatedAtMs）
///   - 支持"模拟网络延迟" `simulatedLatencyMs`（默认 0，单元测试 0 加速，UI 测试可调到 300ms~2s 模拟体验）
///   - 支持"离线模式"（`isOnline = false`），push/pull 立即抛 `.networkUnavailable`，方便测试合并逻辑
///   - 支持"增量同步"：每次 pull(sinceMs) 只返回 updatedAtMs > sinceMs 的记录
///   - 共享状态通过全局 Actor 隔离，保证并发安全
@globalActor public final actor MockCloudKitStore {
    public static let shared = MockCloudKitStore()

    /// ID -> Record（内存）
    private(set) var records: [String: SyncRecord] = [:]
    /// 每次写入会递增，用作全局时钟（用于 sinceMs 增量拉取）
    private(set) var monotonicClock: Int64 = 0

    /// 把 record 写入，返回是否实际发生变更（调用侧统计）
    func upsert(_ rec: SyncRecord) -> Bool {
        monotonicClock += 1
        guard let existing = records[rec.id] else {
            records[rec.id] = rec
            return true
        }
        // last-write-wins: 先比 version，version 相同则比 updatedAtMs
        if rec.version > existing.version ||
           (rec.version == existing.version && rec.updatedAtMs >= existing.updatedAtMs) {
            records[rec.id] = rec
            return rec != existing
        }
        return false
    }

    /// 取某 ID
    func get(_ id: String) -> SyncRecord? { records[id] }

    /// 是否有
    func contains(_ id: String) -> Bool { records[id] != nil }

    /// 物理删除 isDeleted=true 且 updatedAtMs < olderThanMs 的墓碑，返回删除条数
    func purgeExpiredTombstones(olderThanMs: Int64) -> Int {
        let toRemove = records.values.filter { $0.isDeleted && $0.updatedAtMs < olderThanMs }.map(\.id)
        guard !toRemove.isEmpty else { return 0 }
        for id in toRemove { records.removeValue(forKey: id) }
        return toRemove.count
    }

    /// 删除（写墓碑）：直接 upsert 一个 isDeleted=true 的 record
    func markDeleted(id: String, version: Int64, originDevice: String, updatedAtMs: Int64) {
        let tombstone = SyncRecord(
            id: id, kind: .event, version: version, originDevice: originDevice,
            updatedAtMs: updatedAtMs, isDeleted: true, payloadJSON: "{}"
        )
        _ = upsert(tombstone)
    }

    /// 增量返回：sinceMs < updatedAtMs（严格大于，避免重复拉）
    func recordsSince(_ ms: Int64) -> [SyncRecord] {
        records.values.filter { $0.updatedAtMs > ms }
    }

    /// 清空（仅测试用）
    func reset() {
        records.removeAll(keepingCapacity: true)
        monotonicClock = 0
    }

    /// 当前记录数（测试断言用）
    var count: Int { records.count }
}

/// 测试驱动/预览用的 Provider
public final class MockCloudKitProvider: ICloudSyncProvider, @unchecked Sendable {

    // MARK: - 配置

    /// 模拟网络延迟（毫秒）。默认 0，测试里调成 300 可看到 UI loading
    public var simulatedLatencyMs: Int = 0
    /// 离线开关：true → 所有 push/pull 直接抛出 networkUnavailable
    public var isOnline: Bool = true
    /// iCloud 可用开关（比如用户未登录 → false）
    public var iCloudAvailable: Bool = true
    /// 模拟配额超限（默认 false）
    public var simulateQuotaExceeded: Bool = false
    /// 模拟订阅是否启用（setupSubscription 返回此值）
    public var subscriptionEnabled: Bool = false

    // MARK: - 设备ID

    public let currentDeviceID: String

    // MARK: - 内部状态

    private let store: MockCloudKitStore
    /// 最近一次同步时间戳（毫秒），pull(sinceMs) 默认用它
    public private(set) var lastSyncMs: Int64 = 0

    // MARK: - Init

    /// - Parameters:
    ///   - deviceID: 传 UUID().uuidString 模拟多设备；多 Provider 用相同 store 共享云端
    ///   - sharedStore: 默认走 MockCloudKitStore.shared，传自定义实例可做"隔离小云端"
    public init(
        deviceID: String = UUID().uuidString,
        sharedStore: MockCloudKitStore = MockCloudKitStore.shared
    ) {
        self.currentDeviceID = deviceID
        self.store = sharedStore
    }

    // MARK: - ICloudSyncProvider

    public var isAvailable: Bool {
        get async { iCloudAvailable }
    }

    public func push(records: [SyncRecord]) async throws -> (written: Int, errors: [String: SyncError]) {
        try await simulateLatency()
        guard isOnline else { throw SyncError.networkUnavailable }
        guard iCloudAvailable else { throw SyncError.notAvailable }
        guard !simulateQuotaExceeded else { throw SyncError.quotaExceeded }

        var written = 0
        let errors: [String: SyncError] = [:]
        for r in records {
            let changed = await store.upsert(r)
            if changed { written += 1 }
        }
        if let maxMs = records.map(\.updatedAtMs).max(), maxMs > lastSyncMs {
            lastSyncMs = maxMs
        }
        return (written, errors)
    }

    public func pull(sinceMs: Int64) async throws -> [SyncRecord] {
        try await simulateLatency()
        guard isOnline else { throw SyncError.networkUnavailable }
        guard iCloudAvailable else { throw SyncError.notAvailable }

        let recs = await store.recordsSince(sinceMs)
        if let max = recs.map(\.updatedAtMs).max(), max > lastSyncMs {
            lastSyncMs = max
        }
        return recs
    }

    public func delete(recordIDs: [String]) async throws -> (deletedCount: Int, errors: [String: SyncError]) {
        try await simulateLatency()
        guard isOnline else { throw SyncError.networkUnavailable }
        guard iCloudAvailable else { throw SyncError.notAvailable }

        var deletedCount = 0
        let errors: [String: SyncError] = [:]
        for id in recordIDs {
            let existingVersion = await store.get(id)?.version ?? 0
            let ms = Int64(Date().timeIntervalSince1970 * 1000)
            await store.markDeleted(
                id: id,
                version: existingVersion + 1,
                originDevice: currentDeviceID,
                updatedAtMs: ms
            )
            deletedCount += 1
        }
        return (deletedCount, errors)
    }

    public func setupSubscription(enabled: Bool) async -> Bool {
        try? await simulateLatency()
        guard iCloudAvailable else { return false }
        subscriptionEnabled = enabled
        return true
    }

    public func purgeExpiredTombstones(olderThanMs: Int64) async throws -> Int {
        try await simulateLatency()
        guard isOnline else { throw SyncError.networkUnavailable }
        guard iCloudAvailable else { throw SyncError.notAvailable }
        return await store.purgeExpiredTombstones(olderThanMs: olderThanMs)
    }

    // MARK: - 内部

    private func simulateLatency() async throws {
        guard simulatedLatencyMs > 0 else { return }
        // Task.sleep nanoseconds 不能太长 (≤ Int.max) ，安全起见按 ms 拆分
        let ns = min(UInt64(simulatedLatencyMs) * 1_000_000, 5_000_000_000)
        try await Task.sleep(nanoseconds: ns)
    }

    // MARK: - 测试辅助（非协议方法，Mock 专属 API）

    /// 云端当前记录数
    nonisolated
    public func serverRecordCount() async -> Int {
        await store.count
    }

    /// 云端是否有某 record
    nonisolated
    public func serverContains(id: String) async -> Bool {
        await store.contains(id)
    }

    /// 取某条 server 记录
    nonisolated
    public func serverGet(id: String) async -> SyncRecord? {
        await store.get(id)
    }

    /// 直接在"云端"注入一条记录（模拟其它设备写了云端）
    nonisolated
    public func injectServerRecord(_ rec: SyncRecord) async {
        _ = await store.upsert(rec)
    }

    /// 重置 Mock 全局云端（单测 tearDown 用）
    nonisolated
    public static func resetGlobalStore() async {
        await MockCloudKitStore.shared.reset()
    }
}
