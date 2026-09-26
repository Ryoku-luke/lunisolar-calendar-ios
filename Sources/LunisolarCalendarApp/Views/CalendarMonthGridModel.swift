#if canImport(SwiftUI)
import SwiftUI
import LunarCore

struct DaySlot: Identifiable, Hashable {
    let date: Date
    let inCurrentMonth: Bool
    /// 以日期作为稳定标识：横滑手势期间 dragOffsetX 每帧触发 body 重算，
    /// 若用 UUID() 会导致 42 个格子每帧被 ForEach 判定为全新元素而重建掉帧。
    /// 月历网格内日期天然唯一，可直接作 id。
    var id: Date { date }
}

/// 月历单格的全部派生显示数据（农历/黄历/节日色/法定假日/事件统计）。
/// 这些数据只依赖「日期 + EventStore.revision」，与拖拽偏移/选中态无关，
/// 按月份整体预计算一次后跨帧复用。
struct GridCellModel: Identifiable {
    let date: Date
    let inCurrentMonth: Bool
    let lunar: LunarDate
    let huangli: HuangliDay
    let festivalTint: Color?
    /// 节假日名（如"中秋节"）：节日当天格内只显示节日名，不显示农历
    let festivalName: String?
    /// 节气名（如"秋分"）：节气日格内只显示节气名，不显示农历
    let solarTermName: String?
    /// 节气主题色（绿色系），用于格内"·秋分"小字
    let solarTermTint: Color?
    let holidayType: HolidayType
    let eventCount: Int
    /// 当日全部事件优先级（按事件顺序），格子事件点逐个着色
    let eventPriorities: [Priority]
    var id: Date { date }
}

/// 网格缓存键的**唯一定义**（读、写两侧共用，避免两处字符串拼接各自漂移）。
///
/// ⚠️ `weekStart` 必须进键：42 格的前导空格数依赖它，而表头 `WeekHeaderView` 读的是实时值。
/// 漏掉它时改「每周起始日」只会让表头旋转、网格顺序仍是旧的 → 日期与星期对不上，
/// 要滑一次月份才自愈。
func monthGridCacheKey(month: Date, revision: Int, weekStart: Int) -> String {
    "\(month.timeIntervalSince1970)-\(revision)-\(weekStart)"
}

struct MonthGridModel {
    let monthKey: Date
    let revision: Int
    /// 每周起始日（1=周日，2=周一）：网格前导空格数由它决定，故必须参与缓存键
    let weekStart: Int
    let cells: [GridCellModel]
    /// 缓存键（用于多月份网格缓存字典）
    var cacheKey: String {
        monthGridCacheKey(month: monthKey, revision: revision, weekStart: weekStart)
    }
}

#endif
