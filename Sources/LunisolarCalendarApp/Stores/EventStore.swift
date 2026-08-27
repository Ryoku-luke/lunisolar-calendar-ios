import Foundation

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

    /// 脏事件 ID 集合（已变更但未推送到云端的事件）
    private var dirtyEventIDs: Set<String> = []
    /// 已删除但未推送到云端的事件 ID
    private var deletedEventIDs: Set<String> = []
    /// 同步推送队列：序列化多个 push 请求，避免并发竞争
    private var pushQueue: [() async -> Void] = []
    private var isPushing = false

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
                print("[EventStore] ✅ App Group 已配置：\(id)")
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
                    print("[EventStore] ⚠️  widgetAppGroupID 未设置——若使用 Widget Extension，"
                        + "请在 App 启动时给 EventStore.shared.widgetAppGroupID 赋值你的 App Group ID。")
                    #endif
                }
            }
        }
        #endif
    }

    // MARK: - CRUD

    /// 添加事件
    /// - Parameters:
    ///   - event: 新事件
    ///   - skipSync: true=不推送到协调器（pull 合并回本地时使用，避免回环）
    public func add(_ event: CalendarEvent, skipSync: Bool = false) {
        events.append(event)
        sort()
        save()
        // skipSync 时仍标记 dirty（供 syncBidirectional 等主动同步使用），只是不立即 enqueue
        dirtyEventIDs.insert(event.id.uuidString)
        if !skipSync {
            enqueuePush()
        }
    }

    /// 更新事件
    public func update(_ event: CalendarEvent, skipSync: Bool = false) {
        guard let idx = events.firstIndex(where: { $0.id == event.id }) else { return }
        var updated = event
        updated.updatedAt = Date()
        events[idx] = updated
        sort()
        save()
        dirtyEventIDs.insert(updated.id.uuidString)
        if !skipSync {
            enqueuePush()
        }
    }

    /// 删除事件
    public func delete(_ event: CalendarEvent, skipSync: Bool = false) {
        events.removeAll { $0.id == event.id }
        save()
        dirtyEventIDs.remove(event.id.uuidString)
        deletedEventIDs.insert(event.id.uuidString)
        if !skipSync {
            enqueuePush()
        }
    }

    public func toggleCompleted(_ event: CalendarEvent, skipSync: Bool = false) {
        guard let idx = events.firstIndex(where: { $0.id == event.id }) else { return }
        events[idx].isCompleted.toggle()
        events[idx].updatedAt = Date()
        save()
        dirtyEventIDs.insert(events[idx].id.uuidString)
        if !skipSync {
            enqueuePush()
        }
    }

    /// 标记事件通知已触发（防止重复弹窗）
    /// 默认 skipSync=true：通知标记是"设备本地状态"，通常不应该推上云端，
    /// 更不该因此把事件打为 dirty，否则下次别的 CRUD 会把事件"捎带"推云（P5 修复）。
    public func markNotified(_ event: CalendarEvent, skipSync: Bool = true) {
        guard let idx = events.firstIndex(where: { $0.id == event.id }) else { return }
        events[idx].isNotified = true
        events[idx].updatedAt = Date()
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
            print("[EventStore] 推送云端失败: \(error)，将在下次同步时重试")
        }
    }

    /// 同步协调器可调用：获取当前脏事件（用于 syncBidirectional 等主动同步场景）
    public func consumeDirtyEvents() -> (events: [CalendarEvent], deletedIDs: Set<String>) {
        let evs = events.filter { dirtyEventIDs.contains($0.id.uuidString) }
        let del = deletedEventIDs
        return (evs, del)
    }

    /// 清空脏标记（推送成功后由协调器调用）
    public func clearDirtyFlags() {
        dirtyEventIDs.removeAll()
        deletedEventIDs.removeAll()
    }


    // MARK: - 查询

    public func events(on date: Date) -> [CalendarEvent] {
        events
            .filter { $0.occurs(on: date) }
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
                return lhs.priority > rhs.priority
            }
    }

    public func hasEvents(on date: Date) -> Bool {
        events.contains { $0.occurs(on: date) }
    }

    /// 单次遍历同时返回是否有事件和最高优先级，避免 calendarGrid 里调两次
    public func eventStats(on date: Date) -> (has: Bool, priority: Priority?) {
        var has = false
        var best: Priority? = nil
        for ev in events {
            if ev.occurs(on: date) {
                has = true
                // BUG #34 修复：用标准可选比较模式替代短路 + best! 强制解包
                switch (best, ev.priority) {
                case (nil, let p):          best = p
                case (.some(let cur), let p) where p > cur: best = p
                default: break
                }
            }
        }
        return (has, best)
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
    @discardableResult
    public func merge(
        _ incoming: [CalendarEvent],
        policy: ImportConflictPolicy = .keepLatest,
        skipSync: Bool = false
    ) -> ImportMergeResult {
        var result = ImportMergeResult()
        var pushedP: [CalendarEvent] = [] // 用于最后批量 push 云端（若未 skipSync 且有 co）

        for ev in incoming {
            // 基本数据校验：标题非空 + end>start
            if ev.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || ev.endDate <= ev.startDate {
                result.invalid += 1
                continue
            }
            if let existing = events.first(where: { $0.id == ev.id }) {
                // 冲突：按 policy
                switch policy {
                case .overwrite:
                    updateInPlace(id: existing.id, with: ev)
                    pushedP.append(ev)
                    result.updated += 1
                case .keepLocal:
                    result.skipped += 1
                case .keepLatest:
                    if ev.updatedAt >= existing.updatedAt {
                        updateInPlace(id: existing.id, with: ev)
                        pushedP.append(ev)
                        result.updated += 1
                    } else {
                        result.skipped += 1
                    }
                }
            } else {
                events.append(ev)
                pushedP.append(ev)
                result.added += 1
            }
        }

        sort()
        save()
        // skipSync 时仍标记 dirty（供后续主动同步使用），只是不立即 enqueue
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
        events.removeAll()
        save()
        return removedCount
    }

    // MARK: - 内部辅助

    /// 更新某个 id 对应的事件；只写内部数组（不 sort/save/push），由调用方统一处理。
    private func updateInPlace(id: UUID, with new: CalendarEvent) {
        guard let idx = events.firstIndex(where: { $0.id == id }) else { return }
        var applied = new
        applied.updatedAt = Date()
        events[idx] = applied
    }

    // MARK: - 持久化

    private func sort() {
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
            // 数据损坏：不覆盖用户数据，保留空数组 + 打印告警
            // 用户之前的文件已损坏无法恢复，但避免 insertSampleData 直接"替换"导致误以为数据还在
            print("[EventStore] 警告：本地数据文件损坏 (\(error))，已清空。请从备份/云端恢复。")
            events = []
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(events)
            try data.write(to: saveURL, options: .atomic)
            // P4 修复：事件保存成功后，把 dirty/deleted 标记也持久化（下次重启可接着推送）
            saveDirtyFlags()
            writeWidgetSnapshotIfNeeded()
        } catch {
            print("保存事件失败: \(error)")
        }
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
                print("[EventStore] 警告：\(url.lastPathComponent) 读取失败（\(error)），当作空集合。")
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
                print("[EventStore] 写入 \(url.lastPathComponent) 失败：\(error)")
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
        let cal = Calendar.current

        var compsTodayAllDay = cal.dateComponents([.year,.month,.day], from: today)
        compsTodayAllDay.hour = 0
        compsTodayAllDay.minute = 0
        let todayAllDayDate = cal.date(from: compsTodayAllDay) ?? today
        events.append(
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
        events.append(
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

        var comps2 = cal.dateComponents([.year,.month,.day], from: today.addingDays(1))
        comps2.hour = 9; comps2.minute = 0
        let s2 = cal.date(from: comps2) ?? today.addingDays(1)
        events.append(
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
        events.append(
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

        sort()
        save()
    }
}
