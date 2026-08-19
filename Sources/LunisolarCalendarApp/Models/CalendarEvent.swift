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
    case never      = "不重复"
    case daily      = "每天"
    case workday    = "工作日"
    case weekly     = "每周"
    case monthly    = "每月"
    case yearly     = "每年"

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
        }
    }

    public var timeDisplay: String {
        if isAllDay { return "全天" }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return "\(fmt.string(from: startDate)) - \(fmt.string(from: endDate))"
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
