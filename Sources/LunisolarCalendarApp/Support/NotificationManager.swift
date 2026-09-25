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

    #if canImport(UserNotifications)
    /// 返回当前进程的 UNUserNotificationCenter；无合法 App/App Extension 宿主时返回 nil。
    ///
    /// 背景：macOS 命令行 `swift test` 跑逻辑测试时，mainBundle 落在
    /// `.../Xcode.app/Contents/Developer/usr/bin/`（可执行文件所在的裸目录），
    /// 此时 `UNUserNotificationCenter.current()` 会抛
    /// `NSInternalInconsistencyException: bundleProxyForCurrentProcess is nil` 直接终止进程，
    /// 而 ObjC 异常无法被 Swift 的 do/catch 拦截，必须在调用前做环境判定。
    ///
    /// 判据：UserNotifications 框架要求进程宿主必须是 `.app` 或 `.appex`。
    /// 注意不能只看 bundleIdentifier——命令行进程向上回溯会误命中 Xcode.app 的 Info.plist，
    /// 得到 `com.apple.dt.Xcode`；必须直接校验 bundleURL 的扩展名。
    private var currentCenterIfAvailable: UNUserNotificationCenter? {
        let hostExt = Bundle.main.bundleURL.pathExtension.lowercased()
        guard hostExt == "app" || hostExt == "appex" else {
            AppLogger.app.notice("宿主不是 .app/.appex（\(Bundle.main.bundleURL.lastPathComponent)），跳过 UNUserNotificationCenter 访问（命令行/逻辑测试环境）")
            return nil
        }
        return UNUserNotificationCenter.current()
    }
    #endif

    // MARK: - 权限

    /// 申请通知权限（首次添加提醒时调用）
    public func requestAuthorization() async -> Bool {
        #if canImport(UserNotifications)
        guard let center = currentCenterIfAvailable else { return false }
        let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        return granted
        #else
        return false
        #endif
    }

    /// 异步获取授权状态（不阻塞主线程）
    public func authorizationStatusAsync() async -> NotificationAuthStatus {
        #if canImport(UserNotifications)
        guard let center = currentCenterIfAvailable else { return .unavailable }
        let settings = await center.notificationSettings()
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
    ///
    /// 该事件是否应有本地通知——`scheduleNotification` 与 `rescheduleAllReminders`
    /// 共用同一判定，避免两处口径不一致。
    ///
    /// 背景：此前两处各自按 `type == .reminder` 过滤，而编辑页对「日程」也提供提醒选择，
    /// 于是「界面显示已设提醒、到点永远不响」。现在统一为：
    /// - `.note` 记事：永不通知；
    /// - `reminderOffsetMinutes != nil`：通知，按提前量触发（0 = 准时），**与类型无关**；
    /// - `.reminder` 提醒：类型本身即"要响"，无提前量则准时响；
    /// - `.schedule` 日程：只有显式设了提前量才响（对齐系统日历：日程的提醒是可选的）。
    public static func shouldScheduleNotification(for event: CalendarEvent) -> Bool {
        guard event.type != .note else { return false }
        if event.reminderOffsetMinutes != nil { return true }
        return event.type == .reminder
    }

    public func scheduleNotification(for event: CalendarEvent) async {
        #if canImport(UserNotifications)
        guard Self.shouldScheduleNotification(for: event) else { return }

        let rule = event.repeatRule
        // 单次提醒必须在未来（过去的一次性提醒不可能再响）
        // 重复提醒（每日/每周/工作日/每月/每年/农历每年）允许 startDate 在过去——只要未来还有匹配
        // 日期（UNCalendar repeats 自动负责，农历每年由 nextSolarDateForLunarAnnually 负责）。
        // P1 修复：旧版本 `event.startDate > Date()` 一刀切把所有 startDate 在过去的
        // 重复性提醒（生日、打卡、农历生日这些都是从过去某个日期开始）永久挡在门外，
        // 今天待办里能看到该事件的 occurs=true 但从不响通知，属于典型"看得见不会响"。
        if rule == .never && !(event.startDate > Date()) { return }

        // 单次提醒已经触发过就跳过（防重复弹窗）
        if rule == .never && event.isNotified { return }

        guard let center = currentCenterIfAvailable else { return }
        let content = buildContent(for: event)

        let identifiers = buildNotificationRequests(for: event, content: content)
        guard !identifiers.isEmpty else { return }

        // 先移除旧的同事件通知（防止用户改时间后旧通知还挂着）。
        // P2 修复：之前只用 identifiers.map(\.identifier)（本次新建的 IDs），
        //   若用户把重复规则从 .never（ID=base）改成 .lunarAnnually（ID=base-lunar），
        //   旧的 base 通知不会被移除 → 残留幽灵通知。
        //   改用 notificationIdentifiers(for:) 返回该事件所有可能的 IDs（base/base-lunar/base-wd-N），
        //   一次性清干净。
        center.removePendingNotificationRequests(
            withIdentifiers: notificationIdentifiers(for: event)
        )

        do {
            for req in identifiers {
                try await center.add(req)
            }
            if rule == .never {
                // P2 修复：单次提醒只在「已授权」时才标记已通知。
                //   UNUserNotificationCenter.add(_:) 在权限被拒/未确定时不抛错，
                //   但通知实际不会送达。若此时 markNotified=true，后续用户授权后
                //   rescheduleAllReminders 会因 isNotified=true 跳过该事件，
                //   导致提醒永远不响（典型"看得见不会响"）。
                //   未授权时留 isNotified=false，授权后 reschedule 会重新调度。
                let status = await authorizationStatusAsync()
                if status == .granted {
                    EventStore.shared.markNotified(event)
                }
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
        currentCenterIfAvailable?.removePendingNotificationRequests(withIdentifiers: ids)
        #endif
    }

    /// 取消所有通知
    public func cancelAll() {
        #if canImport(UserNotifications)
        currentCenterIfAvailable?.removeAllPendingNotificationRequests()
        #endif
    }

    /// 「稍后提醒」通知 ID 前缀。
    ///
    /// 这是一条**由用户主动触发的一次性通知**，不属于任何事件的常规通知组
    /// （`notificationIdentifiers(for:)` 那套）。因此 `cancelAll()` 会把它一并清掉，
    /// 需要 `rescheduleAllReminders` 显式保下来。
    static let snoozeIdentifierPrefix = "snooze-"

    /// 构造「稍后提醒」通知 ID（与 `snoozeEventID(from:)` 成对，务必同源）
    static func snoozeIdentifier(eventID: String, at epoch: TimeInterval) -> String {
        "\(snoozeIdentifierPrefix)\(eventID)-\(Int(epoch))"
    }

    /// 从「稍后提醒」ID 中取回所属事件 UUID；前缀不符或格式异常返回 nil
    static func snoozeEventID(from identifier: String) -> UUID? {
        guard identifier.hasPrefix(snoozeIdentifierPrefix) else { return nil }
        let rest = identifier.dropFirst(snoozeIdentifierPrefix.count)
        guard rest.count >= 36 else { return nil }
        return UUID(uuidString: String(rest.prefix(36)))
    }

    /// 从一批 pending 通知 ID 中挑出**应当保回**的「稍后提醒」ID：
    /// 前缀为 snooze- 且其所属事件仍然存在（事件已删除就不该再为它提醒）。
    /// 抽成纯函数，是为了让「重排时哪些 snooze 该留」这条判定可以单测。
    static func snoozeIdentifiersToPreserve(from identifiers: [String],
                                            existingEventIDs: Set<String>) -> Set<String> {
        Set(identifiers.filter { identifier in
            guard let eventID = snoozeEventID(from: identifier) else { return false }
            return existingEventIDs.contains(eventID.uuidString)
        })
    }

    /// 灵动岛「稍后提醒」：为指定事件挂一条 `after` 秒后触发的一次性通知。
    /// **不修改事件本身的时间**（避免"稍后提醒"把用户日程挪走）。
    /// - Returns: true 表示已挂载；事件不存在 / 测试环境无通知中心 / 无权限时为 false。
    @discardableResult
    public func snoozeReminder(eventID: String, after seconds: TimeInterval = 10 * 60) async -> Bool {
        #if canImport(UserNotifications)
        guard let uuid = UUID(uuidString: eventID),
              let event = EventStore.shared.eventBy(idString: uuid.uuidString),
              let center = currentCenterIfAvailable else { return false }

        let content = buildContent(for: event)
        content.body = content.body.isEmpty ? "稍后提醒" : "\(content.body)（稍后提醒）"
        let request = UNNotificationRequest(
            identifier: Self.snoozeIdentifier(eventID: eventID, at: Date().timeIntervalSince1970),
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(seconds, 1), repeats: false)
        )
        do {
            try await center.add(request)
            return true
        } catch {
            AppLogger.app.error("稍后提醒挂载失败：\(error.localizedDescription)")
            return false
        }
        #else
        return false
        #endif
    }

    /// 重新调度所有未完成的提醒
    public func rescheduleAllReminders(in store: EventStore) async {
        #if canImport(UserNotifications)
        // 先把「稍后提醒」摘出来：它是用户主动挂的一次性通知（ID 前缀 snooze-），
        // 不属于任何事件的常规通知组，而 cancelAll() 会连它一起清掉 →
        // 用户点了「稍后提醒」后，10 分钟内只要 App 回到前台或冷启动
        // （两者都会走到这里），这条就永远不送达，且没有任何提示。
        // 只保留「对应事件仍然存在」的那些，避免为已删除的事件继续提醒。
        let pending = await currentCenterIfAvailable?.pendingNotificationRequests() ?? []
        let keepIDs = Self.snoozeIdentifiersToPreserve(
            from: pending.map(\.identifier),
            existingEventIDs: Set(store.events.map { $0.id.uuidString })
        )
        let keptSnoozes = pending.filter { keepIDs.contains($0.identifier) }

        cancelAll()
        // 注意：.never && isNotified 的事件不应该再被调度
        for event in store.events
            where Self.shouldScheduleNotification(for: event) && !event.isCompleted {
            if event.repeatRule == .never && event.isNotified { continue }
            await scheduleNotification(for: event)
        }

        // 原样放回「稍后提醒」（内容与触发时刻都不变）
        if let center = currentCenterIfAvailable {
            for request in keptSnoozes {
                try? await center.add(request)
            }
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
            // P2 修复：yearly 规则的 reminderOffsetMinutes 应当完整应用到 month/day/hour/minute
            //  （之前取 startDate 的 month/day，只取 effectiveStart 的 hour/minute，
            //   对"婚礼前 1 天提醒"—— start=3/15, -1440min → effectiveStart=3/14
            //   结果 trigger 仍然绑定 3/15 每年在婚礼当天才响！）。
            //   正确行为：同 weekly/monthly/daily 一样，整组 components 从 effectiveStart 取。
            let comps = gregorian.dateComponents(
                [.month, .day, .hour, .minute], from: effectiveStart
            )
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

    /// 该事件**可能用过**的全部通知 identifier（取消时一次性清干净）。
    ///
    /// 关键：不能只按"当前 repeatRule"生成。用户把「工作日」改成「每天」（或反向、
    /// 或从农历每年改成其它）时，旧规则那组 request 的 ID 与新规则不同，
    /// 按当前规则去 cancel 会漏掉旧的 → 幽灵提醒继续按旧规则弹。
    /// 因此恒定返回全集：base / base-lunar / base-wd-2…6（最多 7 个 ID，开销可忽略）。
    private func notificationIdentifiers(for event: CalendarEvent) -> [String] {
        let base = event.id.uuidString
        return [base, "\(base)-lunar"] + (2...6).map { "\(base)-wd-\($0)" }
    }

    /// 计算未来第一个与 lunarSource 的农历月/日相同的公历日期，保留 timeSource 的时分秒。
    /// ⚠️ 语义必须与 CalendarEvent.occurs(on:) 的 lunarAnnually 分支保持一致：
    /// - 闰月源事件：目标年「有闰同月」→ 用闰月匹配；目标年「无闰同月」→ 回退普通同月同日匹配。
    /// - 普通月源事件：只匹配普通同月同日（不蹭闰月）。
    ///
    /// P1 修复：旧实现 `for year in lunar.year...lunar.year+16`——若事件起始日期距今
    ///   超过 16 年（如农历生日从出生日起算），整个搜索区间落在过去，返回 nil，
    ///   导致农历生日/纪念日提醒永不触发。修复：从「今天所在的农历年」开始往后搜。
    private func nextSolarDateForLunarAnnually(
        lunarSource: Date,
        timeSource: Date
    ) -> Date? {
        Self.nextSolarDateForLunarAnniversary(lunarSource: lunarSource, timeSource: timeSource, now: Date())
    }
    #endif

    // MARK: - 农历周年纯函数（可在 Linux 测试，不依赖 UserNotifications）

    /// 纯函数版：计算未来第一个匹配农历月/日的公历日期。
    /// 抽出到 #if canImport(UserNotifications) 之外，便于 Linux 单元测试覆盖。
    nonisolated static func nextSolarDateForLunarAnniversary(
        lunarSource: Date,
        timeSource: Date,
        now: Date
    ) -> Date? {
        guard let lunar = ChineseCalendar.lunarDateSafe(from: lunarSource) else { return nil }
        let gregorian = Calendar(identifier: .gregorian)
        let refComponents = gregorian.dateComponents(
            [.hour, .minute, .second], from: timeSource
        )

        // P1 修复：从「今天所在的农历年」开始搜，而非事件创建时的 lunar.year。
        let currentLunarYear = ChineseCalendar.lunarDateSafe(from: now)?.year ?? lunar.year
        let startYear = max(lunar.year, currentLunarYear)
        let upperBound = min(ChineseCalendar.maxYear, startYear + 16)

        for year in startYear...upperBound {
            // 按 occurs 语义决定是否用闰月：
            // - 源是闰月 + 今年有相同闰月 → 闰月匹配
            // - 源是闰月 + 今年无相同闰月 → 回退普通月匹配
            // - 源是普通月 → 普通月匹配
            let targetYearLeapMonth = ChineseCalendar.leapMonth(of: year)
            let useLeap: Bool
            if lunar.isLeapMonth {
                useLeap = (targetYearLeapMonth == lunar.month)
            } else {
                useLeap = false
            }
            // 农历"三十"生日 fallback（与 occurs(on:) 语义保持一致）：
            // 目标年该月只有 29 天时回退到廿九，避免该年提醒被跳过。
            let daysInMonth = ChineseCalendar.daysInLunarMonth(
                year: year, month: lunar.month, isLeap: useLeap
            )
            let targetDay = (lunar.day == 30 && daysInMonth == 29) ? 29 : lunar.day
            guard let solar = ChineseCalendar.solarDate(
                fromLunar: year, month: lunar.month,
                day: targetDay, isLeap: useLeap
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
}

// MARK: - 授权状态枚举

public enum NotificationAuthStatus {
    case notDetermined
    case granted
    case denied
    case unavailable  // Linux/非Apple平台
}
