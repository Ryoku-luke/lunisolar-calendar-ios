import Foundation

// MARK: - 日程/记事 类型

public enum EventType: String, Codable, CaseIterable, Identifiable {
    case schedule
    case reminder
    case note

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .schedule: return "日程"
        case .reminder: return "提醒"
        case .note:     return "记事"
        }
    }

    var systemIcon: String {
        switch self {
        case .schedule: return "calendar"
        case .reminder: return "bell.badge"
        case .note:     return "note.text"
        }
    }
}

// MARK: - 重复规则

public enum RepeatRule: String, Codable, CaseIterable, Identifiable {
    case never           = "不重复"
    case daily           = "每天"
    case workday         = "工作日"
    case weekly          = "每周"
    case monthly         = "每月"
    case yearly          = "每年"
    case lunarAnnually   = "农历每年"

    public var id: String { rawValue }
    public var title: String { rawValue }
}

// MARK: - 优先级

public enum Priority: String, Codable, CaseIterable, Identifiable, Comparable {
    case low        = "低"
    case normal     = "中"
    case high       = "高"
    case urgent     = "紧急"

    public var id: String { rawValue }
    public var title: String { rawValue }

    var order: Int {
        switch self {
        case .low: return 0
        case .normal: return 1
        case .high: return 2
        case .urgent: return 3
        }
    }

    public static func < (lhs: Priority, rhs: Priority) -> Bool {
        lhs.order < rhs.order
    }
}

// MARK: - 事件模型

public struct CalendarEvent: Identifiable, Equatable, Hashable, Codable {
    public var id: UUID
    public var title: String
    public var type: EventType
    public var startDate: Date
    public var endDate: Date
    public var isAllDay: Bool
    public var location: String?
    public var notes: String?
    public var repeatRule: RepeatRule
    public var priority: Priority
    public var isCompleted: Bool
    /// 通知是否已触发（防止重复弹窗）
    public var isNotified: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        type: EventType = .schedule,
        startDate: Date,
        endDate: Date? = nil,
        isAllDay: Bool = false,
        location: String? = nil,
        notes: String? = nil,
        repeatRule: RepeatRule = .never,
        priority: Priority = .normal,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.startDate = startDate
        // 确保 endDate > startDate：用户直接传 endDate 早于 startDate 时自动兜底
        let requestedEnd = endDate ?? startDate.addingTimeInterval(3600)
        if requestedEnd <= startDate {
            let fallback: TimeInterval = isAllDay ? 86399 : 3600
            self.endDate = startDate.addingTimeInterval(fallback)
        } else {
            self.endDate = requestedEnd
        }
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.repeatRule = repeatRule
        self.priority = priority
        self.isCompleted = isCompleted
        self.isNotified = false
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    public func occurs(on date: Date) -> Bool {
        let cal = Calendar.current
        let target = cal.startOfDay(for: date)
        let start = cal.startOfDay(for: startDate)

        switch repeatRule {
        case .never:
            return target == start
        case .daily:
            return target >= start
        case .workday:
            let weekday = cal.component(.weekday, from: target)
            return target >= start && weekday >= 2 && weekday <= 6
        case .weekly:
            let targetWeekday = cal.component(.weekday, from: target)
            let startWeekday = cal.component(.weekday, from: start)
            return target >= start && targetWeekday == startWeekday
        case .monthly:
            let targetDay = cal.component(.day, from: target)
            let startDay = cal.component(.day, from: start)
            return target >= start && targetDay == startDay
        case .yearly:
            let tm = cal.dateComponents([.month, .day], from: target)
            let sm = cal.dateComponents([.month, .day], from: start)
            return target >= start && tm.month == sm.month && tm.day == sm.day
        case .lunarAnnually:
            // 农历每年重复：匹配农历月日（父母生日、传统节日等）
            // 民俗处理：
            // - 起始是平月：要求 target 也是平月 + 同月同日（避免闰月罕见触发"多一次"）
            // - 起始是闰月（闰五月初五）：只要求同月同日（五月初五 或 闰五月初五 都命中，保证每年至少一次）
            // 日期门槛比较统一使用 startOfDay 归一化（和 never/daily/weekly/monthly/yearly 保持一致），
            // 避免"起锚20:00的事件当天上午查不到"的一致性 BUG（BUG #1）。
            let targetLunar = ChineseCalendar.lunarDateSafe(from: date)
            let startLunar = ChineseCalendar.lunarDateSafe(from: startDate)
            guard let tl = targetLunar, let sl = startLunar else { return false }
            guard target >= start else { return false }
            guard tl.month == sl.month && tl.day == sl.day else { return false }
            if sl.isLeapMonth {
                return true
            } else {
                return !tl.isLeapMonth
            }
        }
    }

