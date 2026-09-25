#if canImport(SwiftUI)
import SwiftUI
import LunarCore

struct WeekHeaderView: View {
    /// 每周起始日（Calendar weekday 语义：1=周日，2=周一）
    var weekStart: Int = 1
    private let weekdays = ["日","一","二","三","四","五","六"]
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var isRegular: Bool { hSizeClass == .regular }
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { idx in
                // 按起始日旋转顺序；weekday 1=周日 / 7=周六 恒为红色（周末语义与起始日无关）
                let wd = ((idx + weekStart - 1) % 7) + 1
                Text(weekdays[wd - 1])
                    // 复用 AppTheme.Font 阶梯（caption/caption2），避免散落硬编码
                    .font(isRegular ? AppTheme.Font.caption : AppTheme.Font.caption2)
                    .foregroundStyle(wd == 1 || wd == 7
                                     ? Color.systemRed.opacity(0.65)
                                     : Color.secondaryLabel.opacity(0.85))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, isRegular ? 10 : 8)
        .padding(.horizontal, isRegular ? AppTheme.Spacing.lg : AppTheme.Spacing.md)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.hairSeparator)
                .frame(height: AppTheme.Stroke.hair)
                .padding(.horizontal, isRegular ? AppTheme.Spacing.xl : AppTheme.Spacing.lg)
        }
    }
}

// MARK: - 法定假日徽章（抽取自 DayCellView，消除两处重复的"休/班"圆形代码）

struct HolidayBadge: View {
    let type: HolidayType
    let isRegular: Bool

