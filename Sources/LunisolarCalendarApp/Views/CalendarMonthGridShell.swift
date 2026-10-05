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
                        // ⚠️ 这里**不要**加 `.contentShape(.contextMenuPreview, …)`：
                        // 2026-10-05 曾用它把抬起预览的圆角对齐到格子圆角，但用户随即反馈
                        // "回弹一瞬间里面的字扭曲变形"——该 kind 会让系统按遮罩位图化预览，
                        // 回弹时文字被重采样，于是**用更大的视觉问题换掉了一个小的圆角差异** ✗。
                        // 已回退；圆角差异属可接受的小瑕疵，等有"真实视图预览"方案再处理。
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
