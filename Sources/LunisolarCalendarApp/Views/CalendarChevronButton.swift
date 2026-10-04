import SwiftUI

/// 月份切换箭头（P4-1：抽取自 `CalendarMonthView.chevronButton`）。
///
/// 与 `CalendarSolarTermBar` 同类：**只依赖入参、不持有状态**，
/// 所以可以整块搬运而不用动状态所有权。（对比 `monthHeader`——它会写父视图状态，
/// 抽取时必须改成 Binding + 回调，属于另一类改动，见评估文档。）
struct CalendarChevronButton: View {
    let name: String
    let accent: Color

    var body: some View {
        Image(systemName: name).font(.title2.weight(.semibold)).foregroundStyle(accent)
            .frame(width: AppTheme.Touch.minTarget, height: AppTheme.Touch.minTarget)
            .contentShape(Circle())
            .accessibilityLabel(name == "chevron.left" ? String(localized: "上个月") : String(localized: "下个月"))
    }
}