    var body: some View {
        Text(type == .holiday ? String(localized: "休") : String(localized: "班"))
            .font(.system(size: isRegular ? 9 : 8, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: isRegular ? 14 : 12, height: isRegular ? 14 : 12)
            .background(
                Circle().fill(type == .holiday ? Color.systemGreen : Color.systemOrange)
            )
    }
}

struct DayCellView: View {
    let date: Date, isCurrentMonth: Bool, isSelected: Bool, isToday: Bool
    let lunar: LunarDate, huangli: HuangliDay
    let hasEvents: Bool, eventPriorities: [Priority], eventCount: Int
    /// 节日强调色（选中节日日的实心框颜色；常态不再染背景）
    var festivalTint: Color? = nil
    var cellAccent: Color? = nil
    /// 节假日名（如"中秋节"）：节日当天格内只显示节日名，不显示农历
    var festivalName: String? = nil
    /// 节气名（如"秋分"）：格内只显示节气名，不显示农历
    var solarTermName: String? = nil
    /// 节气主题色（绿色系）
    var solarTermTint: Color? = nil
    /// 法定假日/调休标记
    var holidayType: HolidayType = .normal
    @Environment(\.horizontalSizeClass) private var hSizeClass
    // 日历显示开关（设置 → 日历，设计稿 04）：关闭后对应标注在月历格内隐藏
    @AppStorage("Lunisolar.showLunar") private var showLunar = true
    @AppStorage("Lunisolar.showSolarTerm") private var showSolarTerm = true
    @AppStorage("Lunisolar.showHoliday") private var showHoliday = true
    private var isRegular: Bool { hSizeClass == .regular }
    private var numeralFont: Font { isRegular ? AppTheme.Font.numeralL : AppTheme.Font.numeralM }
    /// 底色：仅「选中」实心填充；今日态红描边区分；**节日/节气不再浅染背景**
    /// （用户要求：除点击选择的日期外都不要"选择框"式展示）
    private var fillTint: Color? {
        if isSelected { return cellAccent ?? Color.appTint }
        return nil
    }
    var body: some View {
        // 按用户显示开关过滤节日/节气名；关开关时退化为农历显示
        let effFestival = showHoliday ? festivalName : nil
        let effTerm = showSolarTerm ? solarTermName : nil
        // 选中/今日背景挂在整个格子（公历 + 农历 + 事件行）外层：
        // 农历与公历同框，选中框内农历/名称白字可见；节日/节气以格内文字标注区分。
        // 休/班徽章改为日期**右上角**显示（用户要求：从底部移到右上角）。
        ZStack(alignment: .topTrailing) {
            VStack(spacing: isRegular ? 4 : 2) {
                Text("\(date.day)")
                    .font(numeralFont)
                    .foregroundStyle(foregroundForDay)
                if lunar.isUnsupported {
                    // 越界（1900 前 / 2100 后）：不显示农历，避免假农历误导
                    Color.clear.frame(height: isRegular ? 14 : 12)
                } else if !showLunar, effFestival == nil, effTerm == nil {
                    // 用户关闭「显示农历」：无节日/节气时占空位保持高度一致
                    Color.clear.frame(height: isRegular ? 14 : 12)
                } else if let festivalName = effFestival, let term = effTerm {
                    // 节气与节日同日并存：同行显示"节日名 ·节气名"（节日色 + 绿色）
                    HStack(spacing: 2) {
                        Text(festivalName == term ? term : festivalName)
                            .foregroundStyle(
                                isSelected
                                    ? Color.white.opacity(0.95)
                                    : (festivalTint ?? Color.festiveRed)
                            )
                        if festivalName != term {
                            Text("·\(term)")
                                .foregroundStyle(
                                    isSelected
                                        ? Color.white.opacity(0.95)
                                        : (solarTermTint ?? Color.systemGreen)
                                )
                        }
                    }
                    .font(isRegular ? AppTheme.Font.caption : AppTheme.Font.caption2)
                    .lineLimit(1).minimumScaleFactor(0.6)
                } else if let festivalName = effFestival {
                    // 节假日当天：只显示节日名（节日色），不显示农历
                    Text(festivalName)
                        .font(isRegular ? AppTheme.Font.caption : AppTheme.Font.caption2)
                        .foregroundStyle(
                            isSelected
                                ? Color.white.opacity(0.95)
                                : (festivalTint ?? Color.festiveRed)
                        )
                        .lineLimit(1).minimumScaleFactor(0.6)
                } else if let term = effTerm {
                    // 节气日：只显示节气名（绿色），不显示农历
                    Text(term)
                        .font(isRegular ? AppTheme.Font.caption : AppTheme.Font.caption2)
                        .foregroundStyle(
                            isSelected
                                ? Color.white.opacity(0.95)
                                : (solarTermTint ?? Color.systemGreen)
                        )
                        .lineLimit(1).minimumScaleFactor(0.6)
                } else {
                    Text(lunar.shortDisplayString)
                        .font(isRegular ? AppTheme.Font.caption : AppTheme.Font.caption2)
                        .foregroundStyle(foregroundForLunar)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                if hasEvents {
                    HStack(spacing: 3) {
                        ForEach(0..<min(eventCount, 3), id: \.self) { i in
                            // 事件圆点：逐个按各自事件优先级着色，与"当日安排"列表竖线颜色对应
                            // （此前用 Capsule 画成短横条，视觉上像下划线；改为实心圆点更清晰）
                            Circle().fill(i < eventPriorities.count
                                          ? eventPriorities[i].tintColor
                                          : Color.appTint)
                                .frame(width: isRegular ? 5 : 4, height: isRegular ? 5 : 4)
                        }
                    }
                    .frame(height: isRegular ? 6 : 5)
                } else {
                    Color.clear.frame(height: isRegular ? 6 : 5)
                }
            }
            .padding(.vertical, isRegular ? 6 : 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(dayCellBackground)

            // 休/班徽章：日期右上角（随格子整体淡显）
            if holidayType != .normal {
                HolidayBadge(type: holidayType, isRegular: isRegular)
                    .padding(.top, isRegular ? 6 : 4)
                    .padding(.trailing, isRegular ? 6 : 4)
            }
        }
        .opacity(isCurrentMonth ? 1 : 0.32)
        // 选中弹簧回弹：切换瞬间轻微放大（1.05）并带阻尼振荡，增强"选中物理感"；
        // 值动画只作用于 isSelected 变化时刻，非选中格不受影响
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.34, dampingFraction: 0.52, blendDuration: 0.12),
                   value: isSelected)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(date.day)日 \(lunar.shortDisplayString)\(hasEvents ? " \(eventCount)项日程" : "")\(isToday ? " 今天" : "")")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// 格子背景（整格包裹公历+农历+事件行）：
    /// 仅「选中」实心填充；今日红色描边；节日/节气以格内文字标注区分，不再浅染背景。
    @ViewBuilder
    private var dayCellBackground: some View {
        if let fill = fillTint {
            // fillTint 仅在选中态非空；选中节日日沿用节日色实心框
            let shape = RoundedRectangle(cornerRadius: isRegular ? 14 : 10, style: .continuous)
            shape
                .fill(fill)
                .overlay {
                    shape.stroke(Color.white.opacity(0.28), lineWidth: AppTheme.Stroke.hair)
                }
                .shadow(color: (cellAccent ?? Color.appTint).opacity(0.22),
                        radius: 5, x: 0, y: 2)
        } else if isToday {
            // 今日：红色描边圆角（无填充），与「选中实心」区分
            RoundedRectangle(cornerRadius: isRegular ? 14 : 10, style: .continuous)
                .stroke(Color.systemRed.opacity(0.55), lineWidth: isRegular ? 2 : 1.5)
        }
    }
    private var foregroundForDay: Color {
        if isSelected { return .white }
        guard isCurrentMonth else { return Color.tertiaryLabel }
        if let ft = festivalTint { return ft }
        if isToday { return Color.systemRed }
        let wd = date.weekday
        if wd == 1 || wd == 7 { return Color.systemRed.opacity(0.78) }
        return Color.label
    }
    private var foregroundForLunar: Color {
        guard isCurrentMonth else { return Color.quaternaryLabel }
        if isSelected { return .white.opacity(0.9) }
        if lunar.day == 1 { return Color.festiveRed.opacity(0.9) }
        if let ft = festivalTint { return ft.opacity(0.92) }
        return Color.tertiaryLabel
    }
}

// Equatable + 调用处 .equatable()：横滑期间父视图每帧重新提交 42 个 cell，
// 但网格派生数据已缓存、各入参逐帧相同，SwiftUI 可据此整体跳过 cell body 求值。
// horizontalSizeClass 来自 environment，不参与比较——environment 变化时
// SwiftUI 会绕过 equatable 短路直接刷新（iPad 分屏旋转不受影响）。
extension DayCellView: Equatable {
    // 参与比较的全是不可变 Sendable 值，nonisolated 满足 Swift 6 协议见证隔离要求；
    // 比较本身也必须是同步的（.equatable() 在视图提交时同步调用）。
    nonisolated static func == (lhs: DayCellView, rhs: DayCellView) -> Bool {
        lhs.date == rhs.date
            && lhs.isCurrentMonth == rhs.isCurrentMonth
            && lhs.isSelected == rhs.isSelected
            && lhs.isToday == rhs.isToday
            && lhs.lunar == rhs.lunar
            && lhs.huangli == rhs.huangli
            && lhs.festivalName == rhs.festivalName
            && lhs.solarTermName == rhs.solarTermName
            && lhs.hasEvents == rhs.hasEvents
            && lhs.eventPriorities == rhs.eventPriorities
            && lhs.eventCount == rhs.eventCount
            && lhs.festivalTint == rhs.festivalTint
            && lhs.cellAccent == rhs.cellAccent
            && lhs.holidayType == rhs.holidayType
    }
}
#endif
