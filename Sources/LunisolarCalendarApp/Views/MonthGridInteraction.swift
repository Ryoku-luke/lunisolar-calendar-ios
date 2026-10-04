import SwiftUI

/// 月历网格的**交互态**（P4-1 第 5b 步，第一小步）。
///
/// 为什么单独成一个模型：`monthColumn` / `calendarShell` 之所以难以抽取，正是因为
/// 它们与这些交互态（拖拽位移、翻页方向、宽度测量、可视高度测量）缠绕在一起，
/// 估算下来要 13 个输入 + 6 个回调 + 1 个手势类型。把这些**状态**先集中起来，
/// 视图抽取才会退化成"传一个模型 + 几个回调"。
///
/// 注意区分：这里只放**交互态**。`selectedDate` / `currentMonth` / `auxiliaryPage` /
/// `eventEditSheet` / `gridCache` 属于数据态或派生数据，仍留在视图里。
@Observable
final class MonthGridInteraction {
    /// 拖拽位移（跟手 1:1）
    var dragOffsetX: CGFloat = 0
    /// 是否正在拖动（决定缩放与翻转判定）
    var isDragging = false
    /// 本页滑出方向（transition 用）
    var monthSlideEdge: Edge = .trailing
    /// 预渲染的相邻月（nil 表示未拖动）
    var previewMonth: Date?
    /// 月列容器宽度（翻页阈值用）
    var monthWidth: CGFloat = 0
    /// 月列可视高度（弹性行高用）
    var columnHeight: CGFloat = 0
    /// 已上报的非网格高度（周表头等）
    var chromeHeight: CGFloat = 0
}
