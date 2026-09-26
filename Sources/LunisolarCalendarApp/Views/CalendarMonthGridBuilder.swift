#if canImport(SwiftUI)
import SwiftUI
import LunarCore

extension CalendarMonthView {
    func prefetchGrid(for month: Date) {
        let model = buildGridModel(for: month)
        gridCache[model.cacheKey] = model
    }

    /// 月历纵向列：月份标题 + 节气条 + 网格（iPhone 下方还有当日卡片）。
    /// 卡片式月份切换：设置滑动进入方向后用 withAnimation 变更 currentMonth，
    /// 触发 ZStack 中日历网格的 .id + .transition 滑动转场（旧网格滑出、新网格滑入）。
    /// 同时把选中日期联动到新月份（同日存在则保持，否则取月末），
    /// 避免"切月后日期卡仍显示上月内容"的逻辑不通。
    func changeMonth(by offset: Int) {
        monthSlideEdge = offset > 0 ? .trailing : .leading
        withAnimation(AppTheme.Motion.screen) {
            currentMonth = currentMonth.addingMonths(offset)
            selectedDate = Self.clampedToMonth(selectedDate, in: currentMonth)
        }
    }

    /// 将日期钳制到目标月份：同日存在则保持原日，否则取目标月最后一天（如 1/31 → 2/28）。
    static func clampedToMonth(_ date: Date, in month: Date) -> Date {
        let cal = Calendar(identifier: .gregorian)
        var comps = cal.dateComponents([.year, .month, .day], from: date)
        let target = cal.dateComponents([.year, .month], from: month)
        comps.year = target.year
        comps.month = target.month
        if let day = comps.day,
           let dayCount = cal.range(of: .day, in: .month, for: month)?.count,
           day > dayCount {
            comps.day = dayCount
        }
        return cal.date(from: comps) ?? date
    }

    /// 返回当前月的网格派生数据；月份/事件版本未变时直接复用缓存。
    /// SwiftUI 未定义行为警告修复：body 求值期间**不再回写 @State gridCache**
    /// （Xcode 报 "Modifying state during view update, this will cause undefined behavior"，
    ///  调用栈直指本方法）。未命中时直接构建返回（纯计算无副作用），
    /// 缓存由 `.task(id: gridCacheKey)` 在 body 外异步填充。
    func gridModel(for month: Date) -> MonthGridModel {
        // body 求值期间只读缓存，不写 @State（避免 SwiftUI 未定义行为警告）；
        // 缓存写入统一由 .task(id:) 与 onChange 预填充负责
        if let cached = gridCache[cacheKey(month: month)] { return cached }
        return buildGridModel(for: month)
    }

    /// 纯计算构建网格模型（无副作用，可在 body 与 .task 中安全调用）。
    func buildGridModel(for month: Date) -> MonthGridModel {
        let slots = daysForMonth(month)
        var cells: [GridCellModel] = []
        cells.reserveCapacity(slots.count)
        for slot in slots {
            let d = slot.date
            // 农历转换 → 节日查询（复用预计算 lunar）→ 颜色解析，每月只做一次
            let lunar = d.lunar
            let festivals = FestivalManager.festivals(on: d, lunar: lunar)
            // 节气与节日可同日并存（如清明既是节气也是祭祖日）：
            // 节气 → 格内绿色"节气名"文字标注，不染色背景；
            // 节日 → 格内节日名文字 + 节日色（不再浅染背景，除选中外无"选择框"）
            let solarTermFest = festivals.first { $0.kind == .solarTerm }
            let otherFest = festivals.first { $0.kind != .solarTerm }
            let festivalTint = otherFest.map { Color(hex: $0.accentHex) }
            let festivalName = otherFest?.localizedName
            let solarTermName = solarTermFest?.localizedName
            let solarTermTint = solarTermFest.map { Color(hex: $0.accentHex) }
            let stats = store.eventStats(on: d)
            cells.append(GridCellModel(
                date: d,
                inCurrentMonth: slot.inCurrentMonth,
                lunar: lunar,
                huangli: HuangliGenerator.generate(for: d),
                festivalTint: festivalTint,
                festivalName: festivalName,
                solarTermName: solarTermName,
                solarTermTint: solarTermTint,
                holidayType: HolidayProvider.info(for: d).type,
                eventCount: stats.count,
                eventPriorities: stats.priorities
            ))
        }
        return MonthGridModel(monthKey: month, revision: store.revision,
                              weekStart: weekStart, cells: cells)
    }

    /// 缓存键：月份 + 事件版本 + 每周起始日（与 `MonthGridModel.cacheKey` 同源定义）
    func cacheKey(month: Date) -> String {
        monthGridCacheKey(month: month, revision: store.revision, weekStart: weekStart)
    }

    /// 缓存失效键：月份、事件版本或每周起始日变化时重建（用于 .task(id:) 触发）。
    var gridCacheKey: String {
        monthGridCacheKey(month: currentMonth, revision: store.revision, weekStart: weekStart)
    }

    /// 选中某一天：若它属于相邻月份，连同月份一起切过去并给出滑动方向。
    ///
    /// 否则「选中日」与「显示月」不一致（首页标题的月份与选中日期对不上），
    /// 而且下次翻月时 `clampedToMonth` 会把选中日静默改写成另一个月的同一天。
    func selectDay(_ date: Date) {
        let month = date.firstDayOfMonth
        if month != currentMonth {
            monthSlideEdge = month > currentMonth ? .trailing : .leading
            withAnimation(AppTheme.Motion.screen) { currentMonth = month }
        }
        withAnimation(AppTheme.Motion.pressInOut) { selectedDate = date }
    }

    /// 复制选中日期的中文长格式到剪贴板（上下文菜单动作）
    func copyDateText(_ date: Date) {
        #if canImport(UIKit)
        UIPasteboard.general.string = date.formatted(
            Date.FormatStyle(date: .long, time: .omitted, locale: Locale(identifier: "zh_Hans_CN")))
        #endif
    }

    func daysForMonth(_ month: Date) -> [DaySlot] {
        let first = month.firstDayOfMonth
        // 按每周起始日计算前置空位：weekStart=1(周日) → (wd-1)；weekStart=2(周一) → (wd+5)%7
        let leading = (first.weekday - weekStart + 7) % 7
        let totalDays = month.daysInMonth
        var result: [DaySlot] = []
        for i in 0..<leading {
            result.append(DaySlot(date: first.addingDays(-(leading - i)), inCurrentMonth: false))
        }
        for i in 0..<totalDays {
            result.append(DaySlot(date: first.addingDays(i), inCurrentMonth: true))
        }
        var i = 0
        while result.count < 42 {
            result.append(DaySlot(date: first.addingDays(totalDays + i), inCurrentMonth: false))
            i += 1
        }
        return result
    }
}

#endif
