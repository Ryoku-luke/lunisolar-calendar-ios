import Foundation
import LunarCore

// MARK: - 当日派生数据的单一来源（派生数据收口）
//
// 为什么要有这个类型：
//
// 1. **单一来源**。「某一天是什么日子」由多个生成器共同决定（农历换算、黄历宜忌、节日、
//    当天交节的节气、国务院放假安排）。收口之前，每个页面各自拼一遍：选中日卡片、黄历详情页、
//    设置页、日程编辑页都在 body/computed property 里直接调 `HuangliGenerator.generate` /
//    `FestivalManager.festivals` / `HolidayProvider.info`，同一个日子在四个页面要算四遍。
//
// 2. **避免同一天在不同页面算出不同结果**。收口前各页面自己决定「先算农历再传给 festival 查询」
//    还是让 festival 查询自己再算一次农历、自己决定用哪个放假查询入口——只要有一处跟另一处不一致
//    （时区、越界占位、传参顺序），用户就会看到「月历上是中秋、详情页不是」。现在这些取值只有
//    一处定义，页面拿到的必然一致。
//
// 3. **继续拆分巨型 View 的前置**。`SettingsView` / `CalendarMonthView` 这类千行文件要继续拆时，
//    拆出来的子视图需要一份稳定的「当日数据」参数，而不是各自 `@Environment(EventStore.self)` +
//    自己调生成器。先把派生数据收成一个值类型，再拆视图就只是搬参数。
//
// 设计边界（刻意为之）：
// - **纯值类型、纯派生**：只把现有生成器的结果算一次、装在一起，不新增任何业务判断。
// - **不持有 store**：当日事件由调用方作为 `events` 传入，本类型不访问 `EventStore`，
//   因此可以在单测、Widget、预览等没有 store 的上下文里构造。
// - **无缓存**：事件变更（增删改）会让缓存失效，而失效逻辑比这点性能收益更难维护。
//   本步只做「收口」——需要缓存时由调用方或上层查表解决（月网格走 `MonthGridModel`）。
public struct CalendarDaySummary: Equatable, Sendable {
    public let date: Date
    public let lunar: LunarDate
    public let huangli: HuangliDay
    public let festivals: [Festival]
    /// 当天恰逢交节的节气名（无则 nil）
    public let solarTermName: String?
    /// 休 / 班 / 普通（国务院放假安排）
    public let holidayType: HolidayType
    /// 当日事件（调用方传入，保持本类型不依赖 store）
    public let events: [CalendarEvent]

    public init(date: Date, events: [CalendarEvent] = []) {
        self.date = date
        // 各生成器的调用口径与收口前的视图调用点逐字一致：
        // - lunar：`Date.lunar`（越界返回 .unsupported 占位，不再返回"公历镜像假农历"）
        // - festivals：复用上面这一次农历换算，不再让 FestivalManager 自己再算一遍
        // - solarTermName / holidayType：视图原本用的就是 termOn / info(for:).type 这两个入口
        let lunar = date.lunar
        self.lunar = lunar
        self.huangli = HuangliGenerator.generate(for: date)
        self.festivals = FestivalManager.festivals(on: date, lunar: lunar)
        self.solarTermName = SolarTermProvider.termOn(date)
        self.holidayType = HolidayProvider.info(for: date).type
        self.events = events
    }

    // MARK: - 视图依赖的便利契约

    /// 强调色来源：**必须是 `festivals.first`**。
    /// 视图（选中日卡、详情页、日视图染色）一直取列表首项，而 `FestivalManager.primaryFestival(on:)`
    /// 是另一套「大节日优先」的排序，改用它会改变配色/主节日行为。
    public var primaryFestival: Festival? { festivals.first }

    public var accentHex: String? { primaryFestival?.accentHex }
}
