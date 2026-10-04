import SwiftUI

/// 月份头部：标题（可点，弹日期跳转）+ 左右翻月箭头（P4-1 抽取自 `CalendarMonthView.monthHeader`）。
///
/// **与父视图状态解耦的窄接口**：这里只说"用户点了什么"，具体怎么变仍由父视图决定——
/// 所以父视图的 `AuxiliaryPage` 类型不会泄漏进本文件的接口。
/// （对比无状态叶子视图 `CalendarSolarTermBar` / `CalendarChevronButton`：那两个可以直接搬，
///   本视图原先会写 `auxiliaryPage` / 调 `changeMonth`，属于"另一类"抽取。）
struct CalendarMonthHeader: View {
    /// 已本地化的月份名（如「10月」）——历法/语言逻辑留在父视图，这里只负责展示
    let monthName: String
    let year: Int
    let controlTint: Color
    let onTapTitle: () -> Void
    let onChangeMonth: (Int) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.md) {
            // 月份标题可点击 → 弹出日期跳转（主流日历交互：点标题选月份/年份）
            Button {
                onTapTitle()
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.sm) {
                    // 月份名走 MonthLabel（locale 感知、日历固定公历）。
                    // 原先写死 `"\(month)月"`，英文界面显示「9月」（P3-3）；
                    // 而 `Text(date, format:)` 会跟随 locale 的日历，佛历/和历下月名会错。
                    // 年份仍是 verbatim 纯数字：避免 LocalizedStringKey 对 Int 插值加千位分隔
                    // （英文 locale 下 2026 会渲染成 "2,026"）。
                    Text(verbatim: monthName)
                        .font(AppTheme.Font.hero).foregroundStyle(Color.label)
                        .contentTransition(.numericText())
                        // P3-4 续：最大辅助字号下 hero(38pt) 会缩放到 ~90pt，
                        // 不限制就会把「10月」和年份挤到折行（实测年份被折成「202」/「6」）。
                        // 单行 + 允许缩到 60%：宁可字小，也不让日期信息读不出来。
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(verbatim: "\(year)")
                        .font(AppTheme.Font.title3).foregroundStyle(Color.tertiaryLabel)
                        .contentTransition(.numericText())
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.tertiaryLabel)
                        .padding(.bottom, 6)
                        // 装饰箭头：月/年 Text 已是完整朗读内容，箭头加入只会读出符号名
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pressableFeedback()
            .accessibilityLabel("选择月份或年份")
            .accessibilityHint("打开日期跳转面板")
            Spacer()
            HStack(spacing: AppTheme.Spacing.sm) {
                Button {
                    onChangeMonth(-1)
                } label: { CalendarChevronButton(name: "chevron.left", accent: controlTint) }
                    .pressableFeedback()
                    // P1-2：⌘[ 上一月
                    .keyboardShortcut("[", modifiers: .command)
                Button {
                    onChangeMonth(1)
                } label: { CalendarChevronButton(name: "chevron.right", accent: controlTint) }
                    .pressableFeedback()
                    // P1-2：⌘] 下一月
                    .keyboardShortcut("]", modifiers: .command)
            }
        }
    }
}
