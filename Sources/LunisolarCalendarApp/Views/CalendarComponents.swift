#if canImport(SwiftUI)
import SwiftUI

struct WeekHeaderView: View {
    private let weekdays = ["日","一","二","三","四","五","六"]
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var isRegular: Bool { hSizeClass == .regular }
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { idx in
                Text(weekdays[idx])
                    .font(isRegular ? .system(size: 13, weight: .semibold, design: .rounded)
                                     : .system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(idx == 0 || idx == 6
                                     ? Color.systemRed.opacity(0.65)
                                     : Color.secondaryLabel.opacity(0.85))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, isRegular ? 10 : 8)
        .padding(.horizontal, isRegular ? 16 : 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.hairSeparator)
                .frame(height: AppTheme.Stroke.hair)
                .padding(.horizontal, isRegular ? 20 : 14)
        }
    }
}

struct DayCellView: View {
    let date: Date, isCurrentMonth: Bool, isSelected: Bool, isToday: Bool
    let lunar: LunarDate, huangli: HuangliDay
    let hasEvents: Bool, eventPriority: Priority?, eventCount: Int
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var isRegular: Bool { hSizeClass == .regular }
    private var numeralFont: Font { isRegular ? AppTheme.Font.numeralL : AppTheme.Font.numeralM }
    var body: some View {
        VStack(spacing: isRegular ? 4 : 2) {
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: isRegular ? 14 : 10, style: .continuous)
                        .fill(Color.appTint)
                        .shadow(color: Color.appTint.opacity(0.28), radius: 8, x: 0, y: 3)
                } else if isToday {
                    RoundedRectangle(cornerRadius: isRegular ? 14 : 10, style: .continuous)
                        .fill(Color.todayCapsule)
                        .overlay(
                            RoundedRectangle(cornerRadius: isRegular ? 14 : 10, style: .continuous)
                                .stroke(Color.systemRed.opacity(0.35), lineWidth: AppTheme.Stroke.hair)
                        )
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
            if hasEvents || (huangli.isAuspicious && isCurrentMonth) {
                HStack(spacing: 2) {
                    if huangli.isAuspicious && isCurrentMonth {
                        Capsule().fill(Color.auspicious.opacity(0.85))
                            .frame(width: isRegular ? 12 : 9, height: isRegular ? 5 : 4)
                    }
                    if hasEvents {
                        ForEach(0..<min(eventCount, 3), id: \.self) { _ in
                            Capsule().fill(eventPriority?.tintColor ?? Color.appTint)
                                .frame(width: isRegular ? 12 : 9, height: isRegular ? 5 : 4)
                        }
                    }
                }
                .frame(height: isRegular ? 6 : 5)
            } else {
                Color.clear.frame(height: isRegular ? 6 : 5)
            }
        }
        .padding(.vertical, isRegular ? 6 : 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(isCurrentMonth ? 1 : 0.32)
        .contentShape(Rectangle())
    }
    private var foregroundForDay: Color {
        if isSelected { return .white }
        guard isCurrentMonth else { return Color.tertiaryLabel }
        if isToday { return Color.systemRed }
        let wd = date.weekday
        if wd == 1 || wd == 7 { return Color.systemRed.opacity(0.78) }
        return Color.label
    }
    private var foregroundForLunar: Color {
        guard isCurrentMonth else { return Color.quaternaryLabel }
        if isSelected { return .white.opacity(0.9) }
        if lunar.day == 1 { return Color.festiveRed.opacity(0.9) }
        if huangli.isAuspicious { return Color.auspicious.opacity(0.92) }
        return Color.tertiaryLabel
    }
}
#endif
