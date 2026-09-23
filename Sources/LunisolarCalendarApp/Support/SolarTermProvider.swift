import Foundation

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
        var name: String {
            // 节气名本地化：termNames 保留中文作为 Localizable key 源，
            // 显示层按系统语言取翻译（英文/日文/繁体各有对照）
            L10n.str(termNames[index])
        }
        var date: Date {
            var dc = DateComponents()
            dc.year = year; dc.month = month; dc.day = day
            dc.hour = hour; dc.minute = minute
            dc.timeZone = QingheCalendarContext.chinaTimeZone
            return Calendar(identifier: .gregorian).date(from: dc) ?? Date()
        }
    }

    // 内置 2024–2032 节气时刻表（Swiss Ephemeris 天文计算，太阳视黄经 15° 整数倍交节，
    // 北京时间；已与新华社/央视发布值、紫金山天文台、香港天文台交叉验证，分钟级一致），
    // 已按 year+index 升序
    private static let entries: [TermEntry] = [
        // 2024
        .init(year: 2024, index: 0,  month: 1,  day: 6,  hour: 4, minute: 49),
        .init(year: 2024, index: 1,  month: 1,  day: 20,  hour: 22, minute: 7),
        .init(year: 2024, index: 2,  month: 2,  day: 4,  hour: 16, minute: 27),
        .init(year: 2024, index: 3,  month: 2,  day: 19,  hour: 12, minute: 13),
        .init(year: 2024, index: 4,  month: 3,  day: 5,  hour: 10, minute: 22),
        .init(year: 2024, index: 5,  month: 3,  day: 20,  hour: 11, minute: 6),
        .init(year: 2024, index: 6,  month: 4,  day: 4,  hour: 15, minute: 2),
        .init(year: 2024, index: 7,  month: 4,  day: 19,  hour: 21, minute: 59),
        .init(year: 2024, index: 8,  month: 5,  day: 5,  hour: 8, minute: 10),
        .init(year: 2024, index: 9,  month: 5,  day: 20,  hour: 20, minute: 59),
        .init(year: 2024, index: 10,  month: 6,  day: 5,  hour: 12, minute: 9),
        .init(year: 2024, index: 11,  month: 6,  day: 21,  hour: 4, minute: 51),
        .init(year: 2024, index: 12,  month: 7,  day: 6,  hour: 22, minute: 20),
        .init(year: 2024, index: 13,  month: 7,  day: 22,  hour: 15, minute: 44),
        .init(year: 2024, index: 14,  month: 8,  day: 7,  hour: 8, minute: 9),
        .init(year: 2024, index: 15,  month: 8,  day: 22,  hour: 22, minute: 55),
        .init(year: 2024, index: 16,  month: 9,  day: 7,  hour: 11, minute: 11),
        .init(year: 2024, index: 17,  month: 9,  day: 22,  hour: 20, minute: 43),
        .init(year: 2024, index: 18,  month: 10,  day: 8,  hour: 2, minute: 59),
        .init(year: 2024, index: 19,  month: 10,  day: 23,  hour: 6, minute: 14),
        .init(year: 2024, index: 20,  month: 11,  day: 7,  hour: 6, minute: 20),
        .init(year: 2024, index: 21,  month: 11,  day: 22,  hour: 3, minute: 56),
        .init(year: 2024, index: 22,  month: 12,  day: 6,  hour: 23, minute: 17),
        .init(year: 2024, index: 23,  month: 12,  day: 21,  hour: 17, minute: 20),
        // 2025
        .init(year: 2025, index: 0,  month: 1,  day: 5,  hour: 10, minute: 32),
        .init(year: 2025, index: 1,  month: 1,  day: 20,  hour: 4, minute: 0),
        .init(year: 2025, index: 2,  month: 2,  day: 3,  hour: 22, minute: 10),
        .init(year: 2025, index: 3,  month: 2,  day: 18,  hour: 18, minute: 6),
        .init(year: 2025, index: 4,  month: 3,  day: 5,  hour: 16, minute: 7),
        .init(year: 2025, index: 5,  month: 3,  day: 20,  hour: 17, minute: 1),
        .init(year: 2025, index: 6,  month: 4,  day: 4,  hour: 20, minute: 48),
        .init(year: 2025, index: 7,  month: 4,  day: 20,  hour: 3, minute: 56),
        .init(year: 2025, index: 8,  month: 5,  day: 5,  hour: 13, minute: 57),
        .init(year: 2025, index: 9,  month: 5,  day: 21,  hour: 2, minute: 54),
        .init(year: 2025, index: 10,  month: 6,  day: 5,  hour: 17, minute: 56),
        .init(year: 2025, index: 11,  month: 6,  day: 21,  hour: 10, minute: 42),
        .init(year: 2025, index: 12,  month: 7,  day: 7,  hour: 4, minute: 5),
        .init(year: 2025, index: 13,  month: 7,  day: 22,  hour: 21, minute: 29),
        .init(year: 2025, index: 14,  month: 8,  day: 7,  hour: 13, minute: 51),
        .init(year: 2025, index: 15,  month: 8,  day: 23,  hour: 4, minute: 33),
        .init(year: 2025, index: 16,  month: 9,  day: 7,  hour: 16, minute: 51),
        .init(year: 2025, index: 17,  month: 9,  day: 23,  hour: 2, minute: 19),
        .init(year: 2025, index: 18,  month: 10,  day: 8,  hour: 8, minute: 41),
        .init(year: 2025, index: 19,  month: 10,  day: 23,  hour: 11, minute: 50),
        .init(year: 2025, index: 20,  month: 11,  day: 7,  hour: 12, minute: 4),
        .init(year: 2025, index: 21,  month: 11,  day: 22,  hour: 9, minute: 35),
        .init(year: 2025, index: 22,  month: 12,  day: 7,  hour: 5, minute: 4),
        .init(year: 2025, index: 23,  month: 12,  day: 21,  hour: 23, minute: 3),
        // 2026
        .init(year: 2026, index: 0,  month: 1,  day: 5,  hour: 16, minute: 23),
        .init(year: 2026, index: 1,  month: 1,  day: 20,  hour: 9, minute: 44),
        .init(year: 2026, index: 2,  month: 2,  day: 4,  hour: 4, minute: 2),
        .init(year: 2026, index: 3,  month: 2,  day: 18,  hour: 23, minute: 51),
        .init(year: 2026, index: 4,  month: 3,  day: 5,  hour: 21, minute: 58),
        .init(year: 2026, index: 5,  month: 3,  day: 20,  hour: 22, minute: 45),
        .init(year: 2026, index: 6,  month: 4,  day: 5,  hour: 2, minute: 40),
        .init(year: 2026, index: 7,  month: 4,  day: 20,  hour: 9, minute: 39),
        .init(year: 2026, index: 8,  month: 5,  day: 5,  hour: 19, minute: 48),
        .init(year: 2026, index: 9,  month: 5,  day: 21,  hour: 8, minute: 36),
        .init(year: 2026, index: 10,  month: 6,  day: 5,  hour: 23, minute: 48),
        .init(year: 2026, index: 11,  month: 6,  day: 21,  hour: 16, minute: 24),
        .init(year: 2026, index: 12,  month: 7,  day: 7,  hour: 9, minute: 56),
        .init(year: 2026, index: 13,  month: 7,  day: 23,  hour: 3, minute: 13),
        .init(year: 2026, index: 14,  month: 8,  day: 7,  hour: 19, minute: 42),
        .init(year: 2026, index: 15,  month: 8,  day: 23,  hour: 10, minute: 18),
        .init(year: 2026, index: 16,  month: 9,  day: 7,  hour: 22, minute: 41),
        .init(year: 2026, index: 17,  month: 9,  day: 23,  hour: 8, minute: 5),
        .init(year: 2026, index: 18,  month: 10,  day: 8,  hour: 14, minute: 29),
        .init(year: 2026, index: 19,  month: 10,  day: 23,  hour: 17, minute: 37),
        .init(year: 2026, index: 20,  month: 11,  day: 7,  hour: 17, minute: 52),
        .init(year: 2026, index: 21,  month: 11,  day: 22,  hour: 15, minute: 23),
        .init(year: 2026, index: 22,  month: 12,  day: 7,  hour: 10, minute: 52),
        .init(year: 2026, index: 23,  month: 12,  day: 22,  hour: 4, minute: 50),
        // 2027
        .init(year: 2027, index: 0,  month: 1,  day: 5,  hour: 22, minute: 9),
        .init(year: 2027, index: 1,  month: 1,  day: 20,  hour: 15, minute: 29),
        .init(year: 2027, index: 2,  month: 2,  day: 4,  hour: 9, minute: 46),
        .init(year: 2027, index: 3,  month: 2,  day: 19,  hour: 5, minute: 33),
        .init(year: 2027, index: 4,  month: 3,  day: 6,  hour: 3, minute: 39),
        .init(year: 2027, index: 5,  month: 3,  day: 21,  hour: 4, minute: 24),
        .init(year: 2027, index: 6,  month: 4,  day: 5,  hour: 8, minute: 17),
        .init(year: 2027, index: 7,  month: 4,  day: 20,  hour: 15, minute: 17),
        .init(year: 2027, index: 8,  month: 5,  day: 6,  hour: 1, minute: 25),
        .init(year: 2027, index: 9,  month: 5,  day: 21,  hour: 14, minute: 18),
        .init(year: 2027, index: 10,  month: 6,  day: 6,  hour: 5, minute: 25),
        .init(year: 2027, index: 11,  month: 6,  day: 21,  hour: 22, minute: 10),
        .init(year: 2027, index: 12,  month: 7,  day: 7,  hour: 15, minute: 37),
        .init(year: 2027, index: 13,  month: 7,  day: 23,  hour: 9, minute: 4),
        .init(year: 2027, index: 14,  month: 8,  day: 8,  hour: 1, minute: 26),
        .init(year: 2027, index: 15,  month: 8,  day: 23,  hour: 16, minute: 14),
        .init(year: 2027, index: 16,  month: 9,  day: 8,  hour: 4, minute: 28),
        .init(year: 2027, index: 17,  month: 9,  day: 23,  hour: 14, minute: 1),
        .init(year: 2027, index: 18,  month: 10,  day: 8,  hour: 20, minute: 17),
        .init(year: 2027, index: 19,  month: 10,  day: 23,  hour: 23, minute: 32),
        .init(year: 2027, index: 20,  month: 11,  day: 7,  hour: 23, minute: 38),
        .init(year: 2027, index: 21,  month: 11,  day: 22,  hour: 21, minute: 16),
        .init(year: 2027, index: 22,  month: 12,  day: 7,  hour: 16, minute: 37),
        .init(year: 2027, index: 23,  month: 12,  day: 22,  hour: 10, minute: 42),
        // 2028
        .init(year: 2028, index: 0,  month: 1,  day: 6,  hour: 3, minute: 54),
        .init(year: 2028, index: 1,  month: 1,  day: 20,  hour: 21, minute: 21),
        .init(year: 2028, index: 2,  month: 2,  day: 4,  hour: 15, minute: 31),
        .init(year: 2028, index: 3,  month: 2,  day: 19,  hour: 11, minute: 26),
        .init(year: 2028, index: 4,  month: 3,  day: 5,  hour: 9, minute: 24),
        .init(year: 2028, index: 5,  month: 3,  day: 20,  hour: 10, minute: 17),
        .init(year: 2028, index: 6,  month: 4,  day: 4,  hour: 14, minute: 3),
        .init(year: 2028, index: 7,  month: 4,  day: 19,  hour: 21, minute: 9),
        .init(year: 2028, index: 8,  month: 5,  day: 5,  hour: 7, minute: 12),
        .init(year: 2028, index: 9,  month: 5,  day: 20,  hour: 20, minute: 9),
        .init(year: 2028, index: 10,  month: 6,  day: 5,  hour: 11, minute: 16),
        .init(year: 2028, index: 11,  month: 6,  day: 21,  hour: 4, minute: 2),
        .init(year: 2028, index: 12,  month: 7,  day: 6,  hour: 21, minute: 30),
        .init(year: 2028, index: 13,  month: 7,  day: 22,  hour: 14, minute: 53),
        .init(year: 2028, index: 14,  month: 8,  day: 7,  hour: 7, minute: 21),
        .init(year: 2028, index: 15,  month: 8,  day: 22,  hour: 22, minute: 0),
        .init(year: 2028, index: 16,  month: 9,  day: 7,  hour: 10, minute: 22),
        .init(year: 2028, index: 17,  month: 9,  day: 22,  hour: 19, minute: 45),
        .init(year: 2028, index: 18,  month: 10,  day: 8,  hour: 2, minute: 8),
        .init(year: 2028, index: 19,  month: 10,  day: 23,  hour: 5, minute: 13),
        .init(year: 2028, index: 20,  month: 11,  day: 7,  hour: 5, minute: 27),
        .init(year: 2028, index: 21,  month: 11,  day: 22,  hour: 2, minute: 54),
        .init(year: 2028, index: 22,  month: 12,  day: 6,  hour: 22, minute: 24),
        .init(year: 2028, index: 23,  month: 12,  day: 21,  hour: 16, minute: 19),
        // 2029
        .init(year: 2029, index: 0,  month: 1,  day: 5,  hour: 9, minute: 41),
        .init(year: 2029, index: 1,  month: 1,  day: 20,  hour: 3, minute: 0),
        .init(year: 2029, index: 2,  month: 2,  day: 3,  hour: 21, minute: 20),
        .init(year: 2029, index: 3,  month: 2,  day: 18,  hour: 17, minute: 7),
        .init(year: 2029, index: 4,  month: 3,  day: 5,  hour: 15, minute: 17),
        .init(year: 2029, index: 5,  month: 3,  day: 20,  hour: 16, minute: 1),
        .init(year: 2029, index: 6,  month: 4,  day: 4,  hour: 19, minute: 58),
        .init(year: 2029, index: 7,  month: 4,  day: 20,  hour: 2, minute: 55),
        .init(year: 2029, index: 8,  month: 5,  day: 5,  hour: 13, minute: 7),
        .init(year: 2029, index: 9,  month: 5,  day: 21,  hour: 1, minute: 55),
        .init(year: 2029, index: 10,  month: 6,  day: 5,  hour: 17, minute: 9),
        .init(year: 2029, index: 11,  month: 6,  day: 21,  hour: 9, minute: 48),
        .init(year: 2029, index: 12,  month: 7,  day: 7,  hour: 3, minute: 22),
        .init(year: 2029, index: 13,  month: 7,  day: 22,  hour: 20, minute: 42),
        .init(year: 2029, index: 14,  month: 8,  day: 7,  hour: 13, minute: 11),
        .init(year: 2029, index: 15,  month: 8,  day: 23,  hour: 3, minute: 51),
        .init(year: 2029, index: 16,  month: 9,  day: 7,  hour: 16, minute: 11),
        .init(year: 2029, index: 17,  month: 9,  day: 23,  hour: 1, minute: 38),
        .init(year: 2029, index: 18,  month: 10,  day: 8,  hour: 7, minute: 58),
        .init(year: 2029, index: 19,  month: 10,  day: 23,  hour: 11, minute: 8),
        .init(year: 2029, index: 20,  month: 11,  day: 7,  hour: 11, minute: 16),
        .init(year: 2029, index: 21,  month: 11,  day: 22,  hour: 8, minute: 49),
        .init(year: 2029, index: 22,  month: 12,  day: 7,  hour: 4, minute: 13),
        .init(year: 2029, index: 23,  month: 12,  day: 21,  hour: 22, minute: 14),
        // 2030
        .init(year: 2030, index: 0,  month: 1,  day: 5,  hour: 15, minute: 30),
        .init(year: 2030, index: 1,  month: 1,  day: 20,  hour: 8, minute: 54),
        .init(year: 2030, index: 2,  month: 2,  day: 4,  hour: 3, minute: 8),
        .init(year: 2030, index: 3,  month: 2,  day: 18,  hour: 22, minute: 59),
        .init(year: 2030, index: 4,  month: 3,  day: 5,  hour: 21, minute: 3),
        .init(year: 2030, index: 5,  month: 3,  day: 20,  hour: 21, minute: 52),
        .init(year: 2030, index: 6,  month: 4,  day: 5,  hour: 1, minute: 41),
        .init(year: 2030, index: 7,  month: 4,  day: 20,  hour: 8, minute: 43),
        .init(year: 2030, index: 8,  month: 5,  day: 5,  hour: 18, minute: 46),
        .init(year: 2030, index: 9,  month: 5,  day: 21,  hour: 7, minute: 41),
        .init(year: 2030, index: 10,  month: 6,  day: 5,  hour: 22, minute: 44),
        .init(year: 2030, index: 11,  month: 6,  day: 21,  hour: 15, minute: 31),
        .init(year: 2030, index: 12,  month: 7,  day: 7,  hour: 8, minute: 55),
        .init(year: 2030, index: 13,  month: 7,  day: 23,  hour: 2, minute: 24),
        .init(year: 2030, index: 14,  month: 8,  day: 7,  hour: 18, minute: 47),
        .init(year: 2030, index: 15,  month: 8,  day: 23,  hour: 9, minute: 36),
        .init(year: 2030, index: 16,  month: 9,  day: 7,  hour: 21, minute: 52),
        .init(year: 2030, index: 17,  month: 9,  day: 23,  hour: 7, minute: 26),
        .init(year: 2030, index: 18,  month: 10,  day: 8,  hour: 13, minute: 45),
        .init(year: 2030, index: 19,  month: 10,  day: 23,  hour: 17, minute: 0),
        .init(year: 2030, index: 20,  month: 11,  day: 7,  hour: 17, minute: 8),
        .init(year: 2030, index: 21,  month: 11,  day: 22,  hour: 14, minute: 44),
        .init(year: 2030, index: 22,  month: 12,  day: 7,  hour: 10, minute: 7),
        .init(year: 2030, index: 23,  month: 12,  day: 22,  hour: 4, minute: 9),
        // 2031
        .init(year: 2031, index: 0,  month: 1,  day: 5,  hour: 21, minute: 23),
        .init(year: 2031, index: 1,  month: 1,  day: 20,  hour: 14, minute: 47),
        .init(year: 2031, index: 2,  month: 2,  day: 4,  hour: 8, minute: 58),
        .init(year: 2031, index: 3,  month: 2,  day: 19,  hour: 4, minute: 50),
        .init(year: 2031, index: 4,  month: 3,  day: 6,  hour: 2, minute: 51),
        .init(year: 2031, index: 5,  month: 3,  day: 21,  hour: 3, minute: 40),
        .init(year: 2031, index: 6,  month: 4,  day: 5,  hour: 7, minute: 28),
        .init(year: 2031, index: 7,  month: 4,  day: 20,  hour: 14, minute: 31),
        .init(year: 2031, index: 8,  month: 5,  day: 6,  hour: 0, minute: 35),
        .init(year: 2031, index: 9,  month: 5,  day: 21,  hour: 13, minute: 27),
        .init(year: 2031, index: 10,  month: 6,  day: 6,  hour: 4, minute: 35),
        .init(year: 2031, index: 11,  month: 6,  day: 21,  hour: 21, minute: 17),
        .init(year: 2031, index: 12,  month: 7,  day: 7,  hour: 14, minute: 48),
        .init(year: 2031, index: 13,  month: 7,  day: 23,  hour: 8, minute: 10),
        .init(year: 2031, index: 14,  month: 8,  day: 8,  hour: 0, minute: 42),
        .init(year: 2031, index: 15,  month: 8,  day: 23,  hour: 15, minute: 23),
        .init(year: 2031, index: 16,  month: 9,  day: 8,  hour: 3, minute: 50),
        .init(year: 2031, index: 17,  month: 9,  day: 23,  hour: 13, minute: 15),
        .init(year: 2031, index: 18,  month: 10,  day: 8,  hour: 19, minute: 42),
        .init(year: 2031, index: 19,  month: 10,  day: 23,  hour: 22, minute: 49),
        .init(year: 2031, index: 20,  month: 11,  day: 7,  hour: 23, minute: 5),
        .init(year: 2031, index: 21,  month: 11,  day: 22,  hour: 20, minute: 32),
        .init(year: 2031, index: 22,  month: 12,  day: 7,  hour: 16, minute: 2),
        .init(year: 2031, index: 23,  month: 12,  day: 22,  hour: 9, minute: 55),
        // 2032
        .init(year: 2032, index: 0,  month: 1,  day: 6,  hour: 3, minute: 16),
        .init(year: 2032, index: 1,  month: 1,  day: 20,  hour: 20, minute: 31),
        .init(year: 2032, index: 2,  month: 2,  day: 4,  hour: 14, minute: 48),
        .init(year: 2032, index: 3,  month: 2,  day: 19,  hour: 10, minute: 32),
        .init(year: 2032, index: 4,  month: 3,  day: 5,  hour: 8, minute: 40),
        .init(year: 2032, index: 5,  month: 3,  day: 20,  hour: 9, minute: 21),
        .init(year: 2032, index: 6,  month: 4,  day: 4,  hour: 13, minute: 17),
        .init(year: 2032, index: 7,  month: 4,  day: 19,  hour: 20, minute: 14),
        .init(year: 2032, index: 8,  month: 5,  day: 5,  hour: 6, minute: 25),
        .init(year: 2032, index: 9,  month: 5,  day: 20,  hour: 19, minute: 15),
        .init(year: 2032, index: 10,  month: 6,  day: 5,  hour: 10, minute: 28),
        .init(year: 2032, index: 11,  month: 6,  day: 21,  hour: 3, minute: 8),
        .init(year: 2032, index: 12,  month: 7,  day: 6,  hour: 20, minute: 40),
        .init(year: 2032, index: 13,  month: 7,  day: 22,  hour: 14, minute: 4),
        .init(year: 2032, index: 14,  month: 8,  day: 7,  hour: 6, minute: 32),
        .init(year: 2032, index: 15,  month: 8,  day: 22,  hour: 21, minute: 18),
        .init(year: 2032, index: 16,  month: 9,  day: 7,  hour: 9, minute: 37),
        .init(year: 2032, index: 17,  month: 9,  day: 22,  hour: 19, minute: 10),
        .init(year: 2032, index: 18,  month: 10,  day: 8,  hour: 1, minute: 30),
        .init(year: 2032, index: 19,  month: 10,  day: 23,  hour: 4, minute: 46),
        .init(year: 2032, index: 20,  month: 11,  day: 7,  hour: 4, minute: 54),
        .init(year: 2032, index: 21,  month: 11,  day: 22,  hour: 2, minute: 31),
        .init(year: 2032, index: 22,  month: 12,  day: 6,  hour: 21, minute: 53),
        .init(year: 2032, index: 23,  month: 12,  day: 21,  hour: 15, minute: 55),
    ]

    /// 按发生时间排好序的节气表（避免 nextTerm 每次 O(N log N) 重排）。
    /// entries 源数据本身是「年 × 年内节气序号 0-23」升序写入，Date 也单调递增，但
    /// 保险起见仍做一次排序并缓存，保证后续线性扫描的正确性。
    private static let sortedEntries: [TermEntry] = entries.sorted { $0.date < $1.date }

    // MARK: - 查询

    /// 距离 from 最近的、尚未到达交节时刻的节气。
    ///
    /// 注意：这里必须按“精确交节时刻”比较，而不是按日期比较。
    /// 例如某节气在今天 04:00 交节，今天 18:00 查询时应该返回下一个节气，
    /// 不能再次返回已经过去的今天节气。
    public static func nextTerm(from date: Date) -> (name: String, date: Date, daysRemaining: Int)? {
        let cal = Calendar(identifier: .gregorian)
        for entry in sortedEntries where entry.date >= date {
            let start = cal.startOfDay(for: date)
            let days = cal.dateComponents([.day], from: start, to: cal.startOfDay(for: entry.date)).day ?? 0
            return (entry.name, entry.date, days)
        }
        return nil
    }

    /// 返回当前时刻附近已经交节/即将交节的节气。
    /// 用于短生命周期 Live Activity：交节前后的一小段时间内都允许展示。
    public static func termAround(_ date: Date, window: TimeInterval = 2 * 60 * 60) -> (name: String, date: Date)? {
        guard window >= 0 else { return nil }
        let lower = date.addingTimeInterval(-window)
        let upper = date.addingTimeInterval(window)
        return sortedEntries
            .filter { $0.date >= lower && $0.date <= upper }
            .min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
            .map { ($0.name, $0.date) }
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

    /// 指定年份、指定节气序号（0-23）的精确时刻；无数据返回 nil。
    /// 用于立春换年柱等依赖节气交节的算法（2029+ 无数据时由调用方近似兜底）。
    public static func termDate(year: Int, index: Int) -> Date? {
        entries.first { $0.year == year && $0.index == index }?.date
    }

    /// 返回给定年份的所有节气。
    public static func terms(in year: Int) -> [(name: String, date: Date)] {
        entries.filter { $0.year == year }.sorted { $0.date < $1.date }
            .map { ($0.name, $0.date) }
    }
}
