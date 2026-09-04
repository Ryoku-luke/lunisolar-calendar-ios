import Foundation
import LunarCore

// MARK: - 二十四节气

/// 二十四节气数据与倒计时。
/// 节气精确到分钟，此处内置 2025–2028 年的精确时刻（基于天文计算）。
public enum SolarTermProvider: Sendable {

    /// 二十四节气名称（按年内顺序）
    public static let termNames: [String] = [
        "小寒", "大寒", "立春", "雨水", "惊蛰", "春分",
        "清明", "谷雨", "立夏", "小满", "芒种", "夏至",
        "小暑", "大暑", "立秋", "处暑", "白露", "秋分",
        "寒露", "霜降", "立冬", "小雪", "大雪", "冬至"
    ]

    /// 节气数据条目：(年, 节气序号0-23, 月, 日, 时, 分)
    private struct TermEntry: Sendable {
        let year: Int
        let index: Int   // 0-23
        let month: Int
        let day: Int
        let hour: Int
        let minute: Int
        var name: String { termNames[index] }
        var date: Date {
            var dc = DateComponents()
            dc.year = year; dc.month = month; dc.day = day
            dc.hour = hour; dc.minute = minute
            dc.timeZone = TimeZone(identifier: "Asia/Shanghai")
            return Calendar(identifier: .gregorian).date(from: dc) ?? Date()
        }
    }

