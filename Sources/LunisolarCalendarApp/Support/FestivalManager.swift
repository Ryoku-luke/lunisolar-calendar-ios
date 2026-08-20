import Foundation

// MARK: - 节日类型 & 模型

public enum FestivalKind: Sendable {
    case solar          // 公历固定日 (如 10-01 国庆)
    case lunar          // 农历固定日 (如 正月初一 春节)
}

public struct Festival: Equatable, Hashable, Sendable {
    public let name: String
    public let emoji: String
    public let kind: FestivalKind
    /// solar: (month, day); lunar: (month, day, isLeap)
    public let month: Int
    public let day: Int
    public let isLeap: Bool
    /// 主题色配色（吉祥红=春节、金黄=中秋、青绿=端午...）
    public let accentHex: String

    public init(name: String, emoji: String, kind: FestivalKind, month: Int, day: Int,
                isLeap: Bool = false, accentHex: String = "#C41A1A") {
        self.name = name
        self.emoji = emoji
        self.kind = kind
        self.month = month
        self.day = day
        self.isLeap = isLeap
        self.accentHex = accentHex
    }
}

// MARK: - 节日管理器

public enum FestivalManager: Sendable {

    // MARK: - 内置节日表

    /// 公历节日
    public static let solarFestivals: [Festival] = [
        Festival(name: "元旦", emoji: "🎉", kind: .solar, month: 1,  day: 1,  accentHex: "#D7282E"),
        Festival(name: "情人节", emoji: "💝", kind: .solar, month: 2,  day: 14, accentHex: "#E91E63"),
        Festival(name: "妇女节", emoji: "🌷", kind: .solar, month: 3,  day: 8,  accentHex: "#EC407A"),
        Festival(name: "植树节", emoji: "🌳", kind: .solar, month: 3,  day: 12, accentHex: "#43A047"),
        Festival(name: "劳动节", emoji: "👷", kind: .solar, month: 5,  day: 1,  accentHex: "#FB8C00"),
        Festival(name: "青年节", emoji: "🎓", kind: .solar, month: 5,  day: 4,  accentHex: "#1E88E5"),
        Festival(name: "儿童节", emoji: "🎈", kind: .solar, month: 6,  day: 1,  accentHex: "#FDD835"),
        Festival(name: "建党节", emoji: "🚩", kind: .solar, month: 7,  day: 1,  accentHex: "#C41A1A"),
        Festival(name: "建军节", emoji: "🎖️", kind: .solar, month: 8,  day: 1,  accentHex: "#2E7D32"),
        Festival(name: "教师节", emoji: "📚", kind: .solar, month: 9,  day: 10, accentHex: "#5E35B1"),
        Festival(name: "国庆节", emoji: "🇨🇳", kind: .solar, month: 10, day: 1,  accentHex: "#D7282E"),
        Festival(name: "万圣节", emoji: "🎃", kind: .solar, month: 10, day: 31, accentHex: "#FB8C00"),
        Festival(name: "圣诞节", emoji: "🎄", kind: .solar, month: 12, day: 25, accentHex: "#2E7D32"),
    ]

    /// 农历节日（按农历月日，每年通过 lunarDate 映射到公历）
    public static let lunarFestivals: [Festival] = [
        Festival(name: "春节",   emoji: "🧧", kind: .lunar, month: 1,  day: 1,  accentHex: "#C41A1A"),
        Festival(name: "元宵节", emoji: "🏮", kind: .lunar, month: 1,  day: 15, accentHex: "#E65100"),
        Festival(name: "龙抬头", emoji: "🐉", kind: .lunar, month: 2,  day: 2,  accentHex: "#1565C0"),
        Festival(name: "端午节", emoji: "🐲", kind: .lunar, month: 5,  day: 5,  accentHex: "#2E7D32"),
        Festival(name: "七夕节", emoji: "💘", kind: .lunar, month: 7,  day: 7,  accentHex: "#D81B60"),
        Festival(name: "中元节", emoji: "🕯️", kind: .lunar, month: 7,  day: 15, accentHex: "#6A1B9A"),
        Festival(name: "中秋节", emoji: "🥮", kind: .lunar, month: 8,  day: 15, accentHex: "#F9A825"),
        Festival(name: "重阳节", emoji: "🌾", kind: .lunar, month: 9,  day: 9,  accentHex: "#F57C00"),
        Festival(name: "腊八节", emoji: "🍲", kind: .lunar, month: 12, day: 8,  accentHex: "#795548"),
        Festival(name: "除夕",   emoji: "🎆", kind: .lunar, month: 12, day: 30, accentHex: "#C41A1A"),
    ]

    // MARK: - 查询接口

    /// 返回给定公历日期上重合的所有节日（同日可能多个）
    public static func festivals(on date: Date) -> [Festival] {
        var result: [Festival] = []

        let cal = Calendar(identifier: .gregorian)
        let norm = cal.startOfDay(for: date)
        let ymd = cal.dateComponents([.year, .month, .day], from: norm)
        guard let m = ymd.month, let d = ymd.day else { return result }

        // 1. 公历节日（精确匹配 month+day）
        for f in solarFestivals where f.month == m && f.day == d {
            result.append(f)
        }

        // 2. 农历节日（通过农历月日匹配，注意除夕特殊：若除夕当天非30，则取对应年最后一天）
        if let lunar = ChineseCalendar.lunarDateSafe(from: norm) {
            for f in lunarFestivals {
                if f.name == "除夕" {
                    if isLunarLastDayOfYear(lunar: lunar, in: norm) {
                        result.append(f)
                    }
                } else if lunar.month == f.month && lunar.day == f.day && !lunar.isLeapMonth {
                    result.append(f)
                }
            }
        }

        return result
    }

    /// 是否为"大节日"（决定是否触发主题色 banner）
    public static func primaryFestival(on date: Date) -> Festival? {
        let all = festivals(on: date)
        // 按优先级：农历节日优先于公历节日
        let primaryNames: Set<String> = [
            "春节","元宵","端午","七夕","中秋","重阳","除夕",
            "国庆节","元旦","劳动节","儿童节"
        ]
        return all.first { primaryNames.contains($0.name) } ?? all.first
    }

    /// 节日主题色（吉祥红/金黄/青绿...），无节日返回 nil
    public static func accentColorHex(on date: Date) -> String? {
        primaryFestival(on: date)?.accentHex
    }

    // MARK: - 辅助

    /// 判断给定农历日期是否为除夕（农历年最后一天）
    private static func isLunarLastDayOfYear(lunar: LunarDate, in date: Date) -> Bool {
        guard lunar.month == 12 else { return false }
        // 农历十二月三十 或 该月只有29天（即廿九为最后一天）
        let daysIn12 = ChineseCalendar.daysInLunarMonth(year: lunar.year, month: 12, isLeap: false)
        return daysIn12 > 0 && lunar.day == daysIn12
    }
}

// MARK: - Color 从 Hex 构造辅助（跨平台）

#if canImport(SwiftUI)
import SwiftUI

public extension Color {
    /// 十六进制颜色构造 (支持 #RRGGBB)
    init(hex: String) {
        let hx = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        Scanner(string: hx).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }

    /// 金色 (中秋/重阳节日点缀)
    static var festiveGold: Color {
        Color(red: 0.94, green: 0.73, blue: 0.15)
    }
}
#endif
