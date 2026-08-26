import Foundation

#if canImport(UserNotifications)
import UserNotifications
#endif

// MARK: - 本地通知管理器

/// 管理 UNUserNotificationCenter 本地通知：申请权限、调度提醒、防重复
@MainActor
public final class NotificationManager {

    @MainActor public static let shared = NotificationManager()

    private init() {}

    // MARK: - 权限

    /// 申请通知权限（首次添加提醒时调用）
    public func requestAuthorization() async -> Bool {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        return granted
        #else
        return false
        #endif
    }

    /// ⚠️ 已废弃：请改用 `authorizationStatusAsync()`（不阻塞主线程）。
    /// 旧实现内部用 DispatchSemaphore 同步等待 2 秒，在主线程调用会真实卡顿 Settings 页面 push。
    @available(*, deprecated, message: "Use async authorizationStatusAsync() instead to avoid blocking main thread")
    public var authorizationStatus: NotificationAuthStatus {
        #if canImport(UserNotifications)
        let semaphore = DispatchSemaphore(value: 0)
        var status: UNAuthorizationStatus = .notDetermined
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            status = settings.authorizationStatus
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2)
        switch status {
        case .authorized, .provisional: return .granted
        case .denied: return .denied
        case .ephemeral: return .granted
        default: return .notDetermined
        }
        #else
        return .unavailable
        #endif
    }

    /// 异步获取授权状态（推荐在 View task 中使用，不阻塞主线程）
    public func authorizationStatusAsync() async -> NotificationAuthStatus {
        #if canImport(UserNotifications)
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional: return .granted
        case .denied: return .denied
        case .ephemeral: return .granted
        default: return .notDetermined
        }
        #else
        return .unavailable
        #endif
    }

    // MARK: - 调度通知

    /// 为提醒事件调度本地通知
    public func scheduleNotification(for event: CalendarEvent) async {
        #if canImport(UserNotifications)
        // 只处理 reminder 类型，且尚未通知过的，且日期在未来
        guard event.type == .reminder, !event.isNotified, event.startDate > Date() else { return }

        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = event.title
        if let notes = event.notes, !notes.isEmpty {
            content.body = notes
        }
        content.sound = .default
        content.userInfo = ["eventID": event.id.uuidString]

        // 提前 0 分钟触发（到达 startDate 时）
        let triggerDate = event.startDate
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: event.id.uuidString, content: content, trigger: trigger)

        do {
            try await center.add(request)
            EventStore.shared.markNotified(event)
        } catch {
            print("调度通知失败: \(error)")
        }
        #endif
    }

    /// 取消某个事件的通知
    public func cancelNotification(for event: CalendarEvent) {
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [event.id.uuidString]
        )
        #endif
    }

    /// 取消所有通知
    public func cancelAll() {
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        #endif
    }

    /// 重新调度所有未完成的提醒
    public func rescheduleAllReminders(in store: EventStore) async {
        #if canImport(UserNotifications)
        cancelAll()
        for event in store.events where event.type == .reminder && !event.isCompleted && event.startDate > Date() {
            await scheduleNotification(for: event)
        }
        #endif
    }
}

// MARK: - 授权状态枚举

public enum NotificationAuthStatus {
    case notDetermined
    case granted
    case denied
    case unavailable  // Linux/非Apple平台
}
