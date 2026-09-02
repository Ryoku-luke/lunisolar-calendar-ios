import Foundation
// EventStore 里多处 AppLogger.app.error/warning/notice 使用 os.Logger 字符串插值
// （appendLiteral / appendInterpolation / OSLogInterpolation），这些由 module `os` 提供。
// 仅 import Foundation 在 iOS SDK 下不自动 transitively 引入 os，Xcode 会级联报 N*6 条
// "defining module 'os'"错误，一并补上。
#if canImport(os)
import os
#endif

#if canImport(Observation)
import Observation
#endif

// MARK: - 事件存储

#if canImport(Observation)
@Observable
#endif
@MainActor
public final class EventStore {

    @MainActor public static let shared = EventStore()

    #if !canImport(Observation)
    // Fallback: Linux/非Apple平台下无需Observation
    #endif

    private(set) var events: [CalendarEvent] = []

    /// 查询缓存：按日期首日缓存 occurs(on:) 结果，避免月视图 42 格 × N 事件全量遍历
    private var eventCache: [Date: [CalendarEvent]] = [:]
    private var statsCache: [Date: (count: Int, priority: Priority?)] = [:]

    // MARK: P6 二级索引（O(1) by-id 定位）
    // events 数组永远按 startDate 升序；此字典维护 id → 下标，
    // 所有 CRUD 操作都必须同步更新它，禁止在维护路径上直接 O(N) 扫 id。
    private var idToIndex: [UUID: Int] = [:]
    /// 重建 idToIndex：事件数组读盘、清空、大 merge 后调用一次 O(N)
    private func rebuildIDIndex() {
        idToIndex.removeAll(keepingCapacity: true)
        for (i, ev) in events.enumerated() {
            idToIndex[ev.id] = i
        }
    }
    /// idToIndex 平移：在 index 前插入 count 个元素 → index..<endIndex 的下标全部 +count
    private func shiftIndices(from index: Int, by delta: Int) {
        guard delta != 0 else { return }
        // delta > 0 是插入后：[index, endIndex) 原值 + delta
        // delta < 0 是删除后：[index+abs(delta), endIndex) 原值 - abs(delta)
        // 所以统一写：遍历字典，value >= threshold（起始点）的都 + delta。
        let threshold = delta > 0 ? index : index - delta
        for (id, i) in idToIndex where i >= threshold {
            idToIndex[id] = i + delta
        }
    }
    /// O(1) by-id 读；找不到 = nil
    private func indexOfEvent(id: UUID) -> Int? {
        idToIndex[id]
    }
    /// 按 UUID 字符串直接返回事件本体；同步协调器/批量查询使用，避免 O(N) 扫表
    internal func eventBy(idString: String) -> CalendarEvent? {
        guard let uuid = UUID(uuidString: idString),
              let idx = idToIndex[uuid] else { return nil }
        return events[idx]
    }
    /// 消费"未推送变更"：返回（dirtyEvents, deletedIDs）。
    /// P6 优化：避免原来 events.filter { dirtyEventIDs.contains($0.id.uuidString) } 对 N 条事件
    /// 每次 O(N) 扫表 + uuidString 分配，直接按 dirtyEventIDs 走 idToIndex 字典 O(1) 定位。
    public func consumeDirtyEvents() -> (events: [CalendarEvent], deletedIDs: Set<String>) {
        var evs: [CalendarEvent] = []
        evs.reserveCapacity(dirtyEventIDs.count)
        for idStr in dirtyEventIDs {
            if let ev = eventBy(idString: idStr) { evs.append(ev) }
        }
        // 保持按 startDate 升序返回（便于 push 时云端有序接收 & 单元测试断言）
        evs.sort { $0.startDate < $1.startDate }
        return (evs, deletedEventIDs)
    }

    // MARK: P6 排序不变式：events 永远按 startDate 升序排列

