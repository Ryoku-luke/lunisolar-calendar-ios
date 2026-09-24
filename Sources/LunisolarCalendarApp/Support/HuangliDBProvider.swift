import Foundation
import LunarCore

// MARK: - 离散黄历条目模型 (compact JSON keys)

/// huangli_db.json 单天的内部紧凑结构
internal struct HuangliDBEntry: Decodable {
    enum CodingKeys: String, CodingKey {
        case yi = "y"
        case ji = "j"
        case chong = "c"
        case sha = "s"
        case wuXing = "w"
        case shenWei = "g"
    }
    let yi: [String]
    let ji: [String]
    let chong: String        // "冲" 字已剔除，读入时再拼回
    let sha: String          // "煞" 字已剔除，读入时再拼回
    let wuXing: String
    let shenWei: String
}

/// 离散黄历数据库的顶层容器
internal struct HuangliDBRoot: Decodable {
    enum CodingKeys: String, CodingKey {
        case version = "v"
        case range = "range"
        case count = "count"
        case days = "days"
    }
    let version: Int
    let range: [String]
    let count: Int
    let days: [String: HuangliDBEntry]
}

// MARK: - Provider（Bundle 资源加载 + O(1) 查询 + fallback）

/// 黄历离散数据库提供者：
/// 1) 内置 2024-01-01 ~ 2028-12-31 的 huangli_db.json (385KB)，保证最近 5 年"准"
/// 2) 若资源加载失败或日期不在区间，调用 HuangliGenerator.algorithmGenerate() 走算法 fallback
/// 3) 只读单例 + 延迟加载，首次访问才 JSON 解码 (~3ms)
public enum HuangliDBProvider {

    /// 查询结果来源（用于诊断/测试区分 DB 命中 or 算法）
    public enum Source: Equatable, Hashable, Sendable {
        case discreteDB     // 命中离散数据库
        case algorithm      // 走算法兜底
    }

    /// 查询结果
    public struct Resolved: Equatable, Hashable, Sendable {
        public let huangliDay: HuangliDay?   // 日期越界(1900前/2100后)可能为 nil
        public let source: Source
    }

    // MARK: - 懒加载 Bundle 数据库

    private struct Cache: @unchecked Sendable {
        static let shared = Cache()
        let root: HuangliDBRoot?
        /// 覆盖区间端点（含端点，yyyy-MM-dd）。零填充字符串比较即时间顺序比较，
        /// 与设备时区无关——避免海外时区在边界日被误判越界而静默退化到算法。
        let rangeStartKey: String?
        let rangeEndKey: String?

        init() {
            var loaded: HuangliDBRoot?
            if let url = Bundle.resources.url(forResource: "huangli_db", withExtension: "json") {
                if let data = try? Data(contentsOf: url) {
                    loaded = try? JSONDecoder().decode(HuangliDBRoot.self, from: data)
                }
            }
            self.root = loaded
            self.rangeStartKey = loaded?.range.first
            self.rangeEndKey = (loaded?.range.count ?? 0) >= 2 ? loaded?.range.last : loaded?.range.first
        }

        /// key 字符串是否落在覆盖区间（P3 修复保留：range 被外部篡改为空时安全返回 false）
        func isInRange(_ key: String) -> Bool {
            guard let s = rangeStartKey, let e = rangeEndKey else { return false }
            return key >= s && key <= e
        }
    }

    /// 用户本地日历日的离散库 key：yyyy-MM-dd（公历 + 调用方日历的时区 + POSIX 数字）。
    ///
    /// 历史缺陷（docs #7 时区统一）：曾用 Asia/Shanghai 格式化"设备本地午夜"这一时刻，
    /// UTC+13 设备（如 Pacific/Auckland）会把本地 02-04 映射成 02-03，取到前一天的宜忌；
    /// 边界日还会因时刻比较被误判越界。改为直接取日历分量后与设备时区完全解耦。
    static func dayKey(for date: Date, calendar: Calendar) -> String {
        let y = calendar.component(.year, from: date)
        let m = calendar.component(.month, from: date)
        let d = calendar.component(.day, from: date)
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    // MARK: - 主查询入口

    /// 查询给定公历日期的黄历，返回 resolved 结果（含来源）
    public static func resolve(date: Date) -> Resolved {
        let cache = Cache.shared
        // 用户"点选的那一天"按设备时区日界取整（docs #7：用户数据走 user 口径）；
        // DB key 由该日的日历分量生成，与设备时区解耦（海外设备不再错位一天）
        let userCalendar = Calendar(identifier: .gregorian)
        let normDate = userCalendar.startOfDay(for: date)
        let lunar = ChineseCalendar.lunarDateSafe(from: normDate)
        // 越界：农历数据就没有，直接给 nil（与算法生成器一致）
        guard let lunar else {
            return Resolved(huangliDay: nil, source: .algorithm)
        }

        let key = dayKey(for: normDate, calendar: userCalendar)
        if cache.isInRange(key), let entry = cache.root?.days[key] {
            let day = HuangliDay(
                date: normDate,
                lunar: lunar,
                yi: entry.yi,
                ji: entry.ji,
                chong: "冲\(entry.chong)",
                sha: "煞\(entry.sha)",
                wuXing: entry.wuXing,
                shenWei: entry.shenWei
            )
            return Resolved(huangliDay: day, source: .discreteDB)
        }

        // fallback: 算法生成
        let day = HuangliGenerator.algorithmGenerate(for: normDate, lunar: lunar)
        return Resolved(huangliDay: day, source: .algorithm)
    }

    /// 覆盖范围描述（用于 UI 展示/诊断）
    public static var coverageDescription: String {
        let c = Cache.shared
        guard let r = c.root else {
            return "离散黄历库未加载（将走算法兜底）"
        }
        // P3 修复：JSON 被外部篡改/损坏时 r.range.count 可能 < 2，
        //   旧代码直接 r.range[1] 会触发 Swift Array index out of range precondition
        //   → 整个 SettingsView 进程崩溃。改用 first/last 安全访问。
        let start = r.range.first ?? "未知"
        let end = r.range.count >= 2 ? r.range.last! : start
        return "离散黄历库 v\(r.version)：\(start) ~ \(end)，共 \(r.count) 条"
    }
}

// MARK: - HuangliGenerator extension（离散库 + 算法 fallback）
// 放在 App target 里，因为 LunarCore 没有离散库解析能力
extension HuangliGenerator {
    /// 基于公历日期生成黄历
    /// 策略：优先查"离散黄历数据库"（2024-2028，内置 huangli_db.json），命中则直接用
    /// 未命中（资源缺失/区间外）时走算法推导作为兜底
    public static func generate(for date: Date) -> HuangliDay {
        let resolved = HuangliDBProvider.resolve(date: date)
        if let day = resolved.huangliDay {
            return day
        }
        // 越界时，给一个尽量合理的兜底（lunar 使用占位值）
        let safeLunar = ChineseCalendar.lunarDateSafe(from: date) ?? LunarDate(
            year: 0, month: 1, day: 1, isLeapMonth: false
        )
        return algorithmGenerate(for: date, lunar: safeLunar)
    }
}
