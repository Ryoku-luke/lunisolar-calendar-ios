import Foundation

// MARK: - 农历数据加载器（资源化 JSON + 内置 fallback）

/// 农历数据提供器：优先从 Bundle JSON 加载，失败时回退到内置数据
enum LunarDataProvider {
    /// 从 lunar_calendar.json 加载，失败时使用内置 fallback
    static let lunarInfo: [UInt32] = loadLunarInfo()

    private static func loadLunarInfo() -> [UInt32] {
        // 1. 尝试从 Bundle 加载 JSON
        if let url = Bundle.module.url(forResource: "lunar_calendar", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let hexStrings = json["data"] as? [String] {
            let values = hexStrings.compactMap {
                let hex = $0.hasPrefix("0x") ? String($0.dropFirst(2)) : $0
                return UInt32(hex, radix: 16)
            }
            if values.count == 201 { return values }
        }
        // 2. Fallback：内置数据（保证即使 JSON 加载失败也能工作）
        return fallbackLunarInfo
    }

    /// 内置 fallback 数据（与 lunar_calendar.json 内容一致）
    private static let fallbackLunarInfo: [UInt32] = [
        0x04bd8,0x04ae0,0x0a570,0x054d5,0x0d260,0x0d950,0x16554,0x056a0,0x09ad0,0x055d2,
        0x04ae0,0x0a5b6,0x0a4d0,0x0d250,0x1d255,0x0b540,0x0d6a0,0x0ada2,0x095b0,0x14977,
        0x04970,0x0a4b0,0x0b4b5,0x06a50,0x06d40,0x1ab54,0x02b60,0x09570,0x052f2,0x04970,
        0x06566,0x0d4a0,0x0ea50,0x06e95,0x05ad0,0x02b60,0x186e3,0x092e0,0x1c8d7,0x0c950,
        0x0d4a0,0x1d8a6,0x0b550,0x056a0,0x1a5b4,0x025d0,0x092d0,0x0d2b2,0x0a950,0x0b557,
        0x06ca0,0x0b550,0x15355,0x04da0,0x0a5b0,0x14573,0x052b0,0x0a9a8,0x0e950,0x06aa0,
        0x0aea6,0x0ab50,0x04b60,0x0aae4,0x0a570,0x05260,0x0f263,0x0d950,0x05b57,0x056a0,
        0x096d0,0x04dd5,0x04ad0,0x0a4d0,0x0d4d4,0x0d250,0x0d558,0x0b540,0x0b6a0,0x195a6,
        0x095b0,0x049b0,0x0a974,0x0a4b0,0x0b27a,0x06a50,0x06d40,0x0af46,0x0ab60,0x09570,
        0x04af5,0x04970,0x064b0,0x074a3,0x0ea50,0x06b58,0x055c0,0x0ab60,0x096d5,0x092e0,
        0x0c960,0x0d954,0x0d4a0,0x0da50,0x07552,0x056a0,0x0abb7,0x025d0,0x092d0,0x0cab5,
        0x0a950,0x0b4a0,0x0baa4,0x0ad50,0x055d9,0x04ba0,0x0a5b0,0x15176,0x052b0,0x0a930,
        0x07954,0x06aa0,0x0ad50,0x05b52,0x04b60,0x0a6e6,0x0a4e0,0x0d260,0x0ea65,0x0d530,
        0x05aa0,0x076a3,0x096d0,0x04afb,0x04ad0,0x0a4d0,0x1d0b6,0x0d250,0x0d520,0x0dd45,
        0x0b5a0,0x056d0,0x055b2,0x049b0,0x0a577,0x0a4b0,0x0aa50,0x1b255,0x06d20,0x0ada0,
        0x14b63,0x09370,0x049f8,0x04970,0x064b0,0x168a6,0x0ea50,0x06b20,0x1a6c4,0x0aae0,
        0x0a2e0,0x0d2e3,0x0c960,0x0d557,0x0d4a0,0x0da50,0x05d55,0x056a0,0x0a6d0,0x055d4,
        0x052d0,0x0a9b8,0x0a950,0x0b4a0,0x0b6a6,0x0ad50,0x055a0,0x0aba4,0x0a5b0,0x052b0,
        0x0b273,0x06930,0x07337,0x06aa0,0x0ad50,0x14b55,0x04b60,0x0a570,0x054e4,0x0d160,
        0x0e968,0x0d520,0x0daa0,0x16aa6,0x056d0,0x04ae0,0x0a9d4,0x0a2d0,0x0d150,0x0f252,
        0x0d520
    ]
}

// MARK: - 农历日期模型

public struct LunarDate: Equatable, Hashable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int
    public let isLeapMonth: Bool

    public var yearGanZhi: String { ChineseCalendar.ganZhiOfYear(year) }
    public var yearAnimal: String { ChineseCalendar.zodiacOfYear(year) }
    public var monthName: String { ChineseCalendar.lunarMonthName(month, isLeap: isLeapMonth) }
    public var dayName: String { ChineseCalendar.lunarDayName(day) }

