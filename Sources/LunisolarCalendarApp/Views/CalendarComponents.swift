#if canImport(SwiftUI)
import SwiftUI

// MARK: - 星期标题行

struct WeekHeaderView: View {
    private let weekdays = ["日","一","二","三","四","五","六"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { idx in
                Text(weekdays[idx])
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(idx == 0 || idx == 6 ? Color.systemRed : Color.secondaryLabel)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
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

    private let size: CGFloat = ScreenHelper.width / 7 - 6

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // 选中背景
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.systemBlue.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.systemBlue, lineWidth: 1.5)
                    )
            }

            VStack(spacing: 1) {
                // 公历日期
                Text("\(date.day)")
                    .font(isToday ? .system(size: 17, weight: .bold) : .system(size: 16, weight: .medium))
                    .foregroundStyle(dayForegroundColor)

                // 农历日期 / 节日
                Text(lunar.shortDisplayString)
                    .font(.system(size: 9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(lunarForegroundColor)

                Spacer(minLength: 2)

                // 黄道吉日标记
                if huangli.isAuspicious && isCurrentMonth {
                    Text("吉")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 0.5)
                        .background(
                            Capsule().fill(Color.auspicious)
                        )
                }

                // 事件指示点（按优先级颜色）
                if hasEvents {
                    Circle()
                        .fill(eventPriority?.tintColor ?? Color.systemBlue)
                        .frame(width: 5, height: 5)
                        .padding(.bottom, 2)
                } else {
                    Color.clear.frame(width: 5, height: 5).padding(.bottom, 2)
                }
            }
            .padding(.vertical, 4)
            .frame(height: size * 1.05)
            .frame(maxWidth: .infinity)

            // 今日标记
            if isToday {
                Circle()
                    .fill(Color.systemRed)
                    .frame(width: 5, height: 5)
                    .padding(6)
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
