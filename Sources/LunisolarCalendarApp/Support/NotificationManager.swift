import Foundation
import LunarCore
// N1 修复：Apple 平台下 AppLogger.app.error/warning/debug 最终落到 os.Logger。
// OSLogMessage(_:) 的字符串插值由 module `os` 提供 OSLogInterpolation / appendLiteral /
// appendInterpolation(_:privacy:attributes:)；缺 import 会级联报 6 条 "defining module 'os'"
// 错误（见 DataPortability.swift BUG-DP2 同类修复）。
#if canImport(os)
import os
#endif

#if canImport(UserNotifications)
import UserNotifications
#endif

// MARK: - 本地通知管理器

/// 管理 UNUserNotificationCenter 本地通知：申请权限、调度提醒、防重复
@MainActor
public final class NotificationManager {

    @MainActor public static let shared = NotificationManager()

    private init() {}

    private let gregorian = Calendar(identifier: .gregorian)

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

    /// 异步获取授权状态（不阻塞主线程）
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

    /// 为事件调度本地通知
    ///
    /// 分支策略：
    /// - `.never`：UNTimeIntervalNotificationTrigger，成功后 markNotified 防重复
    /// - `.daily/.weekly/.monthly/.yearly`：UNCalendarNotificationTrigger(.gregorian, repeats: true)，不 markNotified
    /// - `.workday`：拆 5 个 weekday trigger（Mon-Fri = 2,3,4,5,6），不 markNotified
    /// - `.lunarAnnually`：计算"未来第一个匹配农历月/日的公历日期"，排一次 timeInterval trigger；
    ///   由 rescheduleAllReminders 每年续排。iOS 原生不支持农历 trigger。
    ///
    /// ⚠️ 所有 Calendar 类 trigger 统一用 .gregorian：避免用户系统是伊斯兰历/佛历/和历
    ///    时 UNCalendarNotificationTrigger 的 month/day 分量语义错乱（参考 BUG #30/#32）。
    public func scheduleNotification(for event: CalendarEvent) async {
        #if canImport(UserNotifications)
        guard event.type == .reminder, event.startDate > Date() else { return }

        let rule = event.repeatRule
        // 单次提醒已经触发过就跳过（防重复弹窗）
        if rule == .never && event.isNotified { return }

        let center = UNUserNotificationCenter.current()
        let content = buildContent(for: event)

        let identifiers = buildNotificationRequests(for: event, content: content)
        guard !identifiers.isEmpty else { return }

        // 先移除旧的同事件通知（防止用户改时间后旧通知还挂着）
        center.removePendingNotificationRequests(withIdentifiers: identifiers.map(\.identifier))

        do {
            for req in identifiers {
                try await center.add(req)
            }
            if rule == .never {
                // 单次提醒：标记已通知，下次 reschedule 时会跳过
                EventStore.shared.markNotified(event)
            }
            // 有重复规则的事件永远不 markNotified —— 它们依赖 UNCalendarNotificationTrigger
            // 的内置 repeats 或每次 rescheduleAllReminders 来续上
        } catch {
            AppLogger.app.error("调度通知失败: \(error)")
        }
        #endif
    }

    /// 取消某个事件的通知
    public func cancelNotification(for event: CalendarEvent) {
        #if canImport(UserNotifications)
        let ids = notificationIdentifiers(for: event)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
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
        // 注意：.never && isNotified 的事件不应该再被调度
        for event in store.events
            where event.type == .reminder && !event.isCompleted {
            if event.repeatRule == .never && event.isNotified { continue }
            await scheduleNotification(for: event)
        }
        #endif
    }

    // MARK: - 私有辅助

