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

    private let saveURL: URL

    /// 可选 App Group ID：配了之后 EventStore.save() 会顺手写入 Widget 共享快照
    /// （App Group 未配置时也不会崩，仅回退 Documents 路径，Widget 那边按"过期→占位"处理）
    public var widgetAppGroupID: String?

    /// iCloud 同步协调器（可选）。设置后：默认 CRUD 自动 fire-and-forget 推送云端
    public weak var syncCoordinator: EventSyncCoordinator?

    public init() {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        var docs = paths.first
        if docs == nil || !FileManager.default.fileExists(atPath: docs!.path) {
            // Linux/沙箱环境下回退到 /tmp
            docs = URL(fileURLWithPath: NSTemporaryDirectory())
        }
        self.saveURL = docs!.appendingPathComponent("calendar_events.json")
        // 确保父目录存在（iOS 上 Documents 目录首次启动可能需要创建中间路径）
        try? FileManager.default.createDirectory(
            at: self.saveURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        load()
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
        if !skipSync { autoPush([event], deletedID: nil) }
    }

    /// 更新事件
    public func update(_ event: CalendarEvent, skipSync: Bool = false) {
        guard let idx = events.firstIndex(where: { $0.id == event.id }) else { return }
        var updated = event
        updated.updatedAt = Date()
        events[idx] = updated
        sort()
        save()
        if !skipSync { autoPush([updated], deletedID: nil) }
    }

    /// 删除事件
    public func delete(_ event: CalendarEvent, skipSync: Bool = false) {
        events.removeAll { $0.id == event.id }
        save()
        if !skipSync { autoPush([], deletedID: event.id.uuidString) }
    }

    public func toggleCompleted(_ event: CalendarEvent, skipSync: Bool = false) {
        guard let idx = events.firstIndex(where: { $0.id == event.id }) else { return }
        events[idx].isCompleted.toggle()
        events[idx].updatedAt = Date()
        save()
        if !skipSync { autoPush([events[idx]], deletedID: nil) }
    }

    /// 标记事件通知已触发（防止重复弹窗）
    public func markNotified(_ event: CalendarEvent, skipSync: Bool = true) {
        guard let idx = events.firstIndex(where: { $0.id == event.id }) else { return }
        events[idx].isNotified = true
        events[idx].updatedAt = Date()
        save()
        // markNotified 是内部状态，默认不同步（保持 isNotified 本地语义）
        if !skipSync { autoPush([events[idx]], deletedID: nil) }
    }

    // MARK: - 同步辅助

    /// fire-and-forget 推送到 syncCoordinator（若已设置）
    private func autoPush(_ events: [CalendarEvent], deletedID: String?) {
        guard let co = syncCoordinator else { return }
        var del: Set<String> = []
        if let id = deletedID { del.insert(id) }
        Task { @MainActor in
            _ = try? await co.push(events: events, deletedIDs: del)
        }
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
                if best == nil || ev.priority > best! {
                    best = ev.priority
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
        if !skipSync, !pushedP.isEmpty {
            autoPush(pushedP, deletedID: nil)
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
        if !skipSync, let co = syncCoordinator, !events.isEmpty {
            let ids = Set(events.map { $0.id.uuidString })
            Task { @MainActor in
                _ = try? await co.push(events: [], deletedIDs: ids)
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
            print("加载事件失败: \(error)")
            insertSampleData()
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(events)
            try data.write(to: saveURL, options: .atomic)
            writeWidgetSnapshotIfNeeded()
        } catch {
            print("保存事件失败: \(error)")
        }
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
