import Foundation
import LunarCore

// MARK: - 节日类型 & 模型

public enum FestivalKind: Sendable {
    case solar          // 公历固定日 (如 10-01 国庆)
    case lunar          // 农历固定日 (如 正月初一 春节)
    case solarTerm      // 节气（公历交节日浮动，如 清明 4/4-4/6）
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

    /// 本地化节日名：name 保留中文作为 Localizable key 源，
    /// 显示层按系统语言取翻译（春节→Spring Festival / 春節 / 春節）
    // Linux Foundation 无 String.LocalizationValue，降级返回原始中文 key
    public var localizedName: String {
        #if !os(Linux)
        return String(localized: String.LocalizationValue(name))
        #else
        return name
        #endif
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

    // MARK: - 查询索引（性能）
    //
    // 月历每屏 42 格、横滑时 body 可能高频重算，若每次线性遍历 13+10 个节日定义，
    // 每屏要做上千次数组比较。这里按「月*100+日」建静态字典，单次查询 O(1)；
    // 除夕依赖"当年最后一天"动态判断，单独存放。
    // static let 由运行时 dispatch_once 惰性初始化，线程安全且只构建一次。

    private static let gregorian = Calendar(identifier: .gregorian)
    /// 公历节日索引：key = month*100+day（同日可能多个，保留数组与原顺序）
    private static let solarByMD: [Int: [Festival]] = {
        var dict: [Int: [Festival]] = [:]
        for f in solarFestivals {
            dict[f.month * 100 + f.day, default: []].append(f)
        }
        return dict
    }()
    /// 农历节日索引（除夕除外，它需要按年最后一天动态判定）
    private static let lunarByMD: [Int: [Festival]] = {
        var dict: [Int: [Festival]] = [:]
        for f in lunarFestivals where f.name != "除夕" {
            dict[f.month * 100 + f.day, default: []].append(f)
        }
        return dict
    }()
    private static let chuxi: Festival? = lunarFestivals.first { $0.name == "除夕" }

    // MARK: - 查询接口

    /// 返回给定公历日期上重合的所有节日（同日可能多个）
    public static func festivals(on date: Date) -> [Festival] {
        let norm = gregorian.startOfDay(for: date)
        let lunar = ChineseCalendar.lunarDateSafe(from: norm)
        return festivals(on: norm, lunar: lunar)
    }

    /// 接受预计算的 LunarDate，避免调用方重复进行农历转换（性能优化）
    public static func festivals(on date: Date, lunar: LunarDate?) -> [Festival] {
        let norm = gregorian.startOfDay(for: date)
        let ymd = gregorian.dateComponents([.year, .month, .day], from: norm)
        guard let m = ymd.month, let d = ymd.day else { return [] }

        // 1. 公历节日：O(1) 字典查 month+day
        var result: [Festival] = solarByMD[m * 100 + d] ?? []

        // 2. 农历节日：月日字典直查；除夕按"当年最后一天"特殊判断。
        //    普通农历节日闰月不过节；除夕判定本身基于"年内最后一天"，与旧实现一致不查闰月标记。
        //    P2-1 配套：lunar 为越界占位（.unsupported）时跳过农历节日，
        //    避免 2100 年后翻月误把"正月初一"当作春节。
        if let lunar, !lunar.isUnsupported {
            if !lunar.isLeapMonth, let matches = lunarByMD[lunar.month * 100 + lunar.day] {
                result.append(contentsOf: matches)
            }
            if let chuxi, isLunarLastDayOfYear(lunar: lunar, in: norm) {
                result.append(chuxi)
            }
        }

        // 3. 节气节日（P2-2）：当天恰逢节气交节时标注（如清明/冬至/立春）。
        //    随 SolarTermProvider 数据（2025-2028）联动；2029+ 无数据时不显示。
        if let term = SolarTermProvider.termOn(norm) {
            result.append(Festival(
                name: term, emoji: "🌿", kind: .solarTerm,
                month: m, day: d, accentHex: "#15803D"
            ))
        }

        return result
    }

    /// 是否为"大节日"（决定是否触发主题色 banner）
    public static func primaryFestival(on date: Date) -> Festival? {
        let all = festivals(on: date)
        return primaryFrom(all)
    }

    /// 接受预计算 LunarDate 的重载，避免 WidgetProvider 等调用方重复农历转换。
    /// P2 修复：旧 primaryFestival(on:) 只接受 date，内部调 festivals(on:) 做农历转换；
    ///   WidgetProvider 先调 festivals(on: now) 再调 primaryFestival(on: now) → 重复转换。
    ///   新增 lunar 重载后 WidgetProvider 可复用同一次转换结果。
    public static func primaryFestival(on date: Date, lunar: LunarDate?) -> Festival? {
        let all = festivals(on: date, lunar: lunar)
        return primaryFrom(all)
    }

    /// 从节日列表中按优先级选出主节日
    private static func primaryFrom(_ all: [Festival]) -> Festival? {
        // 按优先级：农历节日优先于公历节日。
        // P2 修复：旧 primaryNames 用了 "元宵/端午/七夕/中秋/重阳"（无"节"后缀），
        //   但 lunarFestivals 里的 name 全部带"节"后缀（"元宵节/端午节/..."），
        //   `primaryNames.contains("元宵节")` 永远返回 false → 这些农历主节日
        //   不触发 banner / 主题色 override，仅"除夕/春节"因字面相同侥幸命中。
        //   修复：primaryNames 与 Festival.name 字面严格对齐。
        let primaryNames: Set<String> = [
            "春节","元宵节","端午节","七夕节","中秋节","重阳节","除夕",
            "国庆节","元旦","劳动节","儿童节"
        ]
        return all.first { primaryNames.contains($0.name) } ?? all.first
    }

    /// 节日主题色（吉祥红/金黄/青绿...），无节日返回 nil
    public static func accentColorHex(on date: Date) -> String? {
        primaryFestival(on: date)?.accentHex
    }

    /// 接受预计算 LunarDate 的重载
    public static func accentColorHex(on date: Date, lunar: LunarDate?) -> String? {
        primaryFestival(on: date, lunar: lunar)?.accentHex
    }

    // MARK: - 辅助

    /// 判断给定农历日期是否为除夕（农历年最后一天）
    private static func isLunarLastDayOfYear(lunar: LunarDate, in date: Date) -> Bool {
        // P3 修复：旧代码只 guard lunar.month == 12，未排除闰十二月。
        //   闰十二月的最后一天不是除夕（除夕是正常十二月的最后一天）。
        //   闰十二月极其罕见（上一个 1984 年），但逻辑必须正确。
        guard lunar.month == 12, !lunar.isLeapMonth else { return false }
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
}
#endif