    #if canImport(UserNotifications)
    private func buildContent(for event: CalendarEvent) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = event.title
        if let notes = event.notes, !notes.isEmpty {
            content.body = notes
        }
        content.sound = .default
        content.userInfo = ["eventID": event.id.uuidString]
        return content
    }

    private func buildNotificationRequests(
        for event: CalendarEvent,
        content: UNMutableNotificationContent
    ) -> [UNNotificationRequest] {
        let baseID = event.id.uuidString
        let rule = event.repeatRule

        // reminderOffsetMinutes = 提前 N 分钟；nil/0 = 准时
        let effectiveStart: Date = {
            if let offset = event.reminderOffsetMinutes, offset > 0 {
                return event.startDate.addingTimeInterval(-TimeInterval(offset) * 60)
            }
            return event.startDate
        }()

        // 统一取 .gregorian 下的 hour/minute，避免 Calendar.current 跟随系统本地化日历
        let timeComps = gregorian.dateComponents([.hour, .minute], from: effectiveStart)

        switch rule {
        case .never:
            let interval = effectiveStart.timeIntervalSinceNow
            guard interval > 0 else { return [] }
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            return [UNNotificationRequest(identifier: baseID, content: content, trigger: trigger)]

        case .daily:
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: timeComps, repeats: true
            )
            return [UNNotificationRequest(identifier: baseID, content: content, trigger: trigger)]

        case .weekly:
            let comps = gregorian.dateComponents([.weekday, .hour, .minute], from: effectiveStart)
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: comps, repeats: true
            )
            return [UNNotificationRequest(identifier: baseID, content: content, trigger: trigger)]

        case .monthly:
            let comps = gregorian.dateComponents([.day, .hour, .minute], from: effectiveStart)
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: comps, repeats: true
            )
            return [UNNotificationRequest(identifier: baseID, content: content, trigger: trigger)]

        case .yearly:
            // month/day 取原始 startDate（提醒偏移只应改时分，不改日期）
            let dateComps = gregorian.dateComponents([.month, .day], from: event.startDate)
            var comps = gregorian.dateComponents([.hour, .minute], from: effectiveStart)
            comps.month = dateComps.month
            comps.day = dateComps.day
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: comps, repeats: true
            )
            return [UNNotificationRequest(identifier: baseID, content: content, trigger: trigger)]

        case .workday:
            // 周一到周五 = weekday 2,3,4,5,6（周日=1）
            // timeComps 已从 effectiveStart 取，只改 weekday
            let workdays: Set<Int> = [2, 3, 4, 5, 6]
            var requests: [UNNotificationRequest] = []
            for weekday in workdays {
                var comps = timeComps
                comps.weekday = weekday
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                // 每个 weekday 用不同 identifier，否则后面的会覆盖前面的
                let id = "\(baseID)-wd-\(weekday)"
                requests.append(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            }
            return requests

        case .lunarAnnually:
            // iOS 原生不支持农历 trigger。
            // 策略：计算"未来第一个匹配 startDate 农历月/日的公历日期"，用 effectiveStart 的时分
            // 排一次 timeInterval trigger。下一年由 rescheduleAllReminders 续上。
            guard let nextSolar = nextSolarDateForLunarAnnually(
                lunarSource: event.startDate,
                timeSource: effectiveStart
            ) else { return [] }
            let interval = nextSolar.timeIntervalSinceNow
            guard interval > 0 else { return [] }
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            let id = "\(baseID)-lunar"
            return [UNNotificationRequest(identifier: id, content: content, trigger: trigger)]
        }
    }

    /// 为某个事件生成所有可能的通知 identifier（用于 cancelAll / cancelNotification）
    private func notificationIdentifiers(for event: CalendarEvent) -> [String] {
        let base = event.id.uuidString
        switch event.repeatRule {
        case .workday:
            return (2...6).map { "\(base)-wd-\($0)" }
        case .lunarAnnually:
            return [base, "\(base)-lunar"]
        default:
            return [base]
        }
    }

    /// 计算未来第一个与 lunarSource 的农历月/日相同的公历日期，保留 timeSource 的时分秒
    private func nextSolarDateForLunarAnnually(
        lunarSource: Date,
        timeSource: Date
    ) -> Date? {
        guard let lunar = ChineseCalendar.lunarDateSafe(from: lunarSource) else { return nil }

        let refComponents = gregorian.dateComponents(
            [.hour, .minute, .second], from: timeSource
        )

        let now = Date()
        // 从 refDate 所在农历年份往后搜最多 16 年（覆盖 minYear..maxYear=2100）
        let upperBound = min(ChineseCalendar.maxYear, lunar.year + 16)
        for year in lunar.year...upperBound {
            guard let solar = ChineseCalendar.solarDate(
                fromLunar: year, month: lunar.month,
                day: lunar.day, isLeap: lunar.isLeapMonth
            ) else { continue }

            if let finalDate = gregorian.date(
                bySettingHour: refComponents.hour ?? 0,
                minute: refComponents.minute ?? 0,
                second: refComponents.second ?? 0,
                of: gregorian.startOfDay(for: solar)
            ), finalDate > now {
                return finalDate
            }
        }
        return nil
    }
    #endif
}

// MARK: - 授权状态枚举

public enum NotificationAuthStatus {
    case notDetermined
    case granted
    case denied
    case unavailable  // Linux/非Apple平台
}
