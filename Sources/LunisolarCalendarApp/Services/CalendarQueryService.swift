import Foundation
import LunarCore

// MARK: - 日历查询服务（P1-4）
//
// View 拿单日聚合数据的唯一入口：
//   CalendarQueryService.shared.summary(for: date)
//
// 内部聚合 LunarDate / FestivalManager / HolidayProvider / SolarTermProvider /
// HuangliDBProvider / EventStore，View 不再直接散落调用。

@MainActor
public final class CalendarQueryService {
    public static let shared = CalendarQueryService()

    private init() {}

    /// 单日完整摘要。
    public func summary(for date: Date, weather: WeatherSummary? = nil) -> CalendarDaySummary {
        let lunar = ChineseCalendar.lunarDateSafe(from: date)
        let festivals = FestivalManager.festivals(on: date, lunar: lunar)
        let solarTerm = SolarTermProvider.termOn(date)
        let holidayType = HolidayProvider.info(for: date).type
        let resolved = HuangliDBProvider.resolve(date: date)
        let events = EventStore.shared.events.filter { event in
            Calendar.current.isDate(event.startDate, inSameDayAs: date)
        }
        return CalendarDaySummary(
            date: date,
            lunar: lunar,
            festivals: festivals,
            solarTerm: solarTerm,
            holidayType: holidayType,
            huangli: resolved.huangliDay,
            events: events,
            weatherSummary: weather
        )
    }

    /// 月视图范围内的轻量摘要（只算日历格需要的字段，不算 events/weather）。
    public func monthCell(for date: Date) -> (lunar: LunarDate?, festivals: [Festival], solarTerm: String?, holidayType: HolidayType) {
        let lunar = ChineseCalendar.lunarDateSafe(from: date)
        let festivals = FestivalManager.festivals(on: date, lunar: lunar)
        let solarTerm = SolarTermProvider.termOn(date)
        let holidayType = HolidayProvider.info(for: date).type
        return (lunar, festivals, solarTerm, holidayType)
    }
}