    /// 二分查「第一个 startDate >= target 的位置」，等价于标准库 partitioningIndex(where:)
    private func sortedInsertionIndex(for startDate: Date) -> Int {
        if events.isEmpty { return 0 }
        // P6-3 小优化：利用最近一次 insert 位置做"邻近插入"预检；
        // 绝大多数"未来几天"的提醒会按时间递增插入，直接落在 lastInsertHint 附近，常命中。
        if let hint = lastInsertHint {
            if hint > 0, hint <= events.count {
                let L = events[hint - 1].startDate
                if hint == events.count {
                    if L < startDate { return hint }
                } else {
                    let R = events[hint].startDate
                    if L < startDate && startDate <= R { return hint }
                }
            }
        }
        var lo = 0, hi = events.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if events[mid].startDate < startDate {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        lastInsertHint = lo
        return lo
    }
    /// 最近一次插入位置缓存，P6-3：加速时间大致递增的连续 add（批量导入/新建提醒场景）
    private var lastInsertHint: Int? = nil
    private func clearLastInsertHint() { lastInsertHint = nil }

    /// 脏事件 ID 集合（已变更但未推送到云端的事件）
    private var dirtyEventIDs: Set<String> = []
    /// 已删除但未推送到云端的事件 ID
    private var deletedEventIDs: Set<String> = []
    /// 同步推送队列：序列化多个 push 请求，避免并发竞争
    private var pushQueue: [() async -> Void] = []
    private var isPushing = false

    /// P5 性能：save debounce work item，合并 0.5s 内的多次 CRUD 的磁盘写入
    private var pendingSaveWorkItem: DispatchWorkItem?
    private let saveDebounceInterval: TimeInterval = 0.5

    private let saveURL: URL
    /// dirtyEventIDs 持久化路径（与 saveURL 同目录，P4 修复）
    private let dirtyIDsURL: URL
    /// deletedEventIDs 持久化路径（与 saveURL 同目录，P4 修复）
    private let deletedIDsURL: URL

    /// 可选 App Group ID：配了之后 EventStore.save() 会顺手写入 Widget 共享快照
    /// （App Group 未配置时也不会崩，仅回退 Documents 路径，Widget 那边按"过期→占位"处理）
    ///
    /// ⚠️  重要：如果你的工程创建了 Widget Extension，必须在 App 启动时显式赋值：
    /// ```
    /// EventStore.shared.widgetAppGroupID = "group.com.yourapp.lunisolar"
    /// ```
    /// 主 App 和 Widget Extension 必须同时勾上同一个 App Group Capability，否则 Widget 读不到真实待办。
    public var widgetAppGroupID: String? {
        didSet {
            #if DEBUG
            if let id = widgetAppGroupID, !id.isEmpty {
                AppLogger.app.notice("App Group 已配置：\(id)")
            }
            #endif
        }
    }

    /// iCloud 同步协调器（可选）。设置后：默认 CRUD 自动 fire-and-forget 推送云端
    public weak var syncCoordinator: EventSyncCoordinator?

    public convenience init() {
        self.init(storageBaseDir: nil)
    }

    /// 测试专用：允许自定义持久化根目录，避免多 XCTestCase 实例共享同一个 /tmp 文件。
    /// - Parameter storageBaseDir: 传入一个临时目录（如 FileManager.temporaryDirectory 下 UUID 子目录）
    public convenience init(storageBaseDir: URL) {
        self.init(storageBaseDir: storageBaseDir as URL?)
    }

    /// 内部指定构造：storageBaseDir = nil → 走系统 Documents + /tmp 回退（生产环境默认）
    private init(storageBaseDir: URL?) {
        let baseDir: URL
        if let custom = storageBaseDir {
            baseDir = custom
        } else {
            let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            var docs = paths.first
            // BUG #34 修复：用可选绑定替代短路 + docs! 强制解包，避免后续条件重构误改短路顺序导致崩溃
            if let unwrapped = docs,
               !FileManager.default.fileExists(atPath: unwrapped.path) {
                docs = nil
            }
            if docs == nil {
                docs = URL(fileURLWithPath: NSTemporaryDirectory())
            }
            baseDir = docs ?? URL(fileURLWithPath: NSTemporaryDirectory())
        }
        self.saveURL = baseDir.appendingPathComponent("calendar_events.json")
        self.dirtyIDsURL = baseDir.appendingPathComponent("dirty_event_ids.json")
        self.deletedIDsURL = baseDir.appendingPathComponent("deleted_event_ids.json")
        // 确保父目录存在
        try? FileManager.default.createDirectory(
            at: saveURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        load()
        loadDirtyFlags()

        #if DEBUG
        // DEBUG 下提醒集成者配置 App Group（避免 Widget 读不到快照浑然不知）
        // 仅当生产路径（自定义 baseDir 的测试用例不提示）
        if storageBaseDir == nil {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                // BUG #34 修复：用 isEmpty(orNil:) 思路的可选链替代短路 + ! 强制解包
                if (self.widgetAppGroupID?.isEmpty ?? true) {
                    #if canImport(UIKit)
                    // N4 修复：os.Logger.warning(_:) 形参为 OSLogMessage（ExpressibleByStringInterpolation），
                    // 支持字符串字面量 / 插值，但不接受普通 String 表达式参与 `+` 二元拼接；
                    // 拼接结果 Swift 不会隐式转 OSLogMessage → "Cannot convert String to OSLogMessage"。
                    // 改成单字面量 + 换行 + 插值（任何平台下语义一致，跨 SPM/Xcode）。
                    let gid = String(describing: EventStore.shared.widgetAppGroupID)
                    AppLogger.app.warning("""
                    widgetAppGroupID 未设置——若使用 Widget Extension，\
                    请在 App 启动时给 EventStore.shared.widgetAppGroupID 赋值你的 App Group ID。\
                    （当前值：\(gid)）
                    """)
                    #endif
                }
            }
        }
        #endif
    }

    // MARK: - 缓存失效

    /// CRUD 后调用，清空查询缓存（下次查询时按需重建）
    private func invalidateCache() {
        eventCache.removeAll(keepingCapacity: true)
        statsCache.removeAll(keepingCapacity: true)
    }

    // MARK: - CRUD

    /// 单条插入：二分定位 + 索引平移，O(log N)。
    public func add(_ event: CalendarEvent, skipSync: Bool = false) {
        let at = sortedInsertionIndex(for: event.startDate)
        events.insert(event, at: at)
        // idToIndex 维护：新项 at，所有>=at 的下标 +1
        shiftIndices(from: at, by: 1)
        idToIndex[event.id] = at
        invalidateCache()
        save()
        dirtyEventIDs.insert(event.id.uuidString)
        if !skipSync {
            enqueuePush()
        }
    }

    /// 批量插入：每条单独走二分插入（配合 lastInsertHint，递增时间序列近乎 O(1)）。
    /// 相比 "append 全部 → sort()"，保持不变式更严谨，单次 O(K log (N+K))，
    /// 更关键是「update / 冲突 id 能 O(1) 命中」，不会先脏了数组再 sort 回来。
    public func batchAdd(_ incoming: [CalendarEvent], skipSync: Bool = false) {
        guard !incoming.isEmpty else { return }
        for ev in incoming {
            let at = sortedInsertionIndex(for: ev.startDate)
            events.insert(ev, at: at)
            shiftIndices(from: at, by: 1)
            idToIndex[ev.id] = at
            dirtyEventIDs.insert(ev.id.uuidString)
        }
        invalidateCache()
        save()
        if !skipSync {
            enqueuePush()
        }
    }

    /// 更新事件：若 startDate 变了就"抽出+重新二分插入"，否则原地赋值保持索引不变。
    public func update(_ event: CalendarEvent, skipSync: Bool = false) {
        guard let idx = indexOfEvent(id: event.id) else { return }
        var applied = event
        applied.updatedAt = Date()
        let oldStart = events[idx].startDate
        if oldStart == applied.startDate {
            // 位置没变：直接替换，idToIndex 不变
            events[idx] = applied
        } else {
            // 位置变了：先移除旧的，再按新 startDate 插入
            events.remove(at: idx)
            idToIndex.removeValue(forKey: applied.id)
            shiftIndices(from: idx, by: -1)
            let at = sortedInsertionIndex(for: applied.startDate)
            events.insert(applied, at: at)
            shiftIndices(from: at, by: 1)
            idToIndex[applied.id] = at
        }
        invalidateCache()
        save()
        dirtyEventIDs.insert(applied.id.uuidString)
        if !skipSync {
            enqueuePush()
        }
    }

    /// 删除事件：O(1) by-id 定位，O(1) 字典平移
    /// ⚠️ 同步取消 pending 通知：否则用户删除的 reminder 到点仍会弹出（P1 级别体验问题）。
    public func delete(_ event: CalendarEvent, skipSync: Bool = false) {
        guard let idx = indexOfEvent(id: event.id) else { return }
        events.remove(at: idx)
        idToIndex.removeValue(forKey: event.id)
        shiftIndices(from: idx, by: -1)
        invalidateCache()
        save()
        dirtyEventIDs.remove(event.id.uuidString)
        deletedEventIDs.insert(event.id.uuidString)
        // 被删除事件的 pending 本地通知必须立即取消（UNUserNotificationCenter 是跨 App 重启持久的）
        NotificationManager.shared.cancelNotification(for: event)
        if !skipSync {
            enqueuePush()
        }
    }

    public func toggleCompleted(_ event: CalendarEvent, skipSync: Bool = false) {
        guard let idx = indexOfEvent(id: event.id) else { return }
        let wasNotCompleted = !events[idx].isCompleted
        events[idx].isCompleted.toggle()
        events[idx].updatedAt = Date()
        invalidateCache()
        save()
        dirtyEventIDs.insert(events[idx].id.uuidString)
        // 刚被标记为「已完成」的 reminder，要移除其 pending 通知（完成的事不再提醒）
        if wasNotCompleted && events[idx].isCompleted {
            NotificationManager.shared.cancelNotification(for: events[idx])
        }
        if !skipSync {
            enqueuePush()
        }
    }

    /// 标记事件通知已触发（防止重复弹窗）
    /// 默认 skipSync=true：通知标记是"设备本地状态"，通常不应该推上云端，
    /// 更不该因此把事件打为 dirty，否则下次别的 CRUD 会把事件"捎带"推云。
    public func markNotified(_ event: CalendarEvent, skipSync: Bool = true) {
        guard let idx = indexOfEvent(id: event.id) else { return }
        events[idx].isNotified = true
        events[idx].updatedAt = Date()
        invalidateCache()
        save()
        if !skipSync {
            dirtyEventIDs.insert(events[idx].id.uuidString)
            enqueuePush()
        }
    }

    // MARK: - 同步辅助

    /// 将 push 操作入队（序列化执行，避免并发竞争）
    private func enqueuePush() {
        pushQueue.append { @MainActor [weak self] in
            guard let self = self else { return }
            await self.flushDirtyAndDeleted()
        }
        // 只有当前没有在执行时才启动
        if !isPushing {
            isPushing = true
            Task { @MainActor in
                await self.drainPushQueue()
            }
        }
    }

    /// 序列化执行 push 队列中的所有操作
    private func drainPushQueue() async {
        while !pushQueue.isEmpty {
            let next = pushQueue.removeFirst()
            await next()
        }
        isPushing = false
    }

    /// 将当前 dirty + deleted 的事件批量推送到协调器，推送成功后清空集合
    private func flushDirtyAndDeleted() async {
        guard let co = syncCoordinator else {
            // 无协调器时保留 dirty 标记，等用户重新启用 iCloud 同步后再推送
            return
        }
        // 收集脏事件
        let dirtyEvents = events.filter { dirtyEventIDs.contains($0.id.uuidString) }
        let deletedIDs = deletedEventIDs
        do {
            _ = try await co.push(events: dirtyEvents, deletedIDs: deletedIDs)
            // 推送成功后清空已推送的 ID
            dirtyEventIDs.removeAll()
            deletedEventIDs.removeAll()
        } catch {
            // 推送失败：保留 dirty 标记，下次重试
            AppLogger.sync.warning("推送云端失败: \(error)，将在下次同步时重试")
        }
    }

    /// 同步协调器可调用：获取当前脏事件（用于 syncBidirectional 等主动同步场景）
    /// NOTE：重复声明会与上方 P6 优化版冲突；保留空壳以免外部链接符号变化。此处移除旧实现，
    /// 统一以文件顶部"O(1) 字典路径"版本为准。

    /// 清空脏标记（推送成功后由协调器调用）
    public func clearDirtyFlags() {
        dirtyEventIDs.removeAll()
        deletedEventIDs.removeAll()
    }


    // MARK: - 查询（带缓存）

    public func events(on date: Date) -> [CalendarEvent] {
        let cal = Calendar(identifier: .gregorian)
        let key = cal.startOfDay(for: date)
        if let cached = eventCache[key] { return cached }
        let result = events
            .filter { $0.occurs(on: date) }
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
                return lhs.priority > rhs.priority
            }
        eventCache[key] = result
        return result
    }

