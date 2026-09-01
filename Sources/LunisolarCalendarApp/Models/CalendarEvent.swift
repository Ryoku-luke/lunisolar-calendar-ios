import Foundation

// MARK: - 日程/记事 类型

public enum EventType: String, Codable, CaseIterable, Identifiable, Sendable {
    case schedule
    case reminder
    case note

    public var id: String { rawValue }

    /// UI / 导出显示名；不与 SwiftFoundation 的 String.title / AttributedString.title 扩展名冲突
    public var uiLabel: String {
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

    /// SwiftUI / Widget 显示用图标名（与 systemIcon 同义）
    public var iconName: String { systemIcon }
}

// MARK: - 重复规则

public enum RepeatRule: String, Codable, CaseIterable, Identifiable, Sendable {
    case never           = "不重复"
    case daily           = "每天"
    case workday         = "工作日"
    case weekly          = "每周"
    case monthly         = "每月"
    case yearly          = "每年"
    case lunarAnnually   = "农历每年"

    public var id: String { rawValue }
    /// UI / 导出显示名；不与 Foundation String `.title` 语义扩展歧义
    public var uiLabel: String { rawValue }
    /// 列表行内的短标签 —— .never 返回 nil（列表不显示"不重复"）
    public var displayText: String? {
        switch self {
        case .never: return nil
        default:     return uiLabel
        }
    }
}

// MARK: - 优先级

public enum Priority: String, Codable, CaseIterable, Identifiable, Comparable, Sendable {
    case low        = "低"
    case normal     = "中"
    case high       = "高"
    case urgent     = "紧急"

    public var id: String { rawValue }
    /// UI / 导出显示名；不与 Foundation String `.title` 语义扩展歧义
    public var uiLabel: String { rawValue }

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

public struct CalendarEvent: Identifiable, Codable, Sendable {
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
    /// 提前提醒分钟数（nil = 无提醒；0 = 准时；正数 = 提前 N 分钟）
    public var reminderOffsetMinutes: Int?
    /// 通知是否已触发（防止重复弹窗）
    public var isNotified: Bool
    public var createdAt: Date
    public var updatedAt: Date

    /// CodingKeys：显式排除缓存字段
    private enum CodingKeys: String, CodingKey {
        case id, title, type, startDate, endDate, isAllDay, location, notes
        case repeatRule, priority, isCompleted, reminderOffsetMinutes, isNotified, createdAt, updatedAt
    }

    /// 缓存 startDate 的农历转换结果（用引用类型绕过 struct 不可变性，同一事件永远不变）
    private final class Box<T: Sendable>: @unchecked Sendable { var value: T?; init() {} }
    private var _lunarBox: Box<LunarDate> = Box()

    // MARK: - W2/W3 修复：非隔离 Codable 实现
    // Swift 6 strict mode 下，对 Sendable struct 的 synthesized Encodable/Decodable
    // 有时会被推断为 @MainActor（特别是类型内含有 reference-type cached field 时），
    // 导致 SyncCoders.encoder() 在 nonisolated 上下文调用时触发
    // "Main actor-isolated conformance of 'CalendarEvent' to 'Encodable/Decodable'
    // cannot be used in nonisolated context" 警告。
    // 显式 nonisolated 实现 encode(to:)/init(from:) 即可消除。

    nonisolated public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(type, forKey: .type)
        try c.encode(startDate, forKey: .startDate)
        try c.encode(endDate, forKey: .endDate)
        try c.encode(isAllDay, forKey: .isAllDay)
        try c.encode(location, forKey: .location)
        try c.encode(notes, forKey: .notes)
        try c.encode(repeatRule, forKey: .repeatRule)
        try c.encode(priority, forKey: .priority)
        try c.encode(isCompleted, forKey: .isCompleted)
        try c.encode(reminderOffsetMinutes, forKey: .reminderOffsetMinutes)
        try c.encode(isNotified, forKey: .isNotified)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }

    nonisolated public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decode(UUID.self, forKey: .id)
        title          = try c.decode(String.self, forKey: .title)
        type           = try c.decode(EventType.self, forKey: .type)
        startDate      = try c.decode(Date.self, forKey: .startDate)
        endDate        = try c.decode(Date.self, forKey: .endDate)
        isAllDay       = try c.decode(Bool.self, forKey: .isAllDay)
        location       = try c.decodeIfPresent(String.self, forKey: .location)
        notes          = try c.decodeIfPresent(String.self, forKey: .notes)
        repeatRule     = try c.decode(RepeatRule.self, forKey: .repeatRule)
        priority       = try c.decode(Priority.self, forKey: .priority)
        isCompleted    = try c.decode(Bool.self, forKey: .isCompleted)
        reminderOffsetMinutes = try c.decodeIfPresent(Int.self, forKey: .reminderOffsetMinutes)
        isNotified     = try c.decode(Bool.self, forKey: .isNotified)
        createdAt      = try c.decode(Date.self, forKey: .createdAt)
        updatedAt      = try c.decode(Date.self, forKey: .updatedAt)
        // 缓存字段重建
        _lunarBox      = Box()
    }
    private var startLunarCached: LunarDate? {
        if let cached = _lunarBox.value { return cached }
        let lunar = ChineseCalendar.lunarDateSafe(from: startDate)
        _lunarBox.value = lunar
        return lunar
    }

