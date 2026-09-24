import Foundation
import Observation

// MARK: - EventService 业务边界

/// 文档 #9 / #37：UI → EventService → EventStore。
///
/// EventService 是 SwiftUI View 与数据 / 系统服务之间的唯一业务入口，协调：
/// - EventStore：数据存取、落盘、iCloud 同步入队（内部已协调 Widget 刷新）
/// - NotificationManager：提醒调度（schedule / cancel / reschedule）
///
/// 约束（文档 #9）：View 不应直接操作 UNUserNotificationCenter / WidgetKit /
/// ActivityKit；数据写操作与通知调度统一走本类业务方法。
@MainActor
@Observable
public final class EventService {
    public static let shared = EventService()

    /// 数据层（只读数据源；写操作走本类业务方法）
    public let store: EventStore

    /// 默认注入 App 单例；测试传入隔离 store，避免写入真实 Documents
    /// （既有测试统一用 makeIsolatedEventStore() 的临时目录模式）
    public init(store: EventStore = .shared) {
        self.store = store
    }

    // MARK: - 事件写操作（数据 + 通知 + Widget 协调）

    /// 新增或更新事件，并刷新该事件的通知。
    /// EventStore.add/update 内部已处理落盘、dirty 标记、同步入队、Widget 刷新；
    /// 此处补齐"挂载 / 更新提醒"（add 不自动调度通知）。
    public func saveEvent(_ event: CalendarEvent) {
        if store.eventBy(idString: event.id.uuidString) != nil {
            store.update(event)
        } else {
            store.add(event)
        }
        refreshNotification(for: event)
    }

    /// 删除事件（EventStore 内部取消提醒 + 刷新 Widget）。
    public func deleteEvent(_ event: CalendarEvent) {
        store.delete(event)
    }

    /// 完成 / 取消完成事件。
    public func toggleCompleted(_ event: CalendarEvent) {
        store.toggleCompleted(event)
    }

    /// 只刷新单个事件的通知（避免全量重排导致的 badge 闪烁 / 卡顿）。
    public func refreshNotification(for event: CalendarEvent) {
        #if canImport(UserNotifications)
        NotificationManager.shared.cancelNotification(for: event)
        Task { await NotificationManager.shared.scheduleNotification(for: event) }
        #endif
    }

    // MARK: - 统一 CRUD 入口

    /// 新增/更新事件的完整业务操作。UI 不应直接调用 EventStore.add/update。
    public func upsertEvent(_ event: CalendarEvent, flush: Bool = false) {
        saveEvent(event)
        if flush { store.flushPendingSave() }
    }

    /// 删除事件，并同步清理本地通知。
    public func removeEvent(_ event: CalendarEvent, flush: Bool = false) {
        deleteEvent(event)
        if flush { store.flushPendingSave() }
    }

    /// 切换完成状态，并同步通知生命周期。
    public func setCompleted(_ event: CalendarEvent, flush: Bool = false) {
        toggleCompleted(event)
        if flush { store.flushPendingSave() }
    }

    /// 把 EventStore 防抖中的待写变更立即落盘。
    /// 使用时机：保存后立即退出编辑页等"写后可能立刻进后台"的场景；
    /// App 进入后台的统一落盘由 AppLifecycleCoordinator 负责。
    public func flushPendingSave() {
        store.flushPendingSave()
    }

    // MARK: - 批量导入 / 危险操作（P0：收口 SettingsView 直连 store）

    /// 批量合并导入事件（ICS / JSON / 系统日历 / 联系人导入的统一数据入口）。
    /// 返回合并统计；调用方在 added+updated>0 后负责 rescheduleAllReminders()。
    @discardableResult
    public func mergeImportedEvents(
        _ incoming: [CalendarEvent],
        policy: ImportConflictPolicy,
        skipSync: Bool = true
    ) -> ImportMergeResult {
        store.merge(incoming, policy: policy, skipSync: skipSync)
    }

    /// 清空全部事件（设置页危险操作，二次确认后执行）。返回删除条数。
    @discardableResult
    public func clearAllEvents() -> Int {
        store.clearAll()
    }

    // MARK: - 倒数日业务（P0：收口 CountdownView 直连 CountdownStore）

