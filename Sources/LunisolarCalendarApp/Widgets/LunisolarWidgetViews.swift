#if canImport(WidgetKit)
import SwiftUI
import WidgetKit

// MARK: - ① 今日黄历概览 Widget 视图

/// ① 今日黄历概览（systemSmall / systemMedium 两种尺寸）
///   Small: 宜/忌 各 2 条 + 冲煞
///   Medium: 宜/忌 各 4 条 + 冲煞 + 喜神财神位 + 节日
public struct HuangliOverviewWidgetView: View {
    public let entry: LunisolarWidgetEntry
    @Environment(\.widgetFamily) private var family

    public init(entry: LunisolarWidgetEntry) {
        self.entry = entry
    }

    private var accent: Color {
        entry.hasFestival ? Color(hex: entry.primaryFestivalHex) : Color.systemRed
    }
    private var bgTop: Color {
        entry.hasFestival ? Color(hex: entry.primaryFestivalHex).opacity(0.14) : Color(red: 0.97, green: 0.92, blue: 0.85)
    }

    public var body: some View {
        switch family {
        case .systemSmall: smallView
        case .systemMedium: mediumView
        case .systemLarge: mediumView
        default: mediumView
        }
    }

    // MARK: - Small

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: 日期 + 农历
            headerLine(dateSize: 22)

            // 宜/忌 2×2 紧凑格
            HStack(alignment: .top, spacing: 4) {
                yijiBlock(title: "宜", items: Array(entry.huangli?.yi.prefix(2) ?? []), color: accent)
                yijiBlock(title: "忌", items: Array(entry.huangli?.ji.prefix(2) ?? []), color: Color.secondary)
            }
            .frame(maxHeight: .infinity, alignment: .top)

            // 冲煞/节日一行
            HStack(spacing: 4) {
                Text(entry.huangli?.displayChongSha ?? "冲煞")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.secondary)
                Spacer(minLength: 0)
                ForEach(Array(entry.festivals.enumerated()), id: \.offset) { _, f in
                    Text("\(f.emoji)\(f.name)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(Color(hex: f.accentHex)))
                        .lineLimit(1)
                }
            }
        }
        .widgetBackground {
            LinearGradient(colors: [bgTop, Color.systemBackground], startPoint: .top, endPoint: .bottom)
        }
    }

    // MARK: - Medium

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerLine(dateSize: 26)

            HStack(alignment: .top, spacing: 10) {
                yijiBlock(title: "宜", items: Array(entry.huangli?.yi.prefix(4) ?? []), color: accent, wide: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Divider().frame(width: 1)
                yijiBlock(title: "忌", items: Array(entry.huangli?.ji.prefix(4) ?? []), color: Color.secondary, wide: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                Label(entry.huangli?.displayChongSha ?? "冲煞", systemImage: "exclamationmark.shield")
                    .font(.caption2)
                    .foregroundStyle(Color.secondary)
                Spacer()
                Label(entry.huangli?.shenWei ?? "", systemImage: "location.circle")
                    .font(.caption2)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }

            if !entry.festivals.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(entry.festivals.enumerated()), id: \.offset) { _, f in
                        HStack(spacing: 4) {
                            Text(f.emoji)
                            Text(f.name)
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: f.accentHex), Color(hex: f.accentHex).opacity(0.75)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(Capsule())
                    }
                    Spacer()
                }
            }
        }
        .widgetBackground {
            LinearGradient(colors: [bgTop, Color.systemBackground], startPoint: .top, endPoint: .bottom)
        }
    }

    // MARK: - Header

    private func headerLine(dateSize: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text("\(entry.date.day)")
                .font(.system(size: dateSize, weight: .heavy, design: .rounded))
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(entry.date.month)月 \(entry.date.weekdaySymbol)")
                    .font(.caption2)
                    .foregroundStyle(Color.secondary)
                Text(entry.lunar?.displayString ?? "农历未知")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.primary)
            }
            Spacer(minLength: 0)
            if entry.huangli?.isAuspicious == true {
                Label("黄道", systemImage: "star.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(accent))
            }
        }
    }

    // MARK: - 宜忌块

    private func yijiBlock(title: String, items: [String], color: Color, wide: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: wide ? 13 : 11, weight: .black, design: .serif))
                .foregroundStyle(color)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(color.opacity(0.12))
                )
            if items.isEmpty {
                Text("诸事不宜")
                    .font(.system(size: wide ? 11 : 9))
                    .foregroundStyle(Color.secondary.opacity(0.6))
            } else {
                ForEach(items, id: \.self) { it in
                    Text("· " + it)
                        .font(.system(size: wide ? 12 : 10, weight: .medium))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                }
            }
        }
    }
}