    public var timeDisplay: String {
        if isAllDay { return "全天" }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return "\(fmt.string(from: startDate)) - \(fmt.string(from: endDate))"
    }

    // MARK: - 重复规则文本（列表/详情页显示 + 编辑页锚点提示）

    /// 事件行右侧小标签：「每天」「农历正月十五·每年」等
    public var repeatRuleLabel: String {
        switch repeatRule {
        case .never:      return ""
        case .daily:      return "每天"
        case .workday:    return "每个工作日"
        case .weekly:
            let weekday = Calendar.current.component(.weekday, from: startDate)
            let names = ["周日","周一","周二","周三","周四","周五","周六"]
            let idx = max(0, min(6, weekday - 1))
            return "每周\(names[idx])"
        case .monthly:
            let day = Calendar.current.component(.day, from: startDate)
            return "每月\(day)日"
        case .yearly:
            let c = Calendar.current.dateComponents([.month, .day], from: startDate)
            let m = max(1, c.month ?? 1)
            let d = max(1, c.day ?? 1)
            return "公历 \(m)月\(d)日 · 每年"
        case .lunarAnnually:
            if let lunar = ChineseCalendar.lunarDateSafe(from: startDate) {
                return "农历\(lunar.monthName)\(lunar.dayName) · 每年"
            }
            return "农历生日 · 每年"
        }
    }

    /// 编辑页底部详细提示（解释当前重复规则的锚点日期）
    public static func repeatAnchorDescription(rule: RepeatRule, anchor: Date) -> String {
        let cal = Calendar.current
        switch rule {
        case .never:
            return "仅在所选日期出现一次"
        case .daily:
            return "自 \(Self.dateShort(anchor)) 起，每天都会出现"
        case .workday:
            return "自 \(Self.dateShort(anchor)) 起，周一至周五（工作日）都会出现"
        case .weekly:
            let weekday = cal.component(.weekday, from: anchor)
            let names = ["周日","周一","周二","周三","周四","周五","周六"]
            let idx = max(0, min(6, weekday - 1))
            return "每周\(names[idx]) 重复（锚点：\(Self.dateShort(anchor))）"
        case .monthly:
            let day = cal.component(.day, from: anchor)
            return "每月\(day)日 重复（锚点：\(Self.dateShort(anchor))）"
        case .yearly:
            let c = cal.dateComponents([.month, .day], from: anchor)
            let m = max(1, c.month ?? 1)
            let d = max(1, c.day ?? 1)
            return "公历每年 \(m) 月 \(d) 日 重复（锚点：\(Self.dateShort(anchor))）"
        case .lunarAnnually:
            if let lunar = ChineseCalendar.lunarDateSafe(from: anchor) {
                let leapHint = lunar.isLeapMonth ? "（闰月生日在非闰月年按同月同日过）" : ""
                return "农历每年 \(lunar.monthName)\(lunar.dayName) 重复\(leapHint)（公历锚点：\(Self.dateShort(anchor))）"
            }
            return "农历每年 重复（公历锚点：\(Self.dateShort(anchor))）"
        }
    }

    private static func dateShort(_ d: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy/M/d"
        return fmt.string(from: d)
    }
}

#if canImport(SwiftUI)
import SwiftUI

extension EventType {
    var tintColor: Color {
        switch self {
        case .schedule: return .blue
        case .reminder: return .orange
        case .note:     return .purple
        }
    }
}

extension Priority {
    var tintColor: Color {
        switch self {
        case .low: return .green
        case .normal: return .blue
        case .high: return .orange
        case .urgent: return .red
        }
    }
}
#endif
