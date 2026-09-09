#if canImport(SwiftUI)
import SwiftUI
import LunarCore

struct WeekHeaderView: View {
    private let weekdays = ["日","一","二","三","四","五","六"]
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var isRegular: Bool { hSizeClass == .regular }
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { idx in
                Text(weekdays[idx])
                    // 复用 AppTheme.Font 阶梯（caption/caption2），避免散落硬编码
                    .font(isRegular ? AppTheme.Font.caption : AppTheme.Font.caption2)
                    .foregroundStyle(idx == 0 || idx == 6
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
        Text(type == .holiday ? "休" : "班")
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
    let hasEvents: Bool, eventPriority: Priority?, eventCount: Int
    /// 节日强调色（优先）；选中态下与外层节日强调色联动
    var festivalTint: Color? = nil
    var cellAccent: Color? = nil
    /// 法定假日/调休标记
    var holidayType: HolidayType = .normal
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var isRegular: Bool { hSizeClass == .regular }
    private var numeralFont: Font { isRegular ? AppTheme.Font.numeralL : AppTheme.Font.numeralM }
    /// 节日染色强度：节日态 12% / 选中态使用 cellAccent
    private var fillTint: Color? {
        if isSelected { return cellAccent ?? Color.appTint }
        if let festivalTint { return festivalTint }
        if isToday { return Color.systemRed.opacity(0.12) }
        return nil
    }
    var body: some View {
        VStack(spacing: isRegular ? 4 : 2) {
            ZStack {
                if let fill = fillTint {
                    let shape = RoundedRectangle(cornerRadius: isRegular ? 14 : 10, style: .continuous)
                    ZStack {
                        shape.fill(isSelected ? fill : fill.opacity(0.14))
                        if isSelected {
                            shape
                                .stroke(Color.white.opacity(0.28), lineWidth: AppTheme.Stroke.hair)
                        } else if festivalTint != nil {
                            shape
                                .stroke(fill.opacity(0.45), lineWidth: AppTheme.Stroke.hair)
                        } else if isToday {
                            shape
                                .stroke(Color.systemRed.opacity(0.35), lineWidth: AppTheme.Stroke.hair)
                        }
                    }
                    .shadow(color: isSelected
                            ? (cellAccent ?? Color.appTint).opacity(0.28)
                            : Color.black.opacity(0.0),
                            radius: isSelected ? 8 : 0, x: 0, y: isSelected ? 3 : 0)
                }
                Text("\(date.day)")
                    .font(numeralFont)
                    .foregroundStyle(foregroundForDay)
            }
            .frame(height: isRegular ? 40 : 34).frame(maxWidth: .infinity)
            Text(lunar.shortDisplayString)
                .font(isRegular ? AppTheme.Font.caption : AppTheme.Font.caption2)
                .foregroundStyle(foregroundForLunar)
                .lineLimit(1).minimumScaleFactor(0.6)
            if hasEvents {
                HStack(spacing: 2) {
                    ForEach(0..<min(eventCount, 3), id: \.self) { _ in
                        Capsule().fill(eventPriority?.tintColor ?? Color.appTint)
                            .frame(width: isRegular ? 12 : 9, height: isRegular ? 5 : 4)
                    }
                    if holidayType != .normal {
                        HolidayBadge(type: holidayType, isRegular: isRegular)
                    }
                }
                .frame(height: isRegular ? 6 : 5)
            } else if holidayType != .normal {
                HolidayBadge(type: holidayType, isRegular: isRegular)
            } else {
                Color.clear.frame(height: isRegular ? 6 : 5)
            }
        }
        .padding(.vertical, isRegular ? 6 : 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(isCurrentMonth ? 1 : 0.32)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(date.day)日 \(lunar.shortDisplayString)\(hasEvents ? " \(eventCount)项日程" : "")\(isToday ? " 今天" : "")")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
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
#endif