    public var displayString: String {
        "\(yearGanZhi)年\(monthName)\(dayName)"
    }

    public var shortDisplayString: String {
        if day == 1 {
            return monthName
        }
        return dayName
    }
}

// MARK: - 天干地支生肖计算

public enum ChineseCalendar {

    public static let tianGan = ["甲","乙","丙","丁","戊","己","庚","辛","壬","癸"]
    public static let diZhi = ["子","丑","寅","卯","辰","巳","午","未","申","酉","戌","亥"]
    public static let zodiacs = ["鼠","牛","虎","兔","龙","蛇","马","羊","猴","鸡","狗","猪"]
    public static let lunarMonthNames = ["正","二","三","四","五","六","七","八","九","十","冬","腊"]
    public static let lunarDayNames = [
        "初一","初二","初三","初四","初五","初六","初七","初八","初九","初十",
        "十一","十二","十三","十四","十五","十六","十七","十八","十九","二十",
        "廿一","廿二","廿三","廿四","廿五","廿六","廿七","廿八","廿九","三十"
    ]

    /// 支持的农历年份范围
    public static let minYear = 1900
    public static let maxYear = 2100

    // MARK: - 基础信息提取

    /// 获取该年闰月月份 (0=无闰月)
    public static func leapMonth(of year: Int) -> Int {
        guard year >= minYear, year <= maxYear else { return 0 }
        return Int(LunarDataProvider.lunarInfo[year - minYear] & 0xF)
    }

    /// 获取该年闰月天数
    public static func leapDays(of year: Int) -> Int {
        if leapMonth(of: year) != 0 {
            return (LunarDataProvider.lunarInfo[year - minYear] & 0x10000) != 0 ? 30 : 29
        }
        return 0
    }

    /// 获取该年农历总天数
    public static func daysInLunarYear(_ year: Int) -> Int {
        guard year >= minYear, year <= maxYear else { return 354 }
        var sum = 348 // 12 * 29 天
        let info = LunarDataProvider.lunarInfo[year - minYear]
        var mask: UInt32 = 0x8000
        for _ in 0..<12 {
            if info & mask != 0 { sum += 1 }
            mask >>= 1
        }
        return sum + leapDays(of: year)
    }

    /// 获取该农历月的天数
    public static func daysInLunarMonth(year: Int, month: Int, isLeap: Bool) -> Int {
        guard year >= minYear, year <= maxYear, month >= 1, month <= 12 else { return 30 }
        if isLeap && leapMonth(of: year) == month {
            return leapDays(of: year)
        }
        let mask: UInt32 = 0x10000 >> month
        return (LunarDataProvider.lunarInfo[year - minYear] & mask) != 0 ? 30 : 29
    }

    // MARK: - 公历转农历

    private static let baseDate: Date = {
        let cal = Calendar(identifier: .gregorian)
        var comps = DateComponents()
        comps.year = 1900
        comps.month = 1
        comps.day = 31
        comps.hour = 0
        comps.minute = 0
        comps.second = 0
        return cal.date(from: comps) ?? Date()
    }()

