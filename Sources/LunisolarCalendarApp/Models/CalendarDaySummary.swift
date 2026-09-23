import Foundation
import LunarCore

// MARK: - 单日聚合摘要（P1-4）
//
// 把"某一天"需要的所有展示数据聚合到一个值类型：
// date / lunar / festivals / solarTerm / huangli / holiday / events / weather
// CalendarMonthView / DayDetailView / Widget 都从 CalendarQueryService 拿这个摘要，
// 不再各自散落调用 HuangliDBProvider / FestivalManager / HolidayProvider。

public struct CalendarDaySummary: Sendable {
    public let date: Date
    public let lunar: LunarDate?
    public let festivals: [Festival]
    public let solarTerm: String?
    public let holidayType: HolidayType
    public let huangli: HuangliDay?
    public let events: [CalendarEvent]
    public let weatherSummary: WeatherSummary?

    public init(
        date: Date,
        lunar: LunarDate?,
        festivals: [Festival],
        solarTerm: String?,
        holidayType: HolidayType,
        huangli: HuangliDay?,
        events: [CalendarEvent],
        weatherSummary: WeatherSummary?
    ) {
        self.date = date
        self.lunar = lunar
        self.festivals = festivals
        self.solarTerm = solarTerm
        self.holidayType = holidayType
        self.huangli = huangli
        self.events = events
        self.weatherSummary = weatherSummary
    }
}

/// 天气摘要（从 WeatherService 抽离，View 不直接持 WeatherService 状态）
public struct WeatherSummary: Sendable {
    public let condition: String       // "晴" / "多云" / "小雨"
    public let temperatureLow: Int
    public let temperatureHigh: Int
    public let symbolName: String      // SF Symbol
    public let locationName: String

    public init(condition: String, temperatureLow: Int, temperatureHigh: Int, symbolName: String, locationName: String) {
        self.condition = condition
        self.temperatureLow = temperatureLow
        self.temperatureHigh = temperatureHigh
        self.symbolName = symbolName
        self.locationName = locationName
    }
}
