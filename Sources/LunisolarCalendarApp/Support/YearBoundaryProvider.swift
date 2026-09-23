import Foundation
import LunarCore

// MARK: - 干支年（年柱）边界：立春交节

/// 按黄历行业标准（立春换年柱）判断给定公历日期所属的干支纪年年份。
///
/// 数据优先级：
/// - 2024–2032：`SolarTermProvider` 内置 Swiss Ephemeris 精确立春时刻（Asia/Shanghai，
///   与紫金山天文台/香港天文台分钟级一致）；
/// - 其他年份：退化为 2/4 00:00 Asia/Shanghai 近似（与 LunarCore 的
///   `ChineseCalendar.ganZhiOfYear(for:)` 兜底口径一致）。
///
/// 模块边界（文档 #5）：LunarCore 保持通用近似实现、不依赖节气表；
/// 本文件位于 App target，负责把精确节气换算为干支年判断，
/// 供黄历排盘 / 年视图 / 后续八字类功能使用。
enum YearBoundaryProvider {
    /// 立春在节气表（0-23）中的序号
    static let lichunIndex = 2

    /// 指定公历年份的立春交节时刻（精确优先，无数据退化 2/4 00:00 近似）
    static func lichunBoundary(for year: Int) -> Date {
        if let exact = SolarTermProvider.termDate(year: year, index: lichunIndex) {
            return exact
        }
        var dc = DateComponents()
        dc.year = year
        dc.month = 2
        dc.day = 4
        dc.hour = 0
        dc.minute = 0
        dc.timeZone = QingheCalendarContext.chinaTimeZone
        return Calendar(identifier: .gregorian).date(from: dc) ?? Date(timeIntervalSince1970: 0)
    }

    /// 给定公历日期所属的干支纪年年份（按立春换年柱）。
    /// - 立春前（含 1 月）：返回上一年（如 2026-02-04 03:59 → 2025）；
    /// - 立春及以后：返回当年（如 2026-02-04 04:01 → 2026）。
    static func effectiveGanZhiYear(for date: Date) -> Int {
        let y = Calendar(identifier: .gregorian).component(.year, from: date)
        return (date < lichunBoundary(for: y)) ? y - 1 : y
    }

    /// 干支年字符串（如"乙巳"、"丙午"）
    static func ganZhiString(for date: Date) -> String {
        ChineseCalendar.ganZhiOfYear(effectiveGanZhiYear(for: date))
    }
}
