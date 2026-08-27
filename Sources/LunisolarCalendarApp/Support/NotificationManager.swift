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

    public func requestAuthorization() async -> Bool {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        return granted
        #else
        return false
        #endif
    }

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

    public func scheduleNotification(for event: CalendarEvent) async {
        #if canImport(UserNotifications)
        guard event.type == .reminder, !event.isNotified, event.startDate > Date() else { return }

        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = event.title
        if let notes = event.notes, !notes.isEmpty {
            content.body = notes
        }
        content.sound = .default
        content.userInfo = ["eventID": event.id.uuidString]

        let interval = event.startDate.timeIntervalSinceNow
        guard interval > 0 else { return }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: event.id.uuidString, content: content, trigger: trigger)

        do {
            try await center.add(request)
            EventStore.shared.markNotified(event)
        } catch {
            print("调度通知失败: \(error)")
        }
        #endif
    }

    public func cancelNotification(for event: CalendarEvent) {
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [event.id.uuidString]
        )
        #endif
    }

    public func cancelAll() {
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        #endif
    }

    public func rescheduleAllReminders(in store: EventStore) async {
        #if canImport(UserNotifications)
        cancelAll()
        for event in store.events where event.type == .reminder && !event.isCompleted && event.startDate > Date() {
            await scheduleNotification(for: event)
        }
        #endif
    }
}

public enum NotificationAuthStatus {
    case notDetermined
    case granted
    case denied
    case unavailable
}