    // 内置 2025–2028 节气时刻表（来源：紫金山天文台），已按 year+index 升序
    private static let entries: [TermEntry] = [
        // 2025
        .init(year: 2025, index: 0,  month: 1,  day: 5,  hour: 11, minute: 23),
        .init(year: 2025, index: 1,  month: 1,  day: 20, hour: 4,  minute: 0),
        .init(year: 2025, index: 2,  month: 2,  day: 3,  hour: 22, minute: 10),
        .init(year: 2025, index: 3,  month: 2,  day: 18, hour: 18, minute: 7),
        .init(year: 2025, index: 4,  month: 3,  day: 5,  hour: 16, minute: 7),
        .init(year: 2025, index: 5,  month: 3,  day: 20, hour: 17, minute: 2),
        .init(year: 2025, index: 6,  month: 4,  day: 4,  hour: 20, minute: 49),
        .init(year: 2025, index: 7,  month: 4,  day: 20, hour: 3,  minute: 56),
        .init(year: 2025, index: 8,  month: 5,  day: 5,  hour: 13, minute: 57),
        .init(year: 2025, index: 9,  month: 5,  day: 21, hour: 3,  minute: 54),
        .init(year: 2025, index: 10, month: 6,  day: 5,  hour: 18, minute: 52),
        .init(year: 2025, index: 11, month: 6,  day: 21, hour: 10, minute: 42),
        .init(year: 2025, index: 12, month: 7,  day: 7,  hour: 4,  minute: 5),
        .init(year: 2025, index: 13, month: 7,  day: 22, hour: 21, minute: 29),
        .init(year: 2025, index: 14, month: 8,  day: 7,  hour: 13, minute: 51),
        .init(year: 2025, index: 15, month: 8,  day: 23, hour: 4,  minute: 34),
        .init(year: 2025, index: 16, month: 9,  day: 7,  hour: 16, minute: 52),
        .init(year: 2025, index: 17, month: 9,  day: 23, hour: 2,  minute: 19),
        .init(year: 2025, index: 18, month: 10, day: 8,  hour: 8,  minute: 41),
        .init(year: 2025, index: 19, month: 10, day: 23, hour: 11, minute: 51),
        .init(year: 2025, index: 20, month: 11, day: 7,  hour: 6,  minute: 20),
        .init(year: 2025, index: 21, month: 11, day: 22, hour: 3,  minute: 56),
        .init(year: 2025, index: 22, month: 12, day: 7,  hour: 5,  minute: 5),
        .init(year: 2025, index: 23, month: 12, day: 21, hour: 23, minute: 3),
        // 2026
        .init(year: 2026, index: 0,  month: 1,  day: 5,  hour: 5,  minute: 23),
        .init(year: 2026, index: 1,  month: 1,  day: 20, hour: 22, minute: 0),
        .init(year: 2026, index: 2,  month: 2,  day: 4,  hour: 4,  minute: 1),
        .init(year: 2026, index: 3,  month: 2,  day: 18, hour: 23, minute: 52),
        .init(year: 2026, index: 4,  month: 3,  day: 5,  hour: 21, minute: 59),
        .init(year: 2026, index: 5,  month: 3,  day: 20, hour: 22, minute: 46),
        .init(year: 2026, index: 6,  month: 4,  day: 5,  hour: 2,  minute: 40),
        .init(year: 2026, index: 7,  month: 4,  day: 20, hour: 9,  minute: 39),
        .init(year: 2026, index: 8,  month: 5,  day: 5,  hour: 19, minute: 48),
        .init(year: 2026, index: 9,  month: 5,  day: 21, hour: 9,  minute: 38),
        .init(year: 2026, index: 10, month: 6,  day: 6,  hour: 0,  minute: 48),
        .init(year: 2026, index: 11, month: 6,  day: 21, hour: 16, minute: 44),
        .init(year: 2026, index: 12, month: 7,  day: 7,  hour: 10, minute: 0),
        .init(year: 2026, index: 13, month: 7,  day: 23, hour: 3,  minute: 13),
        .init(year: 2026, index: 14, month: 8,  day: 7,  hour: 19, minute: 43),
        .init(year: 2026, index: 15, month: 8,  day: 23, hour: 10, minute: 19),
        .init(year: 2026, index: 16, month: 9,  day: 7,  hour: 22, minute: 41),
        .init(year: 2026, index: 17, month: 9,  day: 23, hour: 8,  minute: 5),
        .init(year: 2026, index: 18, month: 10, day: 8,  hour: 14, minute: 31),
        .init(year: 2026, index: 19, month: 10, day: 23, hour: 17, minute: 38),
        .init(year: 2026, index: 20, month: 11, day: 7,  hour: 12, minute: 5),
        .init(year: 2026, index: 21, month: 11, day: 22, hour: 9,  minute: 46),
        .init(year: 2026, index: 22, month: 12, day: 7,  hour: 10, minute: 53),
        .init(year: 2026, index: 23, month: 12, day: 22, hour: 4,  minute: 50),
        // 2027
        .init(year: 2027, index: 0,  month: 1,  day: 5,  hour: 11, minute: 9),
        .init(year: 2027, index: 1,  month: 1,  day: 20, hour: 4,  minute: 30),
        .init(year: 2027, index: 2,  month: 2,  day: 4,  hour: 3,  minute: 38),
        .init(year: 2027, index: 3,  month: 2,  day: 19, hour: 1,  minute: 33),
        .init(year: 2027, index: 4,  month: 3,  day: 6,  hour: 7,  minute: 35),
        .init(year: 2027, index: 5,  month: 3,  day: 21, hour: 2,  minute: 25),
        .init(year: 2027, index: 6,  month: 4,  day: 5,  hour: 7,  minute: 37),
        .init(year: 2027, index: 7,  month: 4,  day: 20, hour: 15, minute: 17),
        .init(year: 2027, index: 8,  month: 5,  day: 6,  hour: 1,  minute: 27),
        .init(year: 2027, index: 9,  month: 5,  day: 21, hour: 15, minute: 11),
        .init(year: 2027, index: 10, month: 6,  day: 6,  hour: 6,  minute: 36),
        .init(year: 2027, index: 11, month: 6,  day: 21, hour: 22, minute: 26),
        .init(year: 2027, index: 12, month: 7,  day: 7,  hour: 16, minute: 7),
        .init(year: 2027, index: 13, month: 7,  day: 23, hour: 9,  minute: 14),
        .init(year: 2027, index: 14, month: 8,  day: 8,  hour: 2,  minute: 0),
        .init(year: 2027, index: 15, month: 8,  day: 23, hour: 16, minute: 46),
        .init(year: 2027, index: 16, month: 9,  day: 8,  hour: 5,  minute: 8),
        .init(year: 2027, index: 17, month: 9,  day: 23, hour: 14, minute: 30),
        .init(year: 2027, index: 18, month: 10, day: 8,  hour: 20, minute: 35),
        .init(year: 2027, index: 19, month: 10, day: 23, hour: 23, minute: 39),
        .init(year: 2027, index: 20, month: 11, day: 7,  hour: 18, minute: 5),
        .init(year: 2027, index: 21, month: 11, day: 22, hour: 16, minute: 10),
        .init(year: 2027, index: 22, month: 12, day: 7,  hour: 17, minute: 23),
        .init(year: 2027, index: 23, month: 12, day: 22, hour: 10, minute: 44),
        // 2028
        .init(year: 2028, index: 0,  month: 1,  day: 6,  hour: 3,  minute: 54),
        .init(year: 2028, index: 1,  month: 1,  day: 21, hour: 3,  minute: 47),
        .init(year: 2028, index: 2,  month: 2,  day: 4,  hour: 18, minute: 54),
        .init(year: 2028, index: 3,  month: 2,  day: 19, hour: 20, minute: 25),
        .init(year: 2028, index: 4,  month: 3,  day: 5,  hour: 16, minute: 24),
        .init(year: 2028, index: 5,  month: 3,  day: 20, hour: 17, minute: 18),
        .init(year: 2028, index: 6,  month: 4,  day: 4,  hour: 21, minute: 35),
        .init(year: 2028, index: 7,  month: 4,  day: 20, hour: 4,  minute: 59),
        .init(year: 2028, index: 8,  month: 5,  day: 5,  hour: 15, minute: 0),
        .init(year: 2028, index: 9,  month: 5,  day: 21, hour: 4,  minute: 50),
        .init(year: 2028, index: 10, month: 6,  day: 5,  hour: 20, minute: 10),
        .init(year: 2028, index: 11, month: 6,  day: 21, hour: 12,  minute: 2),
        .init(year: 2028, index: 12, month: 7,  day: 7,  hour: 5,  minute: 24),
        .init(year: 2028, index: 13, month: 7,  day: 22, hour: 22,  minute: 45),
        .init(year: 2028, index: 14, month: 8,  day: 7,  hour: 15, minute: 15),
        .init(year: 2028, index: 15, month: 8,  day: 23, hour: 6,  minute: 4),
        .init(year: 2028, index: 16, month: 9,  day: 7,  hour: 18, minute: 31),
        .init(year: 2028, index: 17, month: 9,  day: 22, hour: 10, minute: 2),
        .init(year: 2028, index: 18, month: 10, day: 8,  hour: 16,  minute: 18),
        .init(year: 2028, index: 19, month: 10, day: 23, hour: 19,  minute: 20),
        .init(year: 2028, index: 20, month: 11, day: 7,  hour: 13,  minute: 48),
        .init(year: 2028, index: 21, month: 11, day: 22, hour: 11,  minute: 37),
        .init(year: 2028, index: 22, month: 12, day: 7,  hour: 12,  minute: 38),
        .init(year: 2028, index: 23, month: 12, day: 21, hour: 6,  minute: 25),
    ]

