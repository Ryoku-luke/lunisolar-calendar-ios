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
    public let store = EventStore.shared

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
}