    public func hasEvents(on date: Date) -> Bool {
        eventStats(on: date).count > 0
    }

    /// 单次遍历同时返回事件数量和最高优先级，避免 calendarGrid 里调两次
    public func eventStats(on date: Date) -> (count: Int, priority: Priority?) {
        let cal = Calendar(identifier: .gregorian)
        let key = cal.startOfDay(for: date)
        if let cached = statsCache[key] { return cached }
        var count = 0
        var best: Priority? = nil
        for ev in events {
            if ev.occurs(on: date) {
                count += 1
                switch (best, ev.priority) {
                case (nil, let p):          best = p
                case (.some(let cur), let p) where p > cur: best = p
                default: break
                }
            }
        }
        let result = (count, best)
        statsCache[key] = result
        return result
    }

    public func highestPriority(on date: Date) -> Priority? {
        eventStats(on: date).priority
    }

    public func search(query: String) -> [CalendarEvent] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return events }
        return events.filter {
            $0.title.lowercased().contains(q) ||
            ($0.location?.lowercased().contains(q) ?? false) ||
            ($0.notes?.lowercased().contains(q) ?? false)
        }
    }

    // MARK: - 导入合并 & 清空

    /// 把一批导入事件合并进本地存储，按 id 去重 + 冲突策略处理；返回合并统计。
    /// 用于 .ics 导入 / .json 备份恢复。调用方再决定是否弹出"有冲突"提示。
    ///
    /// P6 优化：
    /// - 冲突检测：旧 `firstIndex(where:)` 对 M 条事件是 O(N·M)；新实现走 idToIndex 字典 O(M)。
    /// - 新增事件：逐条二分插入（lastInsertHint 让递增序列近 O(1)），不变式全程保持。
    /// - 更新事件：startDate 变化时"先删旧位置+再插新位置"，取代 merge 末尾整体 sort()。
    @discardableResult
    public func merge(
        _ incoming: [CalendarEvent],
        policy: ImportConflictPolicy = .keepLatest,
        skipSync: Bool = false
    ) -> ImportMergeResult {
        var result = ImportMergeResult()
        var pushedP: [CalendarEvent] = []

        for ev in incoming {
            // 基本数据校验：标题非空 + end>start
            if ev.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || ev.endDate <= ev.startDate {
                result.invalid += 1
                continue
            }
            if let idx = indexOfEvent(id: ev.id) {
                let existing = events[idx]
                // 冲突：按 policy
                var shouldApply = false
                switch policy {
                case .overwrite:
                    shouldApply = true
                    result.updated += 1
                case .keepLocal:
                    result.skipped += 1
                case .keepLatest:
                    if ev.updatedAt >= existing.updatedAt {
                        shouldApply = true
                        result.updated += 1
                    } else {
                        result.skipped += 1
                    }
                }
                if shouldApply {
                    updateInPlaceFast(oldIndex: idx, with: ev)
                    pushedP.append(ev)
                }
            } else {
                // 新事件：二分插入
                let at = sortedInsertionIndex(for: ev.startDate)
                events.insert(ev, at: at)
                shiftIndices(from: at, by: 1)
                idToIndex[ev.id] = at
                pushedP.append(ev)
                result.added += 1
            }
        }

        // P6：不变式在 insert/update 内已保持；不需要额外 sort()
        invalidateCache()
        saveNow()
        for ev in pushedP {
            dirtyEventIDs.insert(ev.id.uuidString)
        }
        if !skipSync {
            enqueuePush()
        }
        return result
    }

    /// 清空全部事件（二次确认后的执行步骤）。返回被清空的数量（用于 UI 展示）。
    @discardableResult
    public func clearAll(skipSync: Bool = false) -> Int {
        let removedCount = events.count
        // 通知管理：逐个取消
        #if canImport(UserNotifications)
        for ev in events {
            NotificationManager.shared.cancelNotification(for: ev)
        }
        #endif
        // 同步：若有协调器，把被删的 id 批量打墓碑推送
        if !events.isEmpty {
            deletedEventIDs.formUnion(Set(events.map { $0.id.uuidString }))
            if !skipSync {
                enqueuePush()
            }
        }
        events.removeAll(keepingCapacity: true)
        idToIndex.removeAll(keepingCapacity: true)
        clearLastInsertHint()
        invalidateCache()
        saveNow()
        return removedCount
    }

    // MARK: - 内部辅助

    /// 合并内路径：直接给定 oldIndex，根据 startDate 是否变化决定原地写 or 删+二分插。
    private func updateInPlaceFast(oldIndex idx: Int, with new: CalendarEvent) {
        var applied = new
        applied.updatedAt = Date()
        let oldStart = events[idx].startDate
        if oldStart == applied.startDate {
            events[idx] = applied
            // 位置不变，idToIndex 无需变动（映射仍指向同一个 idx）
        } else {
            let oldID = applied.id
            events.remove(at: idx)
            idToIndex.removeValue(forKey: oldID)
            shiftIndices(from: idx, by: -1)
            let at = sortedInsertionIndex(for: applied.startDate)
            events.insert(applied, at: at)
            shiftIndices(from: at, by: 1)
            idToIndex[oldID] = at
        }
    }

    // MARK: - 持久化

    private func sort() {
        // P6：sort() 现在只在 load() 里对"刚反序列化的可能乱序数组"调用；
        // 其他路径一律"二分插入+不变式"维护。调用后必须跟一次 rebuildIDIndex()。
        events.sort { $0.startDate < $1.startDate }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: saveURL.path) else {
            insertSampleData()
            return
        }
        do {
            let data = try Data(contentsOf: saveURL)
            events = try JSONDecoder().decode([CalendarEvent].self, from: data)
            sort()
        } catch {
            // BUG #41 P0 数据丢失修复：损坏文件不被下一次 saveNow() 原子写默默覆盖掉，
            // 而是先复制到 `calendar_events.json.corrupt.<timestamp>` 隔离目录，
            // 用户可自行从该备份/备份/云端恢复，或使用 Finder/iMazing 提取。
            let backup = quarantineCorruptedURL(original: saveURL)
            do {
                try FileManager.default.copyItem(at: saveURL, to: backup)
                AppLogger.app.error("本地数据损坏 (\(error))，用户原文件已隔离备份至：\(backup.path)")
            } catch {
                AppLogger.app.error("本地数据损坏 (\(error))，且隔离备份失败 (\(backup.path): \(error))，请尽快断电别写盘！")
            }
            events = []
        }
        rebuildIDIndex()
        clearLastInsertHint()
        invalidateCache()
    }

    /// 把损坏/异常文件重命名为 `corrupt.<epochMs>` 同目录副本，避免与下次正常原子写互踩
    private func quarantineCorruptedURL(original: URL) -> URL {
        let ms = Int64(Date().timeIntervalSince1970 * 1000)
        let fm = FileManager.default
        let dir = original.deletingLastPathComponent()
        let base = original.lastPathComponent
        var candidate = dir.appendingPathComponent("\(base).corrupt.\(ms)")
        var idx: Int64 = 0
        // 极端情况：1ms 内连续损坏两次——追加后缀避免 copyItem 覆盖
        while fm.fileExists(atPath: candidate.path) {
            idx += 1
            candidate = dir.appendingPathComponent("\(base).corrupt.\(ms).\(idx)")
        }
        return candidate
    }

    private func save() {
        // P5 性能：防抖写入。单条 CRUD 连续操作（如批量完成事件）合并为 0.5s 一次磁盘写入。
        pendingSaveWorkItem?.cancel()
        let wi = DispatchWorkItem { [weak self] in
            self?.saveNow()
        }
        pendingSaveWorkItem = wi
        DispatchQueue.main.asyncAfter(deadline: .now() + saveDebounceInterval, execute: wi)
    }

    /// 立即写盘（不防抖），用于 merge/clearAll/load/init 等需要立即落盘的事务性场景
    private func saveNow() {
        pendingSaveWorkItem?.cancel()
        pendingSaveWorkItem = nil
        do {
            let data = try JSONEncoder().encode(events)
            try data.write(to: saveURL, options: .atomic)
            saveDirtyFlags()
            writeWidgetSnapshotIfNeeded()
        } catch {
            AppLogger.app.error("保存事件失败: \(error)")
        }
    }

    // MARK: 测试辅助：立即触发一次防抖落盘（Linux XCTest 下 DispatchQueue.main.asyncAfter 不保证执行）
    /// 强制把挂起的防抖保存立即执行；仅用于单元测试，生产代码请勿直接调用。
    @MainActor
    public func _testFlushSave() {
        saveNow()
    }

    // MARK: - Dirty/Deleted 标记持久化（P4）

    /// 启动时从 Documents 恢复 dirty/deleted id；文件不存在/损坏 = 空集合（保守策略：不丢失推送）
    private func loadDirtyFlags() {
        let decoder = JSONDecoder()
        func readSet(_ url: URL) -> Set<String> {
            guard FileManager.default.fileExists(atPath: url.path) else { return [] }
            do {
                let data = try Data(contentsOf: url)
                let arr = try decoder.decode([String].self, from: data)
                return Set(arr)
            } catch {
                AppLogger.app.warning("\(url.lastPathComponent) 读取失败（\(error)），当作空集合。")
                return []
            }
        }
        dirtyEventIDs = readSet(dirtyIDsURL)
        deletedEventIDs = readSet(deletedIDsURL)
        // 关键：清除"悬空"脏标记——events 数组里已经不存在的 id 就不要保留 dirty/deleted，
        // 否则单元测试 setUp 里插入样例→手动 skipSync 删除后，会把这些已删的墓碑当"未推送变更"同步出去。
        cleanupDanglingDirtyIDs()
    }

    /// 若 dirtyEventIDs 中某 id 在 events 里不存在，且不在 deletedEventIDs 里，则清除（悬空标记）。
    private func cleanupDanglingDirtyIDs() {
        let aliveIDs = Set(events.map { $0.id.uuidString })
        // 1) dirty 但既不是 alive 也没记 deleted？→ 清理
        dirtyEventIDs.formIntersection(aliveIDs.union(deletedEventIDs))
        // 2) deleted 里如果 id 又神奇出现在 events 里？→ 取消 deleted（用户手动恢复了？）
        deletedEventIDs.subtract(aliveIDs)
    }

    /// 每次 save() 成功后一并写入 dirty/deleted id（.atomic 原子写）
    private func saveDirtyFlags() {
        let encoder = JSONEncoder()
        func writeSet(_ set: Set<String>, to url: URL) {
            do {
                let data = try encoder.encode(Array(set).sorted())  // 排序 + 数组编码体积更小
                try data.write(to: url, options: .atomic)
            } catch {
                AppLogger.app.error("写入 \(url.lastPathComponent) 失败：\(error)")
            }
        }
        writeSet(dirtyEventIDs, to: dirtyIDsURL)
        writeSet(deletedEventIDs, to: deletedIDsURL)
    }

    /// 仅在 save 成功后触发：把今日统计写成小组件快照
    private func writeWidgetSnapshotIfNeeded() {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())
        let todays = events.filter { $0.occurs(on: today) }
        let completed = todays.filter(\.isCompleted).count
        let top = todays
            .sorted { (l, r) -> Bool in
                if l.priority != r.priority { return l.priority > r.priority }
                return l.startDate < r.startDate
            }
            .prefix(5)
            .map { ev in
                WidgetTodoTitle(
                    id: ev.id.uuidString,
                    title: ev.title,
                    isCompleted: ev.isCompleted,
                    priorityHex: ev.priority.widgetHex
                )
            }
        let snap = WidgetSharedSnapshot(
            updatedAt: Date(),
            targetDay: today,
            todaysEventsCount: todays.count,
            todaysCompletedCount: completed,
            topTitles: top
        )
        _ = WidgetSnapshotStore.write(snap, appGroupID: widgetAppGroupID)
    }

    private func insertSampleData() {
        let today = Date()
        // 一律用公历：避免用户将佛历/伊斯兰历设为系统日历时，示例数据月份分量错位。
        let cal = Calendar(identifier: .gregorian)

        var compsTodayAllDay = cal.dateComponents([.year,.month,.day], from: today)
        compsTodayAllDay.hour = 0
        compsTodayAllDay.minute = 0
        let todayAllDayDate = cal.date(from: compsTodayAllDay) ?? today
        var built: [CalendarEvent] = []
        built.append(
            CalendarEvent(
                title: "阅读《平凡的世界》30分钟",
                type: .note,
                startDate: todayAllDayDate,
                isAllDay: true,
                notes: "今日必读，保持学习节奏",
                priority: .normal
            )
        )

        var comps1 = cal.dateComponents([.year,.month,.day], from: today)
        comps1.hour = 15; comps1.minute = 0
        let s1 = cal.date(from: comps1) ?? today
        var comps1e = comps1; comps1e.hour = 16; comps1e.minute = 30
        let e1 = cal.date(from: comps1e) ?? s1.addingTimeInterval(3600)
        built.append(
            CalendarEvent(
                title: "产品需求评审会",
                type: .schedule,
                startDate: s1,
                endDate: e1,
                location: "3号会议室",
                notes: "讨论Q4产品计划，提前准备方案",
                priority: .high
            )
        )

        // 公历 +1 天，避免 Calendar.current 被用户非公历设置污染
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today) ?? today
        var comps2 = cal.dateComponents([.year,.month,.day], from: tomorrow)
        comps2.hour = 9; comps2.minute = 0
        let s2 = cal.date(from: comps2) ?? tomorrow
        built.append(
            CalendarEvent(
                title: "给妈妈打电话",
                type: .reminder,
                startDate: s2,
                notes: "问候身体情况",
                priority: .urgent
            )
        )

        var comps3 = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        comps3.weekday = 4
        comps3.hour = 20; comps3.minute = 0
        let s3 = cal.date(from: comps3) ?? today
        built.append(
            CalendarEvent(
                title: "瑜伽课",
                type: .schedule,
                startDate: s3,
                endDate: s3.addingTimeInterval(3600),
                location: "阳光健身工作室",
                repeatRule: .weekly,
                priority: .low
            )
        )

        // P6：批量构造完成后只排序一次，然后重建 ID 索引；不经过单条 add() 的事件级防抖/推送。
        built.sort { $0.startDate < $1.startDate }
        events = built
        rebuildIDIndex()
        clearLastInsertHint()
        invalidateCache()
        saveNow()
    }
}
