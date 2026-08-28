#if canImport(SwiftUI)
import SwiftUI

// MARK: - 星期标题行

struct WeekHeaderView: View {
    private let weekdays = ["日","一","二","三","四","五","六"]
    @Environment(\.horizontalSizeClass) private var hSizeClass

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { idx in
                Text(weekdays[idx])
                    .font(hSizeClass == .regular
                          ? .body.weight(.semibold)
                          : .caption.weight(.semibold))
                    .foregroundStyle(idx == 0 || idx == 6 ? Color.systemRed : Color.secondaryLabel)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, hSizeClass == .regular ? 8 : 6)
            }
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - 单个日期单元格

struct DayCellView: View {
    let date: Date
    let isCurrentMonth: Bool
    let isSelected: Bool
    let isToday: Bool
    let lunar: LunarDate
    let huangli: HuangliDay
    let hasEvents: Bool
    let eventPriority: Priority?

    @Environment(\.horizontalSizeClass) private var hSizeClass

    /// iPad regular 宽屏字体放大；iPhone compact 保持原尺寸
    private var isRegular: Bool { hSizeClass == .regular }
    private var dayFontSize: CGFloat { isToday ? (isRegular ? 22 : 17) : (isRegular ? 20 : 16) }
    private var lunarFontSize: CGFloat { isRegular ? 12 : 9 }
    private var badgeFontSize: CGFloat { isRegular ? 10 : 8 }
    private var badgeHeight: CGFloat { isRegular ? 16 : 12 }
    private var dotSize: CGFloat { isRegular ? 7 : 5 }
    private var cellCornerRadius: CGFloat { isRegular ? 14 : 10 }

    var body: some View {
        VStack(spacing: isRegular ? 3 : 1) {
            // 公历日期 + 今日圆点
            ZStack(alignment: .topTrailing) {
                Text("\(date.day)")
                    .font(.system(size: dayFontSize, weight: isToday ? .bold : .medium))
                    .foregroundStyle(dayForegroundColor)

                if isToday {
                    Circle()
                        .fill(Color.systemRed)
                        .frame(width: dotSize, height: dotSize)
                        .padding(2)
                }
            }
            .frame(maxWidth: .infinity)

            // 农历日期 / 节日
            Text(lunar.shortDisplayString)
                .font(.system(size: lunarFontSize))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(lunarForegroundColor)

            Spacer(minLength: 2)

            // 底部：吉日 badge 或事件点（共存不重叠）
            HStack(spacing: 2) {
                if huangli.isAuspicious && isCurrentMonth {
                    Text("吉")
                        .font(.system(size: badgeFontSize, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: isRegular ? 18 : 14, height: badgeHeight)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color.auspicious)
                        )
                }
                if hasEvents {
                    Circle()
                        .fill(eventPriority?.tintColor ?? Color.systemBlue)
                        .frame(width: dotSize, height: dotSize)
                }
                if !(huangli.isAuspicious && isCurrentMonth) && !hasEvents {
                    Color.clear.frame(width: dotSize, height: dotSize)
                }
            }
            .frame(height: badgeHeight)
        }
        .padding(.vertical, isRegular ? 6 : 4)
        .frame(maxHeight: .infinity)
        .frame(maxWidth: .infinity)
        .background {
            // iOS 26 液态玻璃：选中态使用 tinted glass 替代实心半透明
            if isSelected {
                RoundedRectangle(cornerRadius: cellCornerRadius, style: .continuous)
                    .fill(Color.systemBlue.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: cellCornerRadius, style: .continuous)
                            .strokeBorder(Color.systemBlue.opacity(0.6), lineWidth: 1.2)
                    )
            }
        }
        .opacity(isCurrentMonth ? 1.0 : 0.35)
    }

    private var dayForegroundColor: Color {
        if !isCurrentMonth { return Color.secondaryLabel }
        if isToday { return Color.systemRed }
        // 周末
        let wd = date.weekday
        if wd == 1 || wd == 7 { return Color.systemRed.opacity(0.8) }
        return Color.label
    }

    private var lunarForegroundColor: Color {
        if !isCurrentMonth { return Color.tertiaryLabel }
        // 节气/初一用喜庆色
        if lunar.day == 1 { return Color.auspicious.opacity(0.85) }
        return Color.secondaryLabel
    }
}

#endif