// MARK: - ② 农历日期卡片 Widget 视图

/// ② 农历日期卡片：大号月日 + 节日 + 干支
public struct LunarCardWidgetView: View {
    public let entry: LunisolarWidgetEntry
    @Environment(\.widgetFamily) private var family

    public init(entry: LunisolarWidgetEntry) { self.entry = entry }

    private var accent: Color {
        entry.hasFestival ? Color(hex: entry.primaryFestivalHex) : Color.systemRed
    }

    public var body: some View {
        switch family {
        case .systemSmall: smallView
        case .systemMedium: mediumView
        default: mediumView
        }
    }

    private var smallView: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [
                    entry.hasFestival ? Color(hex: entry.primaryFestivalHex).opacity(0.92) : Color(red: 0.77, green: 0.10, blue: 0.10),
                    entry.hasFestival ? Color(hex: entry.primaryFestivalHex).opacity(0.65) : Color(red: 0.55, green: 0.08, blue: 0.08)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .widgetBackground()

            VStack(alignment: .center, spacing: 2) {
                Text("农历")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .tracking(2)
                Text("\(entry.lunar?.month ?? 0)月\(entry.lunar?.day ?? 0)")
                    .font(.system(size: 28, weight: .heavy, design: .serif))
                    .foregroundStyle(Color.white)
                Text(entry.lunar?.displayString ?? "")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Spacer()
                if let f = entry.festivals.first {
                    HStack(spacing: 3) {
                        Text(f.emoji).font(.system(size: 14))
                        Text(f.name)
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(Color(hex: f.accentHex))
                    }
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Capsule().fill(Color.white))
                } else {
                    if entry.huangli?.isAuspicious == true {
                        Label("吉日", systemImage: "star.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill(Color.white))
                    }
                }
            }
            .padding(10)
        }
    }

    private var mediumView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    entry.hasFestival ? Color(hex: entry.primaryFestivalHex) : Color(red: 0.77, green: 0.10, blue: 0.10),
                    entry.hasFestival ? Color(hex: entry.primaryFestivalHex).opacity(0.6) : Color(red: 0.45, green: 0.06, blue: 0.06)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .widgetBackground()

            HStack(spacing: 0) {
                // 左：月日大号
                VStack(alignment: .leading, spacing: 3) {
                    Text("LUNAR CALENDAR")
                        .font(.system(size: 7, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .tracking(1.5)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(entry.lunar?.month ?? 0)")
                            .font(.system(size: 60, weight: .black, design: .serif))
                            .foregroundStyle(Color.white)
                        Text("月\(entry.lunar?.day ?? 0)")
                            .font(.system(size: 20, weight: .heavy, design: .serif))
                            .foregroundStyle(Color.white.opacity(0.92))
                    }
                    Text(entry.lunar?.yearGanZhi ?? "")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.78))
                    Text("\(entry.date.year) 年 \(entry.date.month) 月 \(entry.date.day) 日 · \(entry.date.weekdaySymbol)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.62))
                }
                .padding(.leading, 18)

                Spacer()

                // 右：节日+黄历关键信息
                VStack(alignment: .trailing, spacing: 7) {
                    if let f = entry.festivals.first {
                        HStack(spacing: 6) {
                            Text(f.emoji).font(.system(size: 24))
                            Text(f.name)
                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color(hex: f.accentHex))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(
                            Capsule().fill(Color.white)
                        )
                    }
                    if !entry.festivals.isEmpty, let f2 = entry.festivals.dropFirst().first {
                        Text("\(f2.emoji) \(f2.name)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.white)
                    }
                    if entry.festivals.isEmpty {
                        Label(
                            (entry.huangli?.isAuspicious ?? false) ? "黄道吉日" : "平日",
                            systemImage: (entry.huangli?.isAuspicious ?? false) ? "star.fill" : "moon.stars.fill"
                        )
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.18)))
                    }
                    HStack(spacing: 8) {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(entry.huangli?.displayChongSha ?? "")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.8))
                            Text(entry.huangli?.wuXing ?? "")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.7))
                        }
                    }
                }
                .padding(.trailing, 14)
            }
            .padding(.vertical, 14)
        }
    }
}

// MARK: - ③ 今日待办进度 Widget 视图

/// ③ 今日待办进度：环形进度 + 完成/总数 + 最近 3 条（Medium 显示列表）
public struct TodoProgressWidgetView: View {
    public let entry: LunisolarWidgetEntry
    @Environment(\.widgetFamily) private var family

    public init(entry: LunisolarWidgetEntry) { self.entry = entry }

    private var accent: Color {
        entry.hasFestival ? Color(hex: entry.primaryFestivalHex) : Color.systemGreen
    }

