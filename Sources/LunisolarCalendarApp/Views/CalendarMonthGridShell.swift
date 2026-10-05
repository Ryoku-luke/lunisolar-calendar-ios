import SwiftUI

/// 单月网格卡（P4-1 第 5b-2 步：抽取自 `CalendarMonthView.calendarShell`）。
///
/// 只依赖入参 + 三个回调：**选择某天、新建日程、复制日期文本**；
/// 弹性行高所需的两个测量值经 `columnHeight` / `chromeHeight` 传入。
/// 除这些之外不碰任何父视图状态——所以它是这块里"能搬"的那一半
/// （`monthColumn` 仍持有拖拽/翻月，留到下一小步）。
struct CalendarMonthGridShell: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass
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
                        // 长按抬起预览用**与格子一致**的圆角（否则抬起瞬间圆角会跳一下）。
                        // 封装成 ViewModifier：`.contextMenuPreview` 在 macOS 不可用，
                        // 该修饰符在非 UIKit 平台是空操作（本包同时为 macOS 宿主构建）。
                        // 它只影响抬起预览的形状，不参与命中测试、也不注册手势，
                        // 因此不影响点按与横滑（前两轮分别被破坏过的那两个功能）。
                        .modifier(ContextMenuPreviewShape(
                            radius: DayCellView.selectionRadius(regular: hSizeClass == .regular)))
                        .onTapGesture {
                            onSelectDay(d)
                        }
                        // ⚠️ 此处**不要**加 `Button` 或 `pressableFeedback()`（或任何手势）：
                        // 2026-10-05 两次实测——改 Button 会吞掉横向拖动（Flow17 红：横滑翻月失效）；
                        // 加 pressableFeedback（内部 DragGesture）会吞掉 tap（Flow1 红：点击不再选中）。
                        // 日期格必须同时容纳「点按选中」与「网格横滑翻月」，两者都靠触摸直通，
                        // 因此这一格是**手势真空区**。要加按下反馈只能走 UIKit 长按识别器
                        // （cancelsTouchesInView = false，像 TapOutsideKeyboardDismisser 那样）。
                        // 原生上下文菜单：长按日期格 → 快捷操作（原创，克制不加额外功能）
                        .contextMenu {
                            Button {
                                onSelectDay(d)
                            } label: {
                                Label("选中此日", systemImage: "checkmark.circle")
                            }
                            Button {
                                onNewEvent(d)
                            } label: {
                                Label("新建日程", systemImage: "plus.circle")
                            }
                            Button {
                                onCopyDate(d)
                            } label: {
                                Label("复制日期", systemImage: "doc.on.doc")
                            }
                        }
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
        // 月份横滑手势统一在 monthColumn 以 simultaneousGesture 挂载（避免拦截日期点按与纵向滚动）
    }
}

/// 把上下文菜单「抬起预览」的形状对齐到格子自身圆角（消除抬起瞬间的圆角跳动）。
///
/// 为什么需要：长按抬起时系统按自己的圆角裁切预览，与格子的圆角不一致时会"跳一下"。
/// `.contentShape(.contextMenuPreview, …)` 在 **macOS 不可用**，故此处按平台分支——
/// 非 UIKit 平台直接返回原视图（空操作）。
private struct ContextMenuPreviewShape: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View {
        #if canImport(UIKit)
        content.contentShape(.contextMenuPreview,
                             RoundedRectangle(cornerRadius: radius, style: .continuous))
        #else
        content
        #endif
    }
}
