#if canImport(WidgetKit)
import SwiftUI
import WidgetKit

// MARK: - Widget 统一设计规范

/// 三个小组件共用的视觉规范：
/// 由于 WidgetConfiguration 统一使用 `.contentMarginsDisabled()`，
/// 所有尺寸/样式的内边距、字号、胶囊、信息标签都从这里取，保证摆在一起时协调一致。
private enum WidgetUI {
    /// 小尺寸内边距
    static let padSmall: CGFloat = 14
    /// 中/大尺寸内边距
    static let padRegular: CGFloat = 16
    static let padLarge: CGFloat = 20

    // 字号层级（全小组件仅允许使用以下档位）
    static let overline: CGFloat = 9       // 装饰性英文/小标签
    static let meta: CGFloat = 9           // 冲煞/神位等辅助信息
    static let caption: CGFloat = 10       // 条目小字
    static let item: CGFloat = 11          // 宜忌/待办正文
    static let title: CGFloat = 12         // 区块标题
    static let dateSmall: CGFloat = 26     // small 公历日
    static let dateMedium: CGFloat = 28    // medium 公历日
    static let dateLarge: CGFloat = 40     // large 公历日
    static let lunarNumMedium: CGFloat = 48
    static let lunarNumLarge: CGFloat = 92

    /// 浅底 widget 顶部节日色淡染（深色模式下提高不透明度，避免发灰）
    static func wash(_ color: Color, in scheme: ColorScheme) -> Color {
        color.opacity(scheme == .dark ? 0.24 : 0.10)
    }
}

// MARK: - 通用组件

/// 节日胶囊：浅底用「节日色底 + 白字」，深底用「白底 + 节日字」
private struct WidgetFestivalChip: View {
    let emoji: String
    let name: String
    let accentHex: String
    var onDark: Bool = false
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 3 : 4) {
            Text(emoji).font(.system(size: compact ? 10 : 12))
            Text(name)
                .font(.system(size: compact ? 9 : 11, weight: .heavy, design: .rounded))
                .foregroundStyle(onDark ? Color(hex: accentHex) : .white)
                .lineLimit(1)
        }
        .padding(.horizontal, compact ? 5 : 8)
        .padding(.vertical, compact ? 2 : 3)
        .background(Capsule().fill(onDark ? Color.white : Color(hex: accentHex)))
    }
}

/// 深底上的半透明信息胶囊（干支、生肖等）
private struct WidgetGhostCapsule: View {
    let text: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon).font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(.system(size: WidgetUI.meta, weight: .bold))
                .lineLimit(1)
        }
        .foregroundStyle(Color.white.opacity(0.92))
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(Color.white.opacity(0.18)))
    }
}

/// 辅助信息标签（图标 + 文字）
private struct WidgetMetaLabel: View {
    let icon: String
    let text: String
    var onDark: Bool = false

    var body: some View {
        Label(text, systemImage: icon)
            .font(.system(size: WidgetUI.meta, weight: .medium))
            .foregroundStyle(onDark ? Color.white.opacity(0.72) : Color.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

/// 宜 / 忌 中式标签（衬线大字 + 淡色底）
private struct WidgetYiJiTag: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .black, design: .serif))
            .foregroundStyle(color)
            .frame(width: 20, height: 18)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(color.opacity(0.12))
            )
    }
}

