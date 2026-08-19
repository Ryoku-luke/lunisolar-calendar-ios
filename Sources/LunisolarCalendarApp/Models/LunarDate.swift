import Foundation

// MARK: - 农历日期模型

public struct LunarDate: Equatable, Hashable {
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

    // 公历转农历核心数据表 (1900-2100)
    // 每个整数编码了该年农历信息:
    //   bit 0-3:  闰月月份 (0=无闰月)
    //   bit 4-15: 12个月大小(1=30天, 0=29天), 从最高位开始对应正月到腊月
    //   bit 16-19: 闰月大小(1=30天, 0=29天)
    static let lunarInfo: [UInt32] = [
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

    public static let tianGan = ["甲","乙","丙","丁","戊","己","庚","辛","壬","癸"]
    public static let diZhi = ["子","丑","寅","卯","辰","巳","午","未","申","酉","戌","亥"]
    public static let zodiacs = ["鼠","牛","虎","兔","龙","蛇","马","羊","猴","鸡","狗","猪"]
    public static let lunarMonthNames = ["正","二","三","四","五","六","七","八","九","十","冬","腊"]
    public static let lunarDayNames = [
        "初一","初二","初三","初四","初五","初六","初七","初八","初九","初十",
        "十一","十二","十三","十四","十五","十六","十七","十八","十九","二十",
        "廿一","廿二","廿三","廿四","廿五","廿六","廿七","廿八","廿九","三十"
    ]

    // MARK: - 基础信息提取

    /// 获取该年闰月月份 (0=无闰月)
    public static func leapMonth(of year: Int) -> Int {
        guard year >= 1900, year <= 2100 else { return 0 }
        return Int(lunarInfo[year - 1900] & 0xF)
    }

    /// 获取该年闰月天数
    public static func leapDays(of year: Int) -> Int {
        if leapMonth(of: year) != 0 {
            return (lunarInfo[year - 1900] & 0x10000) != 0 ? 30 : 29
        }
        return 0
    }

    /// 获取该年农历总天数
    public static func daysInLunarYear(_ year: Int) -> Int {
        guard year >= 1900, year <= 2100 else { return 354 }
        // bit4-15 对应正月到腊月大小 (1=30天)
        var sum = 348 // 12 * 29 天
        let info = lunarInfo[year - 1900]
        var mask: UInt32 = 0x8000  // bit15 (正月) -> bit4 (腊月)
        for _ in 0..<12 {
            if info & mask != 0 { sum += 1 }
            mask >>= 1
        }
        return sum + leapDays(of: year)
    }

    /// 获取该农历月的天数
    public static func daysInLunarMonth(year: Int, month: Int, isLeap: Bool) -> Int {
        guard year >= 1900, year <= 2100, month >= 1, month <= 12 else { return 30 }
        if isLeap && leapMonth(of: year) == month {
            return leapDays(of: year)
        }
        // bit15=正月 bit14=二月 ... bit4=腊月
        let mask: UInt32 = 0x10000 >> month
        return (lunarInfo[year - 1900] & mask) != 0 ? 30 : 29
    }

    // MARK: - 公历转农历

    private static let baseDate: Date = {
        var comps = DateComponents()
        comps.year = 1900
        comps.month = 1
        comps.day = 31
        comps.hour = 0
        comps.minute = 0
        comps.second = 0
        return Calendar.current.date(from: comps) ?? Date()
    }()

    /// 公历 Date 转农历 LunarDate
    public static func lunarDate(from date: Date) -> LunarDate {
        let cal = Calendar(identifier: .gregorian)
        // 归一化到当天 00:00，确保时分秒不影响天数差
        let normalized = cal.startOfDay(for: date)
        let baseNorm = cal.startOfDay(for: baseDate)

        // 计算与基准日(1900年1月31日=农历1900年正月初一)的天数差
        let offsetComps = cal.dateComponents([.day], from: baseNorm, to: normalized)
        var offset = offsetComps.day ?? 0

        if offset < 0 {
            // 1900年1月31日之前，降级为公历镜像（保证不崩溃）
            let gregorian = cal.dateComponents([.year, .month, .day], from: date)
            return LunarDate(
                year: gregorian.year ?? 1900,
                month: gregorian.month ?? 1,
                day: gregorian.day ?? 1,
                isLeapMonth: false
            )
        }

        // 年循环：逐年递减天数，确定农历年
        var year = 1900
        while year <= 2100 {
            let daysInYear = daysInLunarYear(year)
            if offset < daysInYear { break }
            offset -= daysInYear
            year += 1
        }
        if year > 2100 {
            // 超出数据表上界：降级处理
            let gregorian = cal.dateComponents([.year, .month, .day], from: date)
            return LunarDate(
                year: min(gregorian.year ?? 2100, 2100),
                month: gregorian.month ?? 1,
                day: gregorian.day ?? 1,
                isLeapMonth: false
            )
        }

        // 月循环：确定月份/闰月/日期
        let leapMonthIndex = leapMonth(of: year)
        var isLeap = false
        var month = 1
        var found = false

        while month <= 12 {
            // 处理普通月
            let daysOfNormalMonth = daysInLunarMonth(year: year, month: month, isLeap: false)

            if offset < daysOfNormalMonth {
                // 命中普通月
                isLeap = false
                found = true
                break
            }
            offset -= daysOfNormalMonth

            // 处理闰月（仅在该月刚好是闰月月份，且闰月还没处理过）
            if leapMonthIndex > 0 && month == leapMonthIndex && !isLeap {
                let daysOfLeapMonth = leapDays(of: year)
                if offset < daysOfLeapMonth {
                    // 命中闰月
                    isLeap = true
                    found = true
                    break
                }
                offset -= daysOfLeapMonth
            }

            month += 1
        }

        if !found {
            // 兜底（理论上不会到达）
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
    public var lunar: LunarDate {
        ChineseCalendar.lunarDate(from: self)
    }

    public var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    public var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    public func addingDays(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
    }

    public func addingMonths(_ months: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: months, to: self) ?? self
    }

    public var year: Int { Calendar.current.component(.year, from: self) }
    public var month: Int { Calendar.current.component(.month, from: self) }
    public var day: Int { Calendar.current.component(.day, from: self) }
    public var weekday: Int { Calendar.current.component(.weekday, from: self) }

    public var firstDayOfMonth: Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month], from: self)
        comps.day = 1
        return cal.date(from: comps) ?? self
    }

    public var daysInMonth: Int {
        Calendar.current.range(of: .day, in: .month, for: self)?.count ?? 30
    }

    public func isSameMonth(as other: Date) -> Bool {
        Calendar.current.isDate(self, equalTo: other, toGranularity: .month)
    }

    public func isSameDay(as other: Date) -> Bool {
        Calendar.current.isDate(self, inSameDayAs: other)
    }

    public var weekdaySymbol: String {
        let symbols = Calendar.current.shortWeekdaySymbols
        return symbols[weekday - 1]
    }
}
