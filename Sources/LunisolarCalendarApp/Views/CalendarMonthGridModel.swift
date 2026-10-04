#if canImport(SwiftUI)
import SwiftUI
import LunarCore

struct DaySlot: Identifiable, Hashable {
    let date: Date
    let inCurrentMonth: Bool
    /// 以日期作为稳定标识：横滑手势期间 interaction.dragOffsetX 每帧触发 body 重算，
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
    /// 选中该日时格内文字的颜色（`SelectedCellForeground.resolve` 的结果）。
    /// 不用半透明白：透明度会把对比度拉低（实测 0.9 白字最差 3.94:1 < 4.5）。
    let selectedForeground: Color
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

extension GridCellModel {
    /// 由「日期 + 该日节日 + 事件统计」派生一格。
    ///
    /// 为什么抽出来：这段派生原先写在 `CalendarMonthView` 的扩展里（SwiftUI 视图），
    /// 单测够不着 —— 而审查报告 P3-1 的验收恰恰要求「测试覆盖这条真实路径，
    /// 而不是只测助手函数」。抽成工厂后，测试可以用真实节日（中秋 2026-09-25）
    /// 断言"填充仍是节日原色、选中字色已按亮度切成黑"。
    static func derive(date: Date,
                       inCurrentMonth: Bool,
                       lunar: LunarDate,
                       huangli: HuangliDay,
                       festivals: [Festival],
                       holidayType: HolidayType,
                       eventCount: Int,
                       eventPriorities: [Priority]) -> GridCellModel {
        // 节气与节日可同日并存（如清明既是节气也是祭祖日）：
        // 节气 → 格内绿色"节气名"文字标注，不染色背景；
        // 节日 → 格内节日名文字 + 节日色（不再浅染背景，除选中外无"选择框"）
        let solarTermFest = festivals.first { $0.kind == .solarTerm }
        let otherFest = festivals.first { $0.kind != .solarTerm }
        return GridCellModel(
            date: date,
            inCurrentMonth: inCurrentMonth,
            lunar: lunar,
            huangli: huangli,
            festivalTint: otherFest.map { Color(hex: $0.accentHex) },
            // 决策点在 SelectedCellForeground（可单测），这里只取结果
            selectedForeground: SelectedCellForeground.resolve(festivalHex: otherFest?.accentHex),
            festivalName: otherFest?.localizedName,
            solarTermName: solarTermFest?.localizedName,
            solarTermTint: solarTermFest.map { Color(hex: $0.accentHex) },
            holidayType: holidayType,
            eventCount: eventCount,
            eventPriorities: eventPriorities
        )
    }
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