    nonisolated public init(
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
        isCompleted: Bool = false,
        reminderOffsetMinutes: Int? = nil
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
        self.reminderOffsetMinutes = reminderOffsetMinutes
        self.isNotified = false
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    public func occurs(on date: Date) -> Bool {
        // 使用公历 Calendar：用户系统日历设置可能是伊斯兰/佛历/和历，
        // 但重复规则的"每月5号/每周三/每年8月15日"语义一律按公历解释（BUG #30 修复）。
        let cal = Calendar(identifier: .gregorian)
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
            // startLunar 使用缓存（同一事件永远不变）
            let targetLunar = ChineseCalendar.lunarDateSafe(from: date)
            guard let tl = targetLunar, let sl = startLunarCached else { return false }
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

    /// SwiftUI / Widget 显示用时间（与 timeDisplay 同义，UI 层统一用 display 前缀）
    public var displayTimeRange: String { timeDisplay }

    // MARK: - 重复规则文本（列表/详情页显示 + 编辑页锚点提示）

    /// 事件行右侧小标签：「每天」「农历正月十五·每年」等
    public var repeatRuleLabel: String {
        // 重复规则语义一律按公历解析（BUG #30 修复）
        let cal = Calendar(identifier: .gregorian)
        switch repeatRule {
        case .never:      return ""
        case .daily:      return "每天"
        case .workday:    return "每个工作日"
        case .weekly:
            let weekday = cal.component(.weekday, from: startDate)
            let names = ["周日","周一","周二","周三","周四","周五","周六"]
            let idx = max(0, min(6, weekday - 1))
            return "每周\(names[idx])"
        case .monthly:
            let day = cal.component(.day, from: startDate)
            return "每月\(day)日"
        case .yearly:
            let c = cal.dateComponents([.month, .day], from: startDate)
            let m = max(1, c.month ?? 1)
            let d = max(1, c.day ?? 1)
            return "公历 \(m)月\(d)日 · 每年"
        case .lunarAnnually:
            if let lunar = startLunarCached {
                return "农历\(lunar.monthName)\(lunar.dayName) · 每年"
            }
            return "农历生日 · 每年"
        }
    }

    /// 编辑页底部详细提示（解释当前重复规则的锚点日期）
    public static func repeatAnchorDescription(rule: RepeatRule, anchor: Date) -> String {
        // 重复规则语义一律按公历解析（BUG #30 修复）
        let cal = Calendar(identifier: .gregorian)
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
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "zh_CN_POSIX")
        fmt.dateFormat = "yyyy/M/d"
        return fmt.string(from: d)
    }
}

// MARK: - Equatable & Hashable（手动实现，排除缓存字段）
extension CalendarEvent: Equatable, Hashable {
    public static func == (lhs: CalendarEvent, rhs: CalendarEvent) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.type == rhs.type &&
        lhs.startDate == rhs.startDate &&
        lhs.endDate == rhs.endDate &&
        lhs.isAllDay == rhs.isAllDay &&
        lhs.location == rhs.location &&
        lhs.notes == rhs.notes &&
        lhs.repeatRule == rhs.repeatRule &&
        lhs.priority == rhs.priority &&
        lhs.isCompleted == rhs.isCompleted &&
        lhs.reminderOffsetMinutes == rhs.reminderOffsetMinutes &&
        lhs.isNotified == rhs.isNotified &&
        lhs.createdAt == rhs.createdAt &&
        lhs.updatedAt == rhs.updatedAt
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

#if canImport(SwiftUI)
import SwiftUI

extension EventType {
    /// iOS 26 语义色：替换原生 .blue/.orange 为 UIColor 系统色（深浅模式一致表现）
    var tintColor: Color {
        switch self {
        case .schedule: return .systemBlue
        case .reminder: return .systemOrange
        case .note:     return .systemPurple
        }
    }
}

extension Priority {
    public var title: String { rawValue }

    /// 胶囊徽标里的短文案（更紧凑，适合 EventRow 的优先级 badge）
    public var shortTitle: String {
        switch self {
        case .low:    return "低"
        case .normal: return "中"
        case .high:   return "高"
        case .urgent: return "紧急"
        }
    }

    /// iOS 26 语义色：紧急=红；高=橙；中=蓝；低=绿
    var tintColor: Color {
        switch self {
        case .low:    return .systemGreen
        case .normal: return .systemBlue
        case .high:   return .systemOrange
        case .urgent: return .systemRed
        }
    }
}
#endif
