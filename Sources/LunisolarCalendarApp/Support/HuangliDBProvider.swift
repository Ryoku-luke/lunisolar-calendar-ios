import Foundation

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
        case auspicious = "a"
    }
    let yi: [String]
    let ji: [String]
    let chong: String        // "冲" 字已剔除，读入时再拼回
    let sha: String          // "煞" 字已剔除，读入时再拼回
    let wuXing: String
    let shenWei: String
    let auspicious: Int      // 0 / 1
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
        // days: yyyy-MM-dd (UTC+0 同日？为了保持与生成时一致，用 Calendar(identifier:.gregorian) + local tz 算 day)
        // 实际：用生成时同一份 DateFormatter: Asia/Shanghai + yyyy-MM-dd
        static let shared = Cache()
        let root: HuangliDBRoot?
        let df: DateFormatter
        let rangeStart: Date?
        let rangeEnd: Date?   // 含当天 2028-12-31

        init() {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            df.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
            df.locale = Locale(identifier: "zh_CN_POSIX")
            self.df = df

            var loaded: HuangliDBRoot?
            if let url = Bundle.resources.url(forResource: "huangli_db", withExtension: "json") {
                if let data = try? Data(contentsOf: url) {
                    loaded = try? JSONDecoder().decode(HuangliDBRoot.self, from: data)
                }
            }
            self.root = loaded
            if let r = loaded, r.range.count == 2 {
                self.rangeStart = df.date(from: r.range[0])
                // rangeEnd = 最后一天 2028-12-31 endOfDay 的下一天开始，比较用 < rangeEndExclusive
                if let last = df.date(from: r.range[1]) {
                    let cal = Calendar(identifier: .gregorian)
                    self.rangeEnd = cal.date(byAdding: .day, value: 1, to: last)
                } else {
                    self.rangeEnd = nil
                }
            } else {
                self.rangeStart = nil
                self.rangeEnd = nil
            }
        }

        /// 给 date 生成离散库的 key
        func key(for date: Date) -> String {
            df.string(from: date)
        }

        /// 判断 date 是否落在离散库覆盖区间（按 Asia/Shanghai yyyy-MM-dd 对齐）
        func isInRange(_ date: Date) -> Bool {
            guard let s = rangeStart, let e = rangeEnd else { return false }
            return date >= s && date < e
        }
    }

    // MARK: - 主查询入口

    /// 查询给定公历日期的黄历，返回 resolved 结果（含来源）
    public static func resolve(date: Date) -> Resolved {
        let cache = Cache.shared
        let normDate = Calendar(identifier: .gregorian).startOfDay(for: date)
        let lunar = ChineseCalendar.lunarDateSafe(from: normDate)
        // 越界：农历数据就没有，直接给 nil（与算法生成器一致）
        guard let lunar else {
            return Resolved(huangliDay: nil, source: .algorithm)
        }

        if cache.isInRange(normDate), let entry = cache.root?.days[cache.key(for: normDate)] {
            let day = HuangliDay(
                date: normDate,
                lunar: lunar,
                yi: entry.yi,
                ji: entry.ji,
                chong: "冲\(entry.chong)",
                sha: "煞\(entry.sha)",
                wuXing: entry.wuXing,
                shenWei: entry.shenWei,
                isAuspicious: entry.auspicious == 1
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
        return "离散黄历库 v\(r.version)：\(r.range[0]) ~ \(r.range[1])，共 \(r.count) 条"
    }
}