/// 环形进度（与待办 widget 两处共用）
private struct WidgetProgressRing: View {
    let progress: Double
    let accent: Color
    var lineWidth: CGFloat = 8

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.18),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Circle()
                .trim(from: 0, to: max(0.001, CGFloat(progress)))
                .stroke(
                    LinearGradient(colors: [accent, accent.opacity(0.65)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - ① 今日黄历概览 Widget 视图

/// ① 今日黄历概览（systemSmall / systemMedium / systemLarge 三种尺寸）
public struct HuangliOverviewWidgetView: View {
    public let entry: LunisolarWidgetEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme

    public init(entry: LunisolarWidgetEntry) {
        self.entry = entry
    }

    private var accent: Color {
        entry.hasFestival ? Color(hex: entry.primaryFestivalHex) : Color.festiveRed
    }

    public var body: some View {
        switch family {
        case .systemSmall: smallView
        case .systemMedium: mediumView
        case .systemLarge: largeView
        default: mediumView
        }
    }

    // MARK: Small

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            header(dateSize: WidgetUI.dateSmall, lunarSize: 11)

            HStack(alignment: .top, spacing: 8) {
                yijiColumn(title: "宜",
                           items: Array(entry.huangli?.yi.prefix(2) ?? []),
                           color: accent, itemSize: WidgetUI.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Rectangle()
                    .fill(Color.themeSeparator.opacity(0.5))
                    .frame(width: 0.5)
                yijiColumn(title: "忌",
                           items: Array(entry.huangli?.ji.prefix(2) ?? []),
                           color: Color.secondary, itemSize: WidgetUI.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity, alignment: .top)

            HStack(alignment: .center, spacing: 4) {
                if let cs = entry.huangli?.displayChongSha {
                    WidgetMetaLabel(icon: "exclamationmark.shield", text: cs)
                }
                Spacer(minLength: 2)
                if let f = entry.festivals.first {
                    WidgetFestivalChip(emoji: f.emoji, name: f.name,
                                       accentHex: f.accentHex, compact: true)
                }
            }
        }
        .padding(WidgetUI.padSmall)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetBackground {
            LinearGradient(colors: [WidgetUI.wash(accent, in: scheme), Color.systemBackground],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    // MARK: Medium

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            header(dateSize: WidgetUI.dateMedium, lunarSize: 11, showsFestival: true)

            HStack(alignment: .top, spacing: 12) {
                yijiColumn(title: "宜",
                           items: Array(entry.huangli?.yi.prefix(4) ?? []),
                           color: accent, itemSize: WidgetUI.caption, rowSpacing: 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Rectangle()
                    .fill(Color.themeSeparator.opacity(0.5))
                    .frame(width: 0.5)
                yijiColumn(title: "忌",
                           items: Array(entry.huangli?.ji.prefix(4) ?? []),
                           color: Color.secondary, itemSize: WidgetUI.caption, rowSpacing: 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity, alignment: .top)

            HStack(spacing: 10) {
                if let cs = entry.huangli?.displayChongSha {
                    WidgetMetaLabel(icon: "exclamationmark.shield", text: cs)
                }
                if let cai = entry.huangli?.caiShenDirection, !cai.isEmpty {
                    WidgetMetaLabel(icon: "dollarsign.circle", text: "财神 \(cai)")
                }
                if entry.festivals.count > 1, let f2 = entry.festivals.dropFirst().first {
                    WidgetFestivalChip(emoji: f2.emoji, name: f2.name,
                                       accentHex: f2.accentHex, compact: true)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(WidgetUI.padRegular)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetBackground {
            LinearGradient(colors: [WidgetUI.wash(accent, in: scheme), Color.systemBackground],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    // MARK: Large

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                header(dateSize: WidgetUI.dateLarge, lunarSize: 14)
                Spacer(minLength: 0)
                if let f = entry.festivals.first {
                    WidgetFestivalChip(emoji: f.emoji, name: f.name, accentHex: f.accentHex)
                }
            }

            HStack(alignment: .top, spacing: 16) {
                yijiColumn(title: "宜",
                           items: Array(entry.huangli?.yi.prefix(6) ?? []),
                           color: accent, itemSize: 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Rectangle()
                    .fill(Color.themeSeparator.opacity(0.5))
                    .frame(width: 0.5)
                yijiColumn(title: "忌",
                           items: Array(entry.huangli?.ji.prefix(6) ?? []),
                           color: Color.secondary, itemSize: 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity, alignment: .top)

            HStack(spacing: 8) {
                if let cs = entry.huangli?.displayChongSha {
                    metaPill(icon: "exclamationmark.shield", text: cs)
                }
                if let wx = entry.huangli?.wuXing, !wx.isEmpty {
                    metaPill(icon: "sparkles", text: wx)
                }
                if let xi = entry.huangli?.xiShenDirection, !xi.isEmpty {
                    metaPill(icon: "face.smiling", text: "喜神 \(xi)")
                }
                if let cai = entry.huangli?.caiShenDirection, !cai.isEmpty {
                    metaPill(icon: "dollarsign.circle", text: "财神 \(cai)")
                }
                Spacer(minLength: 0)
            }
        }
        .padding(WidgetUI.padLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetBackground {
            LinearGradient(colors: [WidgetUI.wash(accent, in: scheme), Color.systemBackground],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    // MARK: 共用子视图

    private func header(dateSize: CGFloat, lunarSize: CGFloat,
                        showsFestival: Bool = false) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text("\(entry.date.day)")
                .font(.system(size: dateSize, weight: .heavy, design: .rounded))
                .foregroundStyle(accent)
                .monospacedDigit()
            VStack(alignment: .leading, spacing: 2) {
                Text("\(entry.date.month)月 \(entry.date.weekdaySymbol)")
                    .font(.system(size: WidgetUI.meta, weight: .medium))
                    .foregroundStyle(Color.secondary)
                if let lunar = entry.lunar {
                    Text("\(lunar.monthName)\(lunar.dayName)")
                        .font(.system(size: lunarSize, weight: .semibold))
                        .foregroundStyle(Color.primary)
                }
            }
            Spacer(minLength: 6)
            if showsFestival, let f = entry.festivals.first {
                WidgetFestivalChip(emoji: f.emoji, name: f.name,
                                   accentHex: f.accentHex, compact: true)
            }
        }
    }

    private func yijiColumn(title: String, items: [String], color: Color,
                            itemSize: CGFloat = WidgetUI.item,
                            rowSpacing: CGFloat = 5) -> some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            WidgetYiJiTag(title: title, color: color)
            if items.isEmpty {
                Text("诸事不宜")
                    .font(.system(size: WidgetUI.caption))
                    .foregroundStyle(Color.secondary.opacity(0.6))
            } else {
                ForEach(items, id: \.self) { it in
                    Text(it)
                        .font(.system(size: itemSize, weight: .medium))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func metaPill(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.system(size: WidgetUI.meta, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(Color.secondary)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(Color.secondary.opacity(0.10)))
    }
}

// MARK: - ② 农历日期卡片 Widget 视图

/// ② 农历日期卡片：深色节日渐变底 + 大号农历月日（small / medium / large）
public struct LunarCardWidgetView: View {
    public let entry: LunisolarWidgetEntry
    @Environment(\.widgetFamily) private var family

    public init(entry: LunisolarWidgetEntry) { self.entry = entry }

    private var accent: Color {
        entry.hasFestival ? Color(hex: entry.primaryFestivalHex) : Color.festiveRed
    }

    /// 节日色 → 同色加深，保持三个尺寸同一渐变语言
    private var gradient: LinearGradient {
        LinearGradient(
            colors: [accent, accent.opacity(0.72)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    public var body: some View {
        switch family {
        case .systemSmall: smallView
        case .systemMedium: mediumView
        case .systemLarge: largeView
        default: mediumView
        }
    }

    // MARK: Small

    private var smallView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("农历")
                    .font(.system(size: WidgetUI.overline, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .tracking(3)
                Spacer()
                if let f = entry.festivals.first {
                    Text(f.emoji).font(.system(size: 15))
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: 4) {
                if let lunar = entry.lunar {
                    Text("\(lunar.month)月\(lunar.day)")
                        .font(.system(size: 32, weight: .heavy, design: .serif))
                        .foregroundStyle(Color.white)
                        .minimumScaleFactor(0.6)
                    Text("\(lunar.monthName)\(lunar.dayName)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.85))
                } else {
                    Text("暂无数据")
                        .font(.system(size: 20, weight: .heavy, design: .serif))
                        .foregroundStyle(Color.white.opacity(0.92))
                    Text("请打开 App 刷新")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.72))
                }
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)

            HStack {
                if let f = entry.festivals.first {
                    WidgetFestivalChip(emoji: f.emoji, name: f.name,
                                       accentHex: f.accentHex, onDark: true, compact: true)
                } else if let lunar = entry.lunar {
                    WidgetGhostCapsule(text: lunar.yearGanZhi)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(WidgetUI.padSmall)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetBackground { gradient }
    }

    // MARK: Medium

    private var mediumView: some View {
        HStack(alignment: .center, spacing: 12) {
            // 左：大号农历月日
            VStack(alignment: .leading, spacing: 4) {
                Text("农 历")
                    .font(.system(size: WidgetUI.overline, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .tracking(3)
                if let lunar = entry.lunar {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(lunar.month)")
                            .font(.system(size: WidgetUI.lunarNumMedium, weight: .black, design: .serif))
                            .foregroundStyle(Color.white)
                            .minimumScaleFactor(0.7)
                        Text("月\(lunar.day)")
                            .font(.system(size: 18, weight: .heavy, design: .serif))
                            .foregroundStyle(Color.white.opacity(0.92))
                    }
                    Text("\(lunar.monthName)\(lunar.dayName)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.9))
                    Text("\(entry.date.year) 年 \(entry.date.month) 月 \(entry.date.day) 日 · \(entry.date.weekdaySymbol)")
                        .font(.system(size: WidgetUI.meta, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.6))
                } else {
                    Text("暂无数据")
                        .font(.system(size: 40, weight: .black, design: .serif))
                        .foregroundStyle(Color.white.opacity(0.95))
                    Text("请打开 App 刷新")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 右：节日 + 黄历信息（干支只在这里出现一次，避免与左侧重复）
            VStack(alignment: .trailing, spacing: 8) {
                if let f = entry.festivals.first {
                    WidgetFestivalChip(emoji: f.emoji, name: f.name,
                                       accentHex: f.accentHex, onDark: true)
                }
                if let f2 = entry.festivals.dropFirst().first {
                    Text("\(f2.emoji) \(f2.name)")
                        .font(.system(size: WidgetUI.caption, weight: .bold))
                        .foregroundStyle(Color.white)
                }
                Spacer(minLength: 0)
                if let lunar = entry.lunar {
                    WidgetGhostCapsule(text: "\(lunar.yearGanZhi)年 · \(lunar.yearAnimal)",
                                       icon: "moon.stars.fill")
                }
                VStack(alignment: .trailing, spacing: 2) {
                    if let cs = entry.huangli?.displayChongSha {
                        Text(cs)
                            .font(.system(size: WidgetUI.meta, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.8))
                    }
                    if let wx = entry.huangli?.wuXing, !wx.isEmpty {
                        Text(wx)
                            .font(.system(size: WidgetUI.meta, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.65))
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .trailing)
        }
        .padding(WidgetUI.padRegular)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetBackground { gradient }
    }

    // MARK: Large

    private var largeView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("农 历")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .tracking(4)
                Spacer()
                if let f = entry.festivals.first {
                    WidgetFestivalChip(emoji: f.emoji, name: f.name,
                                       accentHex: f.accentHex, onDark: true)
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: 8) {
                if let lunar = entry.lunar {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(lunar.month)")
                            .font(.system(size: WidgetUI.lunarNumLarge, weight: .black, design: .serif))
                            .foregroundStyle(Color.white)
                            .minimumScaleFactor(0.6)
                        Text("月\(lunar.day)")
                            .font(.system(size: 30, weight: .heavy, design: .serif))
                            .foregroundStyle(Color.white.opacity(0.92))
                    }
                    Text("\(lunar.monthName)\(lunar.dayName)")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.92))
                    WidgetGhostCapsule(text: "\(lunar.yearGanZhi)年 · 生肖\(lunar.yearAnimal)",
                                       icon: "moon.stars.fill")
                    Text("\(entry.date.year) 年 \(entry.date.month) 月 \(entry.date.day) 日 · \(entry.date.weekdaySymbol)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.62))
                } else {
                    Text("暂无数据")
                        .font(.system(size: 44, weight: .black, design: .serif))
                        .foregroundStyle(Color.white)
                    Text("请打开 App 刷新")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if let cs = entry.huangli?.displayChongSha {
                    WidgetMetaLabel(icon: "exclamationmark.shield", text: cs, onDark: true)
                }
                if let wx = entry.huangli?.wuXing, !wx.isEmpty {
                    WidgetMetaLabel(icon: "sparkles", text: wx, onDark: true)
                }
                Spacer(minLength: 0)
                if let f2 = entry.festivals.dropFirst().first {
                    Text("\(f2.emoji) \(f2.name)")
                        .font(.system(size: WidgetUI.caption, weight: .bold))
                        .foregroundStyle(Color.white)
                }
            }
        }
        .padding(WidgetUI.padLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetBackground { gradient }
    }
}

// MARK: - ③ 今日待办进度 Widget 视图

/// ③ 今日待办进度：环形进度 + 完成/总数 + 最近待办（small / medium / large）
public struct TodoProgressWidgetView: View {
    public let entry: LunisolarWidgetEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme

    public init(entry: LunisolarWidgetEntry) { self.entry = entry }

    private var accent: Color {
        entry.hasFestival ? Color(hex: entry.primaryFestivalHex) : Color.systemGreen
    }

    public var body: some View {
        switch family {
        case .systemSmall: smallView
        case .systemMedium: mediumView
        case .systemLarge: largeView
        default: mediumView
        }
    }

    // MARK: Small

    private var smallView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("今日待办")
                    .font(.system(size: WidgetUI.title, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.primary)
                Spacer()
                if let f = entry.festivals.first {
                    Text(f.emoji).font(.system(size: 13))
                }
            }

            WidgetProgressRing(progress: entry.progress, accent: accent, lineWidth: 8)
                .overlay {
                    VStack(spacing: 1) {
                        Text("\(Int(entry.progress * 100))%")
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundStyle(accent)
                            .monospacedDigit()
                        Text("\(entry.completedCount)/\(entry.todaysEventsCount)")
                            .font(.system(size: WidgetUI.meta, weight: .semibold))
                            .foregroundStyle(Color.secondary)
                            .monospacedDigit()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text(progressHintText)
                .font(.system(size: WidgetUI.caption, weight: .medium))
                .foregroundStyle(Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(WidgetUI.padSmall)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetBackground {
            LinearGradient(colors: [WidgetUI.wash(accent, in: scheme), Color.systemBackground],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    // MARK: Medium

    private var mediumView: some View {
        HStack(alignment: .center, spacing: 14) {
            // 左：进度环
            VStack(spacing: 4) {
                Text("今日待办")
                    .font(.system(size: WidgetUI.title, weight: .heavy, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
                WidgetProgressRing(progress: entry.progress, accent: accent, lineWidth: 9)
                    .overlay {
                        VStack(spacing: 0) {
                            Text("\(Int(entry.progress * 100))%")
                                .font(.system(size: 19, weight: .black, design: .rounded))
                                .foregroundStyle(accent)
                                .monospacedDigit()
                            Text("\(entry.completedCount)/\(entry.todaysEventsCount)")
                                .font(.system(size: WidgetUI.meta, weight: .semibold))
                                .foregroundStyle(Color.secondary)
                                .monospacedDigit()
                        }
                    }
                    .frame(width: 76, height: 76)
                Text(progressHintText)
                    .font(.system(size: WidgetUI.meta, weight: .medium))
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
            }
            .frame(width: 100)

            Rectangle()
                .fill(Color.themeSeparator.opacity(0.5))
                .frame(width: 0.5)

            // 右：3 条待办 + 底部信息
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(displayTodoRows(pick: 3).enumerated()), id: \.offset) { _, row in
                    todoRow(row)
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    if let f = entry.festivals.first {
                        WidgetFestivalChip(emoji: f.emoji, name: f.name,
                                           accentHex: f.accentHex, compact: true)
                    }
                    Spacer(minLength: 0)
                    if let cs = entry.huangli?.displayChongSha {
                        WidgetMetaLabel(icon: "exclamationmark.shield", text: cs)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(WidgetUI.padRegular)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetBackground {
            LinearGradient(colors: [WidgetUI.wash(accent, in: scheme), Color.systemBackground],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    // MARK: Large

    private var largeView: some View {
        VStack(spacing: 12) {
            // 顶部：进度环 + 统计
            HStack(spacing: 16) {
                WidgetProgressRing(progress: entry.progress, accent: accent, lineWidth: 10)
                    .overlay {
                        Text("\(Int(entry.progress * 100))%")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(accent)
                            .monospacedDigit()
                    }
                    .frame(width: 92, height: 92)

                VStack(alignment: .leading, spacing: 4) {
                    Text("今日待办")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                    Text("已完成 \(entry.completedCount) / \(entry.todaysEventsCount) 项")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                        .monospacedDigit()
                    Text(progressHintText)
                        .font(.system(size: WidgetUI.item, weight: .medium))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let f = entry.festivals.first {
                    Text(f.emoji).font(.system(size: 26))
                }
            }

            Rectangle()
                .fill(Color.themeSeparator.opacity(0.5))
                .frame(height: 0.5)

            // 中部：最多 5 条待办
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(displayTodoRows(pick: 5).enumerated()), id: \.offset) { _, row in
                    todoRow(row)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // 底部：节日 + 冲煞
            HStack(spacing: 8) {
                if let f = entry.festivals.first {
                    WidgetFestivalChip(emoji: f.emoji, name: f.name, accentHex: f.accentHex)
                }
                Spacer(minLength: 0)
                if let cs = entry.huangli?.displayChongSha {
                    WidgetMetaLabel(icon: "exclamationmark.shield", text: cs)
                }
            }
        }
        .padding(WidgetUI.padLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetBackground {
            LinearGradient(colors: [WidgetUI.wash(accent, in: scheme), Color.systemBackground],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    // MARK: 辅助

    private struct DisplayRow: Hashable {
        let title: String
        let done: Bool
        let priorityHex: String
    }

    /// 取主 App 写的前 `pick` 条，不够就用占位/黄历提示补齐
    private func displayTodoRows(pick: Int) -> [DisplayRow] {
        var rows: [DisplayRow] = entry.topTitles.prefix(pick).map {
            DisplayRow(title: $0.title, done: $0.isCompleted, priorityHex: $0.priorityHex)
        }
        if rows.count < pick {
            let fallbacks: [DisplayRow] = [
                DisplayRow(title: "打开 App 查看今日日程", done: true,  priorityHex: "#6B7280"),
                DisplayRow(title: "长按小组件可切换尺寸样式", done: false, priorityHex: "#2563EB"),
                DisplayRow(title: "今日宜 \(entry.huangli?.yi.first ?? "祭祀")", done: false, priorityHex: "#D97706"),
                DisplayRow(title: "规划一下明天的安排", done: false, priorityHex: "#6B7280"),
                DisplayRow(title: "记得喝水、起身活动", done: false, priorityHex: "#22A06B")
            ]
            for f in fallbacks where rows.count < pick { rows.append(f) }
        }
        return Array(rows.prefix(pick))
    }

    private var progressHintText: String {
        if entry.todaysEventsCount == 0 {
            return "今日还没安排 · 打开 App 添加 ✨"
        } else if entry.progress >= 1.0 {
            return "已全部完成 🎉 给自己加个鸡腿"
        } else if entry.progress >= 0.5 {
            return "进度过半，继续加油 💪"
        } else {
            return "开工啦，一步一步来 ☕️"
        }
    }

    /// 单行待办：仅一个状态图标（修复旧版「手画圆圈 + SF 圆圈」双圈重叠）
    private func todoRow(_ row: DisplayRow) -> some View {
        HStack(spacing: 8) {
            Image(systemName: row.done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(row.done
                                 ? Color(hex: row.priorityHex)
                                 : Color(hex: row.priorityHex).opacity(0.55))
            Text(row.title)
                .font(.system(size: WidgetUI.item, weight: .medium))
                .foregroundStyle(row.done ? Color.secondary : Color.primary)
                .strikethrough(row.done, color: Color.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - widgetBackground 兼容辅助

private extension View {
    /// iOS 17+ 使用 containerBackground（Widget 圆角由系统裁剪）；旧系统 background 兜底
    @ViewBuilder
    func widgetBackground<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            self.containerBackground(for: .widget) { content() }
        } else {
            self.background(content())
        }
    }
}
#endif