    /// 按发生时间排好序的节气表（避免 nextTerm 每次 O(N log N) 重排）。
    /// entries 源数据本身是「年 × 年内节气序号 0-23」升序写入，Date 也单调递增，但
    /// 保险起见仍做一次排序并缓存，保证后续线性扫描的正确性。
    private static let sortedEntries: [TermEntry] = entries.sorted { $0.date < $1.date }

    // MARK: - 查询

    /// 距离 from 最近的未过去节气。
    public static func nextTerm(from date: Date) -> (name: String, date: Date, daysRemaining: Int)? {
        let cal = Calendar(identifier: .gregorian)
        let now = cal.startOfDay(for: date)
        for entry in sortedEntries where entry.date >= now {
            let days = cal.dateComponents([.day], from: now, to: cal.startOfDay(for: entry.date)).day ?? 0
            return (entry.name, entry.date, days)
        }
        return nil
    }

    /// 返回给定日期所属的节气（如果当天正好是节气交节日）。
    public static func termOn(_ date: Date) -> String? {
        let cal = Calendar(identifier: .gregorian)
        let day = cal.startOfDay(for: date)
        for entry in entries where cal.isDate(entry.date, inSameDayAs: day) {
            return entry.name
        }
        return nil
    }

    /// 返回给定年份的所有节气。
    public static func terms(in year: Int) -> [(name: String, date: Date)] {
        entries.filter { $0.year == year }.sorted { $0.date < $1.date }
            .map { ($0.name, $0.date) }
    }
}
