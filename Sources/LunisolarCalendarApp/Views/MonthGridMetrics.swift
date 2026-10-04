import SwiftUI

/// 月历网格的尺寸计算（P4-1 抽取自 `CalendarMonthView.elasticCellHeight`）。
///
/// 抽出来的理由：这是**纯数学**——输出的行高只取决于「iPad 布局？可视高度？已上报的
/// chrome 高度？行数？」，与任何视图状态无关。放成 `enum` 的静态函数即可单测，
/// 也让 `CalendarMonthView` 少一段与布局无关的计算。（对比 `monthColumn` / `calendarShell`：
/// 那两个持有拖拽、选中、翻月等状态，抽它们属于**状态所有权重构**，不是机械搬运。）
enum MonthGridMetrics {
    /// iPad 分栏下按可视高度弹性分配行高；其余情况返回 nil（由调用方给最小可点高度）。
    /// - Parameters:
    ///   - columnHeight: 月列可视高度（0 表示尚未测量）
    ///   - chromeHeight: 已上报的非网格高度（周表头等；0 表示尚未上报）
    static func elasticCellHeight(rows: Int,
                                  isIPadSplit: Bool,
                                  columnHeight: CGFloat,
                                  chromeHeight: CGFloat) -> CGFloat? {
        guard isIPadSplit, columnHeight > 0, rows > 0 else { return nil }
        // 卡片内外固定边距：月卡 .padding(.top, sm=8) + .padding(.bottom, lg=16)
        // 网格行距：LazyVGrid spacing（iPad 6pt / iPhone 3pt）× 行间缝隙（rows-1）
        let cardPadding: CGFloat = AppTheme.Spacing.sm + AppTheme.Spacing.lg
        let gridSpacing: CGFloat = CGFloat(rows - 1) * (isIPadSplit ? 6 : 3)
        let chrome = chromeHeight > 0
            ? chromeHeight + cardPadding + gridSpacing
            : 170 // 回退：首次布局前偏好未上报
        return min(96, max(AppTheme.Touch.minCellHeight, (columnHeight - chrome) / CGFloat(rows)))
    }
}