    /// 倒数日数据源（写操作走本类业务方法，保持 UI → Service → Store 单向依赖）。
    private let countdownStore = CountdownStore.shared

    /// 新增或更新倒数日（按 id 是否已存在决定 add/update）。
    /// flush=true：编辑页保存后立即 dismiss，很可能马上进后台；0.5s 防抖的
    /// Task.sleep 在后台不一定跑完，直接落盘防丢数据（沿用 CountdownEditor 原 P2 修复语义）。
    public func saveCountdown(_ event: CountdownEvent, flush: Bool = false) {
        if countdownStore.events.contains(where: { $0.id == event.id }) {
            countdownStore.update(event)
        } else {
            countdownStore.add(event)
        }
        if flush { countdownStore.flushPendingSave() }
    }

    /// 删除倒数日（滑动删除）。删除后的灵动岛活动由 CountdownStore 内部统一结束；
    /// 落盘由 store 防抖 + AppLifecycleCoordinator 后台 flush 兜底。
    public func deleteCountdown(id: UUID, flush: Bool = false) {
        countdownStore.delete(id: id)
        if flush { countdownStore.flushPendingSave() }
    }

    // MARK: - 通知调度统一入口（文档 #37）

    /// 全量重排所有提醒（导入 / iCloud 同步 / 权限变更后调用）。
    public func rescheduleAllReminders() {
        Task { @MainActor in
            await NotificationManager.shared.rescheduleAllReminders(in: store)
        }
    }

    /// 通知授权状态（notDetermined / granted / denied / unavailable）。
    public func notificationAuthorizationStatus() async -> NotificationAuthStatus {
        await NotificationManager.shared.authorizationStatusAsync()
    }

    /// 请求通知授权。
    public func requestNotificationAuthorization() async -> Bool {
        await NotificationManager.shared.requestAuthorization()
    }

    // MARK: - 清和时间胶囊（文档 #20/#25）

    /// 从当前事件中选出最值得进入时间胶囊（灵动岛 / 锁屏）的一个。
    /// 映射规则（对齐文档 #20 优先级表）：
    /// - 记事（note）：不上岛；
    /// - 普通日程（schedule）：不上岛；
    /// - 提醒（reminder）：按事件优先级映射 urgent / important / normal；
    /// - 高优先级日程：按 important 处理。
    public func timeCapsuleCandidate(now: Date = Date()) -> QingheTimeCapsuleCandidate? {
        var all = Self.timeCapsuleCandidates(from: store.events)
        // 文档 #29：节气短生命周期候选（24h 内交节才加入）
        if let term = QingheActivityCoordinator.nextSolarTermCandidate(now: now) {
            all.append(term)
        }
        return QingheActivityCoordinator.pickForIsland(from: all, now: now)
    }

    /// 事件 → 时间胶囊候选（纯函数，可测试）。
    /// 映射规则（对齐文档 #20 优先级表）：
    /// - 记事（note）：不上岛；
    /// - 普通日程（schedule）：不上岛；
    /// - 提醒（reminder）：按事件优先级映射 urgent / important / normal；
    /// - 高优先级日程：按 important 处理。
    nonisolated public static func timeCapsuleCandidates(from events: [CalendarEvent]) -> [QingheTimeCapsuleCandidate] {
        events.compactMap { ev -> QingheTimeCapsuleCandidate? in
            guard !ev.isCompleted else { return nil }
            let type: QingheActivityType
            let priority: QingheActivityPriority
            switch ev.type {
            case .note:
                return nil
            case .reminder:
                type = .reminder
                priority = mapPriority(ev.priority)
            case .schedule:
                // 仅高优先级日程参与
                guard ev.priority >= .high else { return nil }
                type = .event
                priority = .important
            }
            return QingheTimeCapsuleCandidate(
                eventID: ev.id,
                type: type,
                priority: priority,
                startDate: ev.startDate,
                endDate: ev.isAllDay ? nil : ev.endDate,
                isAllDay: ev.isAllDay
            )
        }
    }

    /// CalendarEvent.Priority → QingheActivityPriority
    nonisolated private static func mapPriority(_ p: Priority) -> QingheActivityPriority {
        switch p {
        case .urgent: return .urgent
        case .high:   return .important
        case .normal, .low: return .normal
        }
    }
}
