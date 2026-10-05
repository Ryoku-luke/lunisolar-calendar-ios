import SwiftUI

/// 单月网格卡（P4-1 第 5b-2 步：抽取自 `CalendarMonthView.calendarShell`）。
///
/// 只依赖入参 + 三个回调：**选择某天、新建日程、复制日期文本**；
/// 弹性行高所需的两个测量值经 `columnHeight` / `chromeHeight` 传入。
/// 除这些之外不碰任何父视图状态——所以它是这块里"能搬"的那一半
/// （`monthColumn` 仍持有拖拽/翻月，留到下一小步）。
struct CalendarMonthGridShell: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass

    /// 被长按的格子（自绘菜单的锚点）：日期 + 在网格命名坐标系里的 frame。
    struct PressedCell: Equatable {
        let date: Date
        let frame: CGRect
    }
    @State private var pressedCell: PressedCell?
    let month: Date
    /// 已构建好的网格模型（缓存仍由父视图持有：父视图用 `gridModel(for:)` 取好再传入）
    let grid: MonthGridModel
    let accent: Color
    let controlFill: Color
    let selectedDate: Date
    let weekStart: Int
    let isIPadSplit: Bool
    let columnHeight: CGFloat
    let chromeHeight: CGFloat
    let onSelectDay: (Date) -> Void
    let onNewEvent: (Date) -> Void
    let onCopyDate: (Date) -> Void

    var body: some View {
                let columns = [GridItem](repeating: GridItem(.flexible(), spacing: 0), count: 7)
        return VStack(alignment: .leading, spacing: 0) {
            WeekHeaderView(weekStart: weekStart)
                // N-3：星期表头高度上报（弹性行高 chrome 的组成部分）
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: MonthChromeHeightKey.self, value: geo.size.height)
                    }
                )
            LazyVGrid(columns: columns, spacing: isIPadSplit ? 6 : 3) {
                ForEach(grid.cells) { cell in
                    let d = cell.date
                    DayCellView(date: d, isCurrentMonth: cell.inCurrentMonth,
                                isSelected: d.isSameDay(as: selectedDate),
                                isToday: d.isToday,
                                lunar: cell.lunar,
                                huangli: cell.huangli,
                                hasEvents: cell.eventCount > 0,
                                eventPriorities: cell.eventPriorities,
                                eventCount: cell.eventCount,
                                festivalTint: cell.festivalTint,
                                selectedForeground: cell.selectedForeground,
                                cellAccent: cell.festivalTint
                                    ?? (d.isSameDay(as: selectedDate) ? controlFill : nil),
                                festivalName: cell.festivalName,
                                solarTermName: cell.solarTermName,
                                solarTermTint: cell.solarTermTint,
                                holidayType: cell.holidayType)
                        .equatable()
                        // iPad：按可视高度弹性分配行高；iPhone：nil → 不限高，
                        // 由下一行的 minHeight 给出可点下限
                        .frame(height: MonthGridMetrics.elasticCellHeight(rows: grid.cells.count / 7,
                                                                isIPadSplit: isIPadSplit,
                                                                columnHeight: columnHeight,
                                                                chromeHeight: chromeHeight))
                        .frame(minHeight: AppTheme.Touch.minCellHeight)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelectDay(d)
                        }
                        // 长按 → 自绘菜单（方案 1）。用 UIKit 识别器：`cancelsTouchesInView = false`
                        // 且与其它手势并行 → 点按与横滑都不受影响（Button 吞拖动、pressableFeedback
                        // 吞 tap 都已实测否掉；此格是"手势真空区"，只有 UIKit 识别器能同时容纳三者）。
                        // **不用系统 .contextMenu**：它会对格子做**位图快照**，长按回落时缩放这张位图 →
                        // 文字被重采样（"回落一瞬间字扭曲变形"）；且抬起预览圆角由系统决定、
                        // 与格子圆角不一致（"圆角依然不一致"）。自绘菜单没有快照，两个问题一起消失。
                        // 锚点取命名坐标系里的 frame，分栏/横屏都不会错位。
                        .overlay {
                            GeometryReader { geo in
                                DayCellLongPressCatcher(
                                    onLongPress: {
                                        // 必须包 withAnimation：否则 DayCellLongPressMenu 的
                                        // .transition 不会播放，菜单会"瞬间出现"（用户反馈
                                        // "没有了原来弹出的动画"）。
                                        withAnimation(AppTheme.Motion.selection) {
                                            pressedCell = PressedCell(
                                                date: d, frame: geo.frame(in: .named("monthGrid")))
                                        }
                                    },
                                    onRelease: {
                                        withAnimation(AppTheme.Motion.selection) { pressedCell = nil }
                                    },
                                    onTap: { onSelectDay(d) })
                            }
                        }
                        // 无障碍降级：仅 VoiceOver 运行时保留系统菜单
                        // （系统菜单的无障碍支持最完整；位图快照对不依赖视觉的用户无影响）。
                        .modifier(SystemMenuForVoiceOver(
                            onSelect: { onSelectDay(d) },
                            onNew: { onNewEvent(d) },
                            onCopy: { onCopyDate(d) }))
                }
            }
            // 原生选中触觉反馈：选中日期轻震（iOS 17+ 系统 sensoryFeedback，无自定义引擎）
            .sensoryFeedback(.selection, trigger: selectedDate)
            .padding(.horizontal, isIPadSplit ? AppTheme.Spacing.lg : AppTheme.Spacing.md)
            .padding(.bottom, AppTheme.Spacing.lg)
        }
        .padding(.top, AppTheme.Spacing.sm)
        // 月历是主视觉：白/浅色卡片 + 极轻边界，减少玻璃效果噪声。
        .background(
            Color.secondarySystemGroupedBackground,
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.xxl, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.xxl, style: .continuous)
                .stroke(Color.themeSeparator.opacity(0.18), lineWidth: 0.7)
        }
        .contentShape(Rectangle())
        // 自绘长按菜单（方案 1）：命名坐标系让每个格子能报到「网格内的准确位置」；
        // 浮层挂在网格根上并按该位置定位。**不做位图快照** → 回落时文字不会被重采样，
        // 且圆角取 DayCellView.selectionRadius（与格子同源）→ 不再出现圆角不一致。
        .coordinateSpace(name: "monthGrid")
        .overlay(alignment: .topLeading) {
            if let pressed = pressedCell {
                DayCellLongPressMenu(
                    radius: DayCellView.selectionRadius(regular: hSizeClass == .regular),
                    onSelect: { onSelectDay(pressed.date); pressedCell = nil },
                    onNew: { onNewEvent(pressed.date); pressedCell = nil },
                    onCopy: { onCopyDate(pressed.date); pressedCell = nil },
                    onDismiss: { pressedCell = nil })
                    .offset(x: pressed.frame.minX, y: pressed.frame.maxY + 6)
                    // 触觉反馈：系统菜单自带"弹出时的轻震"，自绘菜单要自己给
                    // （用户反馈"没有了原来震动的效果"）。trigger 用 Bool → 只在开/关时各响一次。
                    .sensoryFeedback(.impact(weight: .medium), trigger: pressedCell != nil)
                    // 开/关**两个方向**都要动画（只给 onLongPress 包 withAnimation 的话，
                    // 点操作项或点外部关闭时菜单会"啪"地消失）。
                    .animation(AppTheme.Motion.selection, value: pressedCell)
            }
        }
        // 月份横滑手势统一在 monthColumn 以 simultaneousGesture 挂载（避免拦截日期点按与纵向滚动）
    }
}
