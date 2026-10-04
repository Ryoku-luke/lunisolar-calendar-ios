import SwiftUI

/// 月列（P4-1 第 5b-2 步之二，最后一块）：月份标题 + 节气条 + 单月网格卡 + 选中日卡片，
/// 以及"跟手翻月"的预渲染层（抽取自 `CalendarMonthView.monthColumn`）。
///
/// 设计要点（5b 的收尾）：
/// - **交互态走模型**：拖拽位移/翻页方向/容器宽度都在 `MonthGridInteraction` 里，
///   本视图只读写它，不持有这些状态；
/// - **横滑手势挂在列内部的网格区上**（不是整列）。原因见 `CalendarMonthSwipeGesture.swift`：
///   挂到 `ScrollView` 的直接子视图上会抢走纵向拖动，真机表现为主页无法上下滑动；
/// - 其余经入参 + 回调接入：父视图仍是唯一的状态所有者。
struct CalendarMonthColumn: View {
    let interaction: MonthGridInteraction
    let month: Date
    let accent: DayAccent
    let isIPadSplit: Bool
    /// 数据态：当天选中日与每周起始（网格卡需要，仍由父视图持有）
    let selectedDate: Date
    let weekStart: Int
    let gridProvider: (Date) -> MonthGridModel
    let onSelectDay: (Date) -> Void
    let onNewEvent: (Date) -> Void
    let onCopyDate: (Date) -> Void
    let onChangeMonth: (Int) -> Void
    let onTapDateJump: () -> Void
    /// 横滑翻页提交（月份变化 + 选中日随月收敛由父视图处理——数据态仍归父视图）
    let onCommitMonth: (Date) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // N-3：月份标题 + 节气条合包上报真实高度（含各自外层 padding）。
            // 节气条显隐两态自然正确——solarTermBar 为 @ViewBuilder，不存在时不渲染。
            VStack(spacing: 0) {
                CalendarMonthHeader(monthName: MonthLabel.name(for: month),
                                                    year: month.year,
                                                    controlTint: accent.controlTint,
                                                    onTapTitle: onTapDateJump,
                                                    onChangeMonth: onChangeMonth)
                    .padding(.horizontal, AppTheme.Spacing.xl)
                    .padding(.top, 8).padding(.bottom, AppTheme.Spacing.sm)
                CalendarSolarTermBar(accent: accent.decorative)
                    .padding(.horizontal, AppTheme.Spacing.xl)
                    .padding(.bottom, AppTheme.Spacing.xs)
            }
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: MonthChromeHeightKey.self, value: geo.size.height)
                }
            )
            // 卡片式月份滑动（完全跟手）：
            // 拖动中当前月卡片 1:1 跟随手指位移，相邻月网格预渲染在另一侧同速移动；
            // 松手后按位移/速度决定翻页（transition 接管收尾动画）或回弹。
            #if canImport(UIKit)
            ZStack {
                // 底层：拖动方向的相邻月（左滑=下月在右、右滑=上月在左），跟手同速
                if let pm = interaction.previewMonth {
                    // 传 pm：此前 calendarShell 内部恒定取 month，.id(pm) 只换视图标识
                    // 不改内容 → 拖动时屏幕上并排的两份是"同一个月"，相邻月等于没预渲染
                    CalendarMonthGridShell(month: pm, grid: gridProvider(pm),
                                              accent: accent.decorative, controlFill: accent.controlFill,
                                              selectedDate: selectedDate, weekStart: weekStart,
                                              isIPadSplit: isIPadSplit,
                                              columnHeight: interaction.columnHeight,
                                              chromeHeight: interaction.chromeHeight,
                                              onSelectDay: onSelectDay,
                                              onNewEvent: onNewEvent,
                                              onCopyDate: onCopyDate)
                        .id(pm)
                        .offset(x: interaction.dragOffsetX < 0 ? interaction.dragOffsetX + interaction.monthWidth : interaction.dragOffsetX - interaction.monthWidth)
                }
                // 顶层：当前月，1:1 跟手
                CalendarMonthGridShell(month: month, grid: gridProvider(month),
                                              accent: accent.decorative, controlFill: accent.controlFill,
                                              selectedDate: selectedDate, weekStart: weekStart,
                                              isIPadSplit: isIPadSplit,
                                              columnHeight: interaction.columnHeight,
                                              chromeHeight: interaction.chromeHeight,
                                              onSelectDay: onSelectDay,
                                              onNewEvent: onNewEvent,
                                              onCopyDate: onCopyDate)
                    .id(month)
                    .offset(x: interaction.dragOffsetX)
                    .scaleEffect(interaction.isDragging ? 0.992 : 1.0)
                    .transition(.asymmetric(
                        insertion: .move(edge: interaction.monthSlideEdge),
                        removal: .move(edge: interaction.monthSlideEdge == .trailing ? .leading : .trailing)
                    ))
            }
            .simultaneousGesture(swipeMonthGesture(width: interaction.monthWidth))
            // ⚠️ 只能挂在这个网格区上，不能上移到整列：挂到 ScrollView 的直接子视图
            // 会抢走纵向拖动，真机表现为「主页上下无法滑动」（2026-10-04 真实回归）。
            .padding(.horizontal, AppTheme.Spacing.md)
            // 容器宽度（翻页阈值用）：background 里读尺寸，不改变布局高度
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { interaction.monthWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, w in interaction.monthWidth = w }
                }
            )
            #else
            CalendarMonthGridShell(month: month, grid: gridProvider(month),
                                              accent: accent.decorative, controlFill: accent.controlFill,
                                              selectedDate: selectedDate, weekStart: weekStart,
                                              isIPadSplit: isIPadSplit,
                                              columnHeight: interaction.columnHeight,
                                              chromeHeight: interaction.chromeHeight,
                                              onSelectDay: onSelectDay,
                                              onNewEvent: onNewEvent,
                                              onCopyDate: onCopyDate)
                .id(month)
                .padding(.horizontal, AppTheme.Spacing.md)
            #endif
            if !isIPadSplit {
                // 2026-09-29 用户裁决：日期卡片与今日安排不再收起折叠，始终完整展开。
                // 底部保留固定呼吸空间，避免「宜做/勿做」卡片被 TabBar 遮挡。
                SelectedDayCardView(selectedDate: selectedDate,
                                    accent: accent)
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.top, AppTheme.Spacing.md)
                    // 系统 TabBar(~83pt) + home indicator + 呼吸空间
                    .padding(.bottom, 96)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