    /// 检查日期是否在支持范围内
    public static func isSupported(_ date: Date) -> Bool {
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year], from: cal.startOfDay(for: date))
        let y = comps.year ?? 0
        return y >= minYear && y <= maxYear
    }

    /// 公历 Date 转农历 LunarDate（安全版，越界返回 nil）
    public static func lunarDateSafe(from date: Date) -> LunarDate? {
        guard isSupported(date) else { return nil }
        return lunarDate(from: date)
    }

    /// 公历 Date 转农历 LunarDate（越界降级为公历镜像）
    public static func lunarDate(from date: Date) -> LunarDate {
        let cal = Calendar(identifier: .gregorian)
        let normalized = cal.startOfDay(for: date)
        let baseNorm = cal.startOfDay(for: baseDate)

        let offsetComps = cal.dateComponents([.day], from: baseNorm, to: normalized)
        var offset = offsetComps.day ?? 0

        if offset < 0 {
            let gregorian = cal.dateComponents([.year, .month, .day], from: date)
            return LunarDate(
                year: gregorian.year ?? minYear,
                month: gregorian.month ?? 1,
                day: gregorian.day ?? 1,
                isLeapMonth: false
            )
        }

        var year = minYear
        while year <= maxYear {
            let daysInYear = daysInLunarYear(year)
            if offset < daysInYear { break }
            offset -= daysInYear
            year += 1
        }
        if year > maxYear {
            let gregorian = cal.dateComponents([.year, .month, .day], from: date)
            return LunarDate(
                year: min(gregorian.year ?? maxYear, maxYear),
                month: gregorian.month ?? 1,
                day: gregorian.day ?? 1,
                isLeapMonth: false
            )
        }

        let leapMonthIndex = leapMonth(of: year)
        var isLeap = false
        var month = 1
        var found = false

        while month <= 12 {
            let daysOfNormalMonth = daysInLunarMonth(year: year, month: month, isLeap: false)

            if offset < daysOfNormalMonth {
                isLeap = false
                found = true
                break
            }
            offset -= daysOfNormalMonth

            if leapMonthIndex > 0 && month == leapMonthIndex && !isLeap {
                let daysOfLeapMonth = leapDays(of: year)
                if offset < daysOfLeapMonth {
                    isLeap = true
                    found = true
                    break
                }
                offset -= daysOfLeapMonth
            }

            month += 1
        }

        if !found {
            month = 12
            isLeap = false
        }

        let day = offset + 1
        return LunarDate(
            year: year,
            month: month,
            day: day,
            isLeapMonth: isLeap
        )
    }

    // MARK: - 农历转公历（新增：反向查询）

    /// 农历转公历：给定农历年月日，返回公历 Date（失败返回 nil）
    public static func solarDate(fromLunar year: Int, month: Int, day: Int, isLeap: Bool) -> Date? {
        guard year >= minYear, year <= maxYear, month >= 1, month <= 12, day >= 1, day <= 30 else { return nil }
        // 闰月非法：请求闰月但该年无此闰月
        let leapM = leapMonth(of: year)
        if isLeap && leapM != month { return nil }

        let cal = Calendar(identifier: .gregorian)
        var baseComps = DateComponents()
        baseComps.year = 1900; baseComps.month = 1; baseComps.day = 31
        guard var date = cal.date(from: baseComps) else { return nil }

        // 逐年累加天数
        for y in minYear..<year {
            date = cal.date(byAdding: .day, value: daysInLunarYear(y), to: date) ?? date
        }

        // 逐月累加天数
        for m in 1..<month {
            date = cal.date(byAdding: .day, value: daysInLunarMonth(year: year, month: m, isLeap: false), to: date) ?? date
            // 如果该月有闰月且不是目标闰月，加上闰月天数
            if leapM == m && !(isLeap && m == month) {
                date = cal.date(byAdding: .day, value: leapDays(of: year), to: date) ?? date
            }
        }

        // 如果目标是闰月，需要先跳过普通月
        if isLeap && leapM == month {
            date = cal.date(byAdding: .day, value: daysInLunarMonth(year: year, month: month, isLeap: false), to: date) ?? date
        }

        // 加上天数
        date = cal.date(byAdding: .day, value: day - 1, to: date) ?? date
        return date
    }

    // MARK: - 显示辅助

    public static func ganZhiOfYear(_ year: Int) -> String {
        let ganIndex = (year - 4) % 10
        let zhiIndex = (year - 4) % 12
        let gan = tianGan[(ganIndex + 10) % 10]
        let zhi = diZhi[(zhiIndex + 12) % 12]
        return "\(gan)\(zhi)"
    }

    public static func zodiacOfYear(_ year: Int) -> String {
        let index = (year - 4) % 12
        return zodiacs[(index + 12) % 12]
    }

    public static func lunarMonthName(_ month: Int, isLeap: Bool) -> String {
        let m = abs(month)
        guard m >= 1, m <= 12 else { return "" }
        let name = lunarMonthNames[m - 1]
        return isLeap ? "闰\(name)月" : "\(name)月"
    }

    public static func lunarDayName(_ day: Int) -> String {
        guard day >= 1, day <= 30 else { return "" }
        return lunarDayNames[day - 1]
    }
}

// MARK: - Date 扩展

public extension Date {
    var lunar: LunarDate {
        ChineseCalendar.lunarDate(from: self)
    }

    /// 安全版农历（越界返回 nil）
    var lunarSafe: LunarDate? {
        ChineseCalendar.lunarDateSafe(from: self)
    }

    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    func addingDays(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
    }

    func addingMonths(_ months: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: months, to: self) ?? self
    }

    var year: Int { Calendar.current.component(.year, from: self) }
    var month: Int { Calendar.current.component(.month, from: self) }
    var day: Int { Calendar.current.component(.day, from: self) }
    var weekday: Int { Calendar.current.component(.weekday, from: self) }

    var firstDayOfMonth: Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month], from: self)
        comps.day = 1
        return cal.date(from: comps) ?? self
    }

    var daysInMonth: Int {
        Calendar.current.range(of: .day, in: .month, for: self)?.count ?? 30
    }

    func isSameMonth(as other: Date) -> Bool {
        Calendar.current.isDate(self, equalTo: other, toGranularity: .month)
    }

    func isSameDay(as other: Date) -> Bool {
        Calendar.current.isDate(self, inSameDayAs: other)
    }

    var weekdaySymbol: String {
        let symbols = Calendar.current.shortWeekdaySymbols
        // weekday 返回 1-7 (Sun-Sat)，数组下标 0-6
        let idx = max(0, min(6, weekday - 1))
        return symbols[idx]
    }
}
