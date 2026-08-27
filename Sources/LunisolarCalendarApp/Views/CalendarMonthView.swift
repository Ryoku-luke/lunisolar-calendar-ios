#if canImport(SwiftUI)
import SwiftUI

// MARK: - 月视图日历主界面

fileprivate struct DaySlot: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let inCurrentMonth: Bool
}

struct CalendarMonthView: View {
    @State private var currentMonth: Date = Date().gregorianFirstDayOfMonth
    /// iPad 模式下从外部 Binding 注入；iPhone 模式下用本地 @State
    @Binding private var selectedDate: Date
    /// 底部面板展开状态（点击就地显示完整时间轴）
    @State private var isPanelExpanded: Bool = false

    @Environment(EventStore.self) private var store
    @Environment(\.horizontalSizeClass) private var hSizeClass

    /// iPhone 便捷初始化（内部自带 selectedDate State）
    init(selectedDate: Binding<Date>? = nil) {
        if let binding = selectedDate {
            self._selectedDate = binding
        } else {
            let local = State(initialValue: Date())
            self._selectedDate = local.projectedValue
        }
    }

    /// 是否在 iPad 双栏模式下运行（隐藏底部面板、FAB等，改为右侧详情）
    private var isIPadSplit: Bool { hSizeClass == .regular }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                monthHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 6)

                Divider().padding(.horizontal, 16)

                WeekHeaderView()
                    .padding(.top, 4)

                calendarGrid
                    .padding(.horizontal, 8)
                    .padding(.top, 2)

                // iPad 双栏模式隐藏底部面板（详情在右栏显示）
                if !isIPadSplit {
                    dayPreviewPanel
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 12)
                }
            }
            .background(Color.systemGroupedBackground.ignoresSafeArea())
            .overlay(alignment: .bottomTrailing) {
                // iPad 双栏模式不显示 FAB（右栏已有添加按钮）
                if !isIPadSplit {
                    NavigationLink {
                        EventEditView(
                            editing: nil,
                            defaultDate: selectedDate
                        )
                        .environment(store)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 50, weight: .light))
                            .foregroundStyle(Color.systemBlue)
                            .background(
                                Circle()
                                    .fill(Color.systemBackground)
                                    .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2)
                            )
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 24)
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    headerTitle
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentMonth = Date().gregorianFirstDayOfMonth
                            selectedDate = Date()
                        }
                    } label: {
                        Text("今天")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.systemBlue)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentMonth = Date().gregorianFirstDayOfMonth
                                selectedDate = Date()
                            }
                        } label: {
                            Label("回到今天", systemImage: "calendar.circle")
                        }
                        Divider()
                        NavigationLink {
                            SettingsView()
                                .environment(store)
                        } label: {
                            Label("设置", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    private var headerTitle: some View {
        Text("农历日历")
            .font(.headline)
            .foregroundStyle(Color.label)
    }

    private var monthHeader: some View {
        HStack {
            Text("\(currentMonth.gregorianYear) 年 \(currentMonth.gregorianMonth) 月")
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.label)
            Spacer()
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentMonth = currentMonth.gregorianAddingMonths(-1)
                    }
                } label: {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.secondaryLabel)
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentMonth = currentMonth.gregorianAddingMonths(1)
                    }
                } label: {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.secondaryLabel)
                }
            }
        }
    }

    // MARK: - 日历网格

    private var calendarGrid: some View {
        let columns = [GridItem](repeating: GridItem(.flexible(), spacing: 2), count: 7)
        // 预计算本月所有 slot 的数据，避免 LazyVGrid 每帧对每个 cell 重算
        let slots = daysForMonth()
        // P9 修复：一次性预计算 event 统计 + 黄历 + 农历，42 slot 只做 42 次重算；
        //         原实现把 HuangliGenerator.generate 放进 ForEach body，cell 每一帧 layout 都会重算（ProMotion 120Hz 下可能掉帧）。
        var eventMap: [Date: (has: Bool, prio: Priority?)] = [:]
        var huangliMap: [Date: HuangliDay] = [:]
        var lunarMap: [Date: LunarDate] = [:]
        for slot in slots {
            let d = slot.date
            let stats = store.eventStats(on: d)
            eventMap[d] = (stats.has, stats.priority)
            huangliMap[d] = HuangliGenerator.generate(for: d)
            lunarMap[d] = d.lunar
        }

        return LazyVGrid(columns: columns, spacing: 2) {
            ForEach(slots) { slot in
                let date = slot.date
                let lunar = lunarMap[date] ?? date.lunar
                let huangli = huangliMap[date] ?? HuangliGenerator.generate(for: date)
                let (hasEvs, prio) = eventMap[date] ?? (false, nil)

                DayCellView(
                    date: date,
                    isCurrentMonth: slot.inCurrentMonth,
                    isSelected: date.isSameDay(as: selectedDate),
                    isToday: date.isToday,
                    lunar: lunar,
                    huangli: huangli,
                    hasEvents: hasEvs,
                    eventPriority: prio
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedDate = date
                }
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondarySystemBackground)
        )
        .padding(.horizontal, 8)
    }

    private func daysForMonth() -> [DaySlot] {
        // BUG #33 修复：月历网格结构统一按公历计算，不受用户系统日历（伊斯兰历/佛历/和历）影响。
        let first = currentMonth.gregorianFirstDayOfMonth
        // gregorianWeekday: 1=周日 ... 7=周六 -> 将周日列在首位，前置数量 = (weekday-1)
        let leading = first.gregorianWeekday - 1
        let totalDays = currentMonth.gregorianDaysInMonth
        var result: [DaySlot] = []

        for i in 0..<leading {
            let d = first.gregorianAddingDays(-(leading - i))
            result.append(DaySlot(date: d, inCurrentMonth: false))
        }
        for i in 0..<totalDays {
            result.append(DaySlot(date: first.gregorianAddingDays(i), inCurrentMonth: true))
        }
        var i = 0
        while result.count < 42 {
            result.append(DaySlot(date: first.gregorianAddingDays(totalDays + i), inCurrentMonth: false))
            i += 1
        }
        return result
    }

    // MARK: - 底部预览面板

    private var dayPreviewPanel: some View {
        let huangli = HuangliGenerator.generate(for: selectedDate)
        let todaysEvents = store.events(on: selectedDate)
        let todayFestivals = FestivalManager.festivals(on: selectedDate)
        let primaryFest = FestivalManager.primaryFestival(on: selectedDate)
        let accentHex = primaryFest?.accentHex ?? "#C41A1A"
        let hasFestival = !todayFestivals.isEmpty

        let cardBg: Color = hasFestival && primaryFest != nil
            ? Color(hex: accentHex).opacity(0.08)
            : Color.secondarySystemBackground

        return VStack(alignment: .leading, spacing: 10) {
            // 节日主题 Banner
            if !todayFestivals.isEmpty {
                festivalBanner(festivals: todayFestivals, accentHex: accentHex)
            }

            // 可点击的标题行：就地展开/收起完整时间轴
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    isPanelExpanded.toggle()
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 2) {
                        Text("\(selectedDate.day)")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(
                                selectedDate.isToday
                                    ? (hasFestival ? Color(hex: accentHex) : Color.systemRed)
                                    : Color.label
                            )
                        Text(selectedDate.weekdaySymbol)
                            .font(.caption)
                            .foregroundStyle(Color.secondaryLabel)
                    }
                    .frame(width: 64)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                hasFestival
                                    ? Color(hex: accentHex).opacity(0.12)
                                    : Color.tertiarySystemBackground
                            )
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(huangli.lunar.displayString)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.label)
                            if huangli.isAuspicious {
                                Label("宜", systemImage: "star.fill")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(
                                        Capsule().fill(
                                            hasFestival ? Color(hex: accentHex) : Color.auspicious
                                        )
                                    )
                            }
                            // 节日徽标胶囊
                            ForEach(Array(todayFestivals.prefix(2).enumerated()), id: \.offset) { _, f in
                                Text("\(f.emoji)\(f.name)")
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 7).padding(.vertical, 2)
                                    .background(
                                        Capsule().fill(Color(hex: f.accentHex).opacity(0.15))
                                    )
                                    .foregroundStyle(Color(hex: f.accentHex))
                            }
                        }
                        HStack(spacing: 4) {
                            Text("冲煞")
                                .font(.caption)
                                .foregroundStyle(Color.secondaryLabel)
                            Text(huangli.displayChongSha)
                                .font(.caption)
                                .foregroundStyle(Color.label)
                            Text("·")
                                .font(.caption)
                                .foregroundStyle(Color.tertiaryLabel)
                            Text("五行")
                                .font(.caption)
                                .foregroundStyle(Color.secondaryLabel)
                            Text(huangli.wuXing)
                                .font(.caption)
                                .foregroundStyle(Color.label)
                        }
                    }
                    Spacer()
                    Image(systemName: isPanelExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.title3)
                        .foregroundStyle(
                            hasFestival ? Color(hex: accentHex) : Color.secondaryLabel
                        )
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 折叠态：前 2 条；展开态：完整时间轴 (超过 8 条给"查看全部"跳转)
            Group {
                if todaysEvents.isEmpty {
                    emptyEventsHint
                } else if isPanelExpanded {
                    VStack(spacing: 6) {
                        ForEach(todaysEvents) { ev in
                            NavigationLink {
                                EventEditView(editing: ev, defaultDate: selectedDate)
                                    .environment(store)
                            } label: {
                                EventRow(event: ev, compact: false)
                                    .environment(store)
                            }
                            .buttonStyle(.plain)
                        }
                        if todaysEvents.count > 8 {
                            NavigationLink {
                                DayDetailView(date: selectedDate)
                                    .environment(store)
                            } label: {
                                HStack {
                                    Spacer()
                                    Text("共\(todaysEvents.count)条，查看完整列表 →")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(
                                            hasFestival ? Color(hex: accentHex) : Color.systemBlue
                                        )
                                    Spacer()
                                }
                                .padding(.top, 4)
                            }
                        }
                    }
                } else {
                    VStack(spacing: 4) {
                        ForEach(todaysEvents.prefix(2)) { ev in
                            EventRow(event: ev, compact: true)
                                .environment(store)
                        }
                        if todaysEvents.count > 2 {
                            HStack(spacing: 3) {
                                Text("还有 \(todaysEvents.count - 2) 条")
                                    .font(.caption2)
                                    .foregroundStyle(Color.tertiaryLabel)
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(Color.tertiaryLabel)
                                Text("展开")
                                    .font(.caption2)
                                    .foregroundStyle(Color.tertiaryLabel)
                            }
                            .padding(.horizontal, 6)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                NavigationLink {
                    DayDetailView(date: selectedDate)
                        .environment(store)
                } label: {
                    HStack {
                        Spacer()
                        Label(
                            isPanelExpanded ? "查看黄历详情" : "查看详情",
                            systemImage: "doc.text.magnifyingglass"
                        )
                        .font(.footnote.weight(.semibold))
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                hasFestival
                                    ? Color(hex: accentHex).opacity(0.12)
                                    : Color.systemBlue.opacity(0.12)
                            )
                    )
                    .foregroundStyle(
                        hasFestival ? Color(hex: accentHex) : Color.systemBlue
                    )
                }

                NavigationLink {
                    EventEditView(editing: nil, defaultDate: selectedDate)
                        .environment(store)
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("新建日程")
                            .font(.footnote.weight(.semibold))
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                hasFestival
                                    ? LinearGradient(
                                        colors: [Color(hex: accentHex), Color(hex: accentHex).opacity(0.8)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    )
                                    : LinearGradient(
                                        colors: [Color.systemBlue, Color.systemBlue.opacity(0.85)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    )
                            )
                    )
                    .foregroundStyle(.white)
                    .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 2)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    hasFestival ? Color(hex: accentHex).opacity(0.25) : Color.clear,
                    lineWidth: 1
                )
        )
        .shadow(
            color: hasFestival
                ? Color(hex: accentHex).opacity(0.08)
                : Color.black.opacity(0.02),
            radius: hasFestival ? 8 : 0,
            x: 0, y: hasFestival ? 3 : 0
        )
    }

    // MARK: - 节日 Banner 组件

    private func festivalBanner(festivals: [Festival], accentHex: String) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(festivals.enumerated()), id: \.offset) { _, f in
                HStack(spacing: 6) {
                    Text(f.emoji)
                        .font(.system(size: 20))
                    Text(f.name)
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(
                    LinearGradient(
                        colors: [Color(hex: f.accentHex), Color(hex: f.accentHex).opacity(0.78)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .clipShape(Capsule())
                .shadow(color: Color(hex: f.accentHex).opacity(0.3), radius: 4, x: 0, y: 2)
            }
            Spacer(minLength: 0)
            if festivals.contains(where: { ["春节","元宵","端午","中秋","重阳","除夕"].contains($0.name) }) {
                Label("传统佳节", systemImage: "flame.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(
                        LinearGradient(
                            colors: [Color.festiveGold, Color.festiveGold.opacity(0.7)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - 空日程提示

    private var emptyEventsHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "moon.stars")
                .foregroundStyle(Color.tertiaryLabel)
            Text(
                isPanelExpanded
                    ? "这天还没有安排 ☕ 点击右下角 + 添加一条吧"
                    : "今日暂无日程，保持轻松心情 ☕️"
            )
                .font(.footnote)
                .foregroundStyle(Color.tertiaryLabel)
            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.tertiarySystemBackground.opacity(0.7))
        )
    }
}

#Preview {
    CalendarMonthView()
        .environment(EventStore.shared)
}

// MARK: - iPad 双栏预览

#Preview("iPad Split") {
    iPadRootView()
        .environment(EventStore.shared)
}

#endif