    public var body: some View {
        switch family {
        case .systemSmall: smallView
        case .systemMedium: mediumView
        default: mediumView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("今日待办")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.primary)
                Spacer()
                ForEach(Array(entry.festivals.prefix(1).enumerated()), id: \.offset) { _, f in
                    Text(f.emoji)
                        .font(.caption)
                }
            }

            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                Circle()
                    .trim(from: 0, to: CGFloat(entry.progress))
                    .stroke(
                        LinearGradient(colors: [accent, accent.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(Int(entry.progress * 100))%")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(accent)
                    Text("\(entry.completedCount)/\(entry.todaysEventsCount)")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                }
            }
            .padding(.horizontal, 4)

            Text(progressHintText)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .widgetBackground {
            RoundedRectangle(cornerRadius: 0).fill(Color.systemBackground)
        }
    }

    private var mediumView: some View {
        HStack(alignment: .top, spacing: 12) {
            // 左：进度环
            VStack(spacing: 6) {
                Text("今日待办")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.15), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    Circle()
                        .trim(from: 0, to: CGFloat(entry.progress))
                        .stroke(
                            LinearGradient(colors: [accent, accent.opacity(0.6)], startPoint: .top, endPoint: .bottom),
                            style: StrokeStyle(lineWidth: 9, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: -2) {
                        Text("\(Int(entry.progress * 100))%")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(accent)
                        Text("\(entry.completedCount)/\(entry.todaysEventsCount)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.secondary)
                    }
                }
                .frame(width: 92, height: 92)

                Text(progressHintText)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .frame(width: 110)

            Divider().padding(.vertical, 4)

            // 右：3 条真实待办（优先级排序）→ 没写快照时给占位引导
            VStack(alignment: .leading, spacing: 6) {
                let rows = displayTodoRows(pick: 3)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    todoRow(title: row.title, done: row.done, priorityHex: row.priorityHex)
                }
                if !entry.festivals.isEmpty {
                    HStack(spacing: 4) {
                        if let f = entry.festivals.first {
                            HStack(spacing: 4) {
                                Text(f.emoji)
                                Text(f.name)
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(
                                Capsule().fill(Color(hex: f.accentHex))
                            )
                        }
                        Spacer()
                        Label(entry.huangli?.displayChongSha ?? "", systemImage: "exclamationmark.shield")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .widgetBackground {
            RoundedRectangle(cornerRadius: 0).fill(Color.systemBackground)
        }
    }

    // MARK: 辅助

    private struct DisplayRow { let title: String; let done: Bool; let priorityHex: String }

    /// 取主 App 写的前 `pick` 条，不够就用占位/黄历提示补齐
    private func displayTodoRows(pick: Int) -> [DisplayRow] {
        var rows: [DisplayRow] = entry.topTitles.prefix(pick).map {
            DisplayRow(title: $0.title, done: $0.isCompleted, priorityHex: $0.priorityHex)
        }
        if rows.count < pick {
            let fallbacks: [DisplayRow] = [
                DisplayRow(title: "打开 Lunisolar 查看日程", done: true,  priorityHex: "#6B7280"),
                DisplayRow(title: "长按小组件可切换尺寸样式", done: false, priorityHex: "#2563EB"),
                DisplayRow(title: "今日宜 \(entry.huangli?.yi.first ?? "祭祀")", done: false, priorityHex: "#D97706")
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

    private func todoRow(title: String, done: Bool, idx: Int) -> some View {
        let fallbackHexes = ["#6B7280", "#2563EB", "#D97706"]
        let hex = fallbackHexes[idx % fallbackHexes.count]
        return todoRow(title: title, done: done, priorityHex: hex)
    }

    private func todoRow(title: String, done: Bool, priorityHex hex: String) -> some View {
        HStack(spacing: 7) {
            // 优先级色点 + 复选框（色点作为复选框的描边色点缀）
            ZStack {
                Circle()
                    .stroke(Color(hex: hex), lineWidth: 1.2)
                    .frame(width: 14, height: 14)
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? Color(hex: hex) : Color.secondary.opacity(0.55))
                    .font(.system(size: 13, weight: .heavy))
            }
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(done ? Color.secondary : Color.primary)
                .strikethrough(done, pattern: .solid, color: Color.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - widgetBackground 兼容辅助

private extension View {
    /// iOS 17+ 有 containerBackground；之前版本用 background 兜底
    @ViewBuilder
    func widgetBackground<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            self.containerBackground(for: .widget) { content() }
        } else {
            self.background(content())
        }
    }
    func widgetBackground() -> some View {
        self.widgetBackground { Color.clear }
    }
}
#endif
