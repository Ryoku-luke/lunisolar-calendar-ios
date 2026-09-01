#if canImport(SwiftUI)
import SwiftUI
import LunarCore

fileprivate final class _Box<T>: @unchecked Sendable { var value: T; init(_ v: T) { self.value = v } }
fileprivate struct DaySlot: Identifiable, Hashable {
    let id = UUID(); let date: Date; let inCurrentMonth: Bool
}

struct CalendarMonthView: View {
    @State private var currentMonth: Date = Date().gregorianFirstDayOfMonth
    @Binding private var selectedDate: Date
    @State private var isPanelExpanded: Bool = false
    #if canImport(UIKit)
    @State private var dragOffsetX: CGFloat = 0
    @State private var isDragging: Bool = false
    private let swipeThreshold: CGFloat = 28
    #endif
    @Environment(EventStore.self) private var store
    @Environment(\.horizontalSizeClass) private var hSizeClass

    init(selectedDate: Binding<Date>? = nil) {
        if let binding = selectedDate {
            self._selectedDate = binding
        } else {
            let localBox = _Box(Date())
            self._selectedDate = Binding(get: { localBox.value }, set: { localBox.value = $0 })
        }
    }

    private var isIPadSplit: Bool { hSizeClass == .regular }

    var body: some View {
        NavigationStack {
            ZStack {
                // 节日自适应柔和渐变背景（春节自动偏红、中秋偏金、平日系统灰）
                festiveBackground
                    .ignoresSafeArea()
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        monthHeader(containerWidth: geo.size.width)
                            .padding(.horizontal, AppTheme.Spacing.xl)
                            .padding(.top, 12).padding(.bottom, AppTheme.Spacing.sm)
                        calendarShell(containerWidth: geo.size.width)
                            .padding(.horizontal, AppTheme.Spacing.md)
                            #if canImport(UIKit)
                            // 拖拽视差 + 轻微缩放，增强手势感
                            .offset(x: dragOffsetX * 0.25)
                            .scaleEffect(isDragging ? 0.992 : 1.0)
                            .animation(isDragging ? AppTheme.Motion.pressInOut
                                                  : AppTheme.Motion.screen, value: isDragging)
                            #endif
                        if !isIPadSplit {
                            selectedDayCard
                                .padding(.horizontal, AppTheme.Spacing.md)
                                .padding(.top, AppTheme.Spacing.md)
                                .padding(.bottom, AppTheme.Spacing.xxl)
                        }
                    }.frame(maxWidth: .infinity)
                }
                if !isIPadSplit {
                    VStack { Spacer(); HStack {
                        Spacer()
                        NavigationLink {
                            EventEditView(editing: nil, defaultDate: selectedDate).environment(store)
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.white)
                                .frame(width: 60, height: 60)
                                .background {
                                    ZStack {
                                        // iOS 26 液态玻璃浮动按钮：节日色自动切换
                                        Circle()
                                            .fill(LinearGradient(
                                                colors: [accentColorForToday, accentColorForToday.opacity(0.80)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing
                                            ))
                                        Circle()
                                            .stroke(Color.white.opacity(0.24), lineWidth: AppTheme.Stroke.hair)
                                    }
                                }
                                .shadow(color: accentColorForToday.opacity(0.32),
                                        radius: 20, x: 0, y: 10)
                                .overlay(alignment: .top) {
                                    // 顶部高光
                                    Circle()
                                        .fill(LinearGradient(colors: [Color.white.opacity(0.30), .clear],
                                                             startPoint: .top, endPoint: .bottom))
                                        .frame(height: 28).allowsHitTesting(false)
                                        .offset(y: 2).clipShape(Circle())
                                }
                        }
                        .buttonStyle(.plain)
                        .pressableFeedback()
                        .padding(.trailing, AppTheme.Spacing.xl)
                        .padding(.bottom, AppTheme.Spacing.xl)
                    }}
                }
            }
            .navigationTitle("日历")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.navBar, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(AppTheme.Motion.screen) {
                            currentMonth = Date().gregorianFirstDayOfMonth; selectedDate = Date()
                        }
                    } label: {
                        Label("今天", systemImage: "sparkles")
                            .font(.subheadline.weight(.semibold))
                            .touchTarget(min: AppTheme.Touch.minTarget)
                    }
                        .tint(accentColorForToday)
                        .pressableFeedback()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { withAnimation(AppTheme.Motion.screen) {
                            currentMonth = Date().gregorianFirstDayOfMonth; selectedDate = Date()
                        } } label: { Label("回到今天", systemImage: "location.circle") }
                        Divider()
                        NavigationLink { SettingsView().environment(store) }
                            label: { Label("设置", systemImage: "gearshape") }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.title3).foregroundStyle(Color.secondaryLabel)
                            .touchTarget(min: AppTheme.Touch.minTarget)
                    }
                    .pressableFeedback()
                }
            }
            #endif
            .tint(accentColorForToday)
        }
    }

    // MARK: - 节日自适应背景与强调色

    /// 根据「选中日期的节日」决定今日强调色；无节日回落为系统 appTint
    private var accentColorForToday: Color {
        let selLunar = selectedDate.lunar
        let fs = FestivalManager.festivals(on: selectedDate, lunar: selLunar)
        if let f = fs.first { return Color(hex: f.accentHex) }
        return Color.appTint
    }

    /// 全屏柔和渐变背景：节日强调色弱染色，平日保持 SystemGrouped
    @ViewBuilder
    private var festiveBackground: some View {
        let accent = accentColorForToday
        ZStack {
            Color.systemGroupedBackground
            LinearGradient(
                colors: [accent.opacity(0.08), accent.opacity(0.02), Color.clear],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            // 两个模糊的色斑，增强 iOS 26 壁纸感
            Circle()
                .fill(accent.opacity(0.06))
                .frame(width: 380, height: 380)
                .blur(radius: 80)
                .offset(x: -140, y: -160)
            Circle()
                .fill(accent.opacity(0.05))
                .frame(width: 320, height: 320)
                .blur(radius: 72)
                .offset(x: 120, y: 340)
        }
    }

    private func monthHeader(containerWidth: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.md) {
            Text("\(currentMonth.gregorianMonth)月")
                .font(AppTheme.Font.hero).foregroundStyle(Color.label)
            Text("\(currentMonth.gregorianYear)")
                .font(AppTheme.Font.title3).foregroundStyle(Color.tertiaryLabel)
            Spacer()
            HStack(spacing: AppTheme.Spacing.sm) {
                Button {
                    withAnimation(AppTheme.Motion.screen) {
                        currentMonth = currentMonth.gregorianAddingMonths(-1)
                    }
                } label: { chevronButton("chevron.left") }
                    .pressableFeedback()
                Button {
                    withAnimation(AppTheme.Motion.screen) {
                        currentMonth = currentMonth.gregorianAddingMonths(1)
                    }
                } label: { chevronButton("chevron.right") }
                    .pressableFeedback()
            }
        }
    }

    private func chevronButton(_ name: String) -> some View {
        Image(systemName: name).font(.title2.weight(.semibold)).foregroundStyle(Color.secondaryLabel)
            .frame(width: AppTheme.Touch.minTarget, height: AppTheme.Touch.minTarget)
            .background(
                ZStack {
                    Circle().fill(.ultraThinMaterial)
                    Circle().stroke(Color.white.opacity(0.18), lineWidth: AppTheme.Stroke.hair)
                }
            )
            .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
            .contentShape(Circle())
    }

    #if canImport(UIKit)
    private var swipeMonthGesture: some Gesture {
        DragGesture(minimumDistance: swipeThreshold, coordinateSpace: .local)
            .updating($dragOffsetX) { value, state, _ in
                state = value.translation.width
                if !isDragging { Task { @MainActor in isDragging = true } }
            }
            .onEnded { value in
                isDragging = false
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > swipeThreshold && abs(dx) > 1.5 * abs(dy) else { return }
                withAnimation(AppTheme.Motion.screen) {
                    currentMonth = dx < 0
                        ? currentMonth.gregorianAddingMonths(1)
                        : currentMonth.gregorianAddingMonths(-1)
                }
            }
    }
    #endif

    private func calendarShell(containerWidth: CGFloat) -> some View {
        let slots = daysForMonth()
        var statsMap: [Date: (count: Int, prio: Priority?)] = [:]
        var huangliMap: [Date: HuangliDay] = [:]
        var lunarMap: [Date: LunarDate] = [:]
        for slot in slots {
            let d = slot.date
            let stats = store.eventStats(on: d)
            statsMap[d] = (stats.count, stats.priority)
            huangliMap[d] = HuangliGenerator.generate(for: d)
            lunarMap[d] = d.lunar
        }
        let columns = [GridItem](repeating: GridItem(.flexible(), spacing: 0), count: 7)
        return VStack(alignment: .leading, spacing: 0) {
            WeekHeaderView()
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(slots) { slot in
                    let d = slot.date
                    let st = statsMap[d] ?? (0, nil)
                    let lunarFor = lunarMap[d] ?? d.lunar
                    let festivals = FestivalManager.festivals(on: d, lunar: lunarFor)
                    DayCellView(date: d, isCurrentMonth: slot.inCurrentMonth,
                                isSelected: d.isSameDay(as: selectedDate),
                                isToday: d.isToday,
                                lunar: lunarFor,
                                huangli: huangliMap[d] ?? HuangliGenerator.generate(for: d),
                                hasEvents: st.count > 0, eventPriority: st.prio, eventCount: st.count,
                                festivalTint: festivals.first.map { Color(hex: $0.accentHex) },
                                cellAccent: (festivals.first.map { Color(hex: $0.accentHex) }
                                                ?? (d.isSameDay(as: selectedDate) ? accentColorForToday : nil)))
                    .frame(minHeight: AppTheme.Touch.minCellHeight)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(AppTheme.Motion.pressInOut) { selectedDate = d }
                    }
                }
            }
            .padding(.horizontal, isIPadSplit ? AppTheme.Spacing.lg : AppTheme.Spacing.md)
            .padding(.bottom, AppTheme.Spacing.lg)
        }
        .padding(.top, AppTheme.Spacing.xs)
        .liquidCard(radius: AppTheme.Radius.xxl, material: .regularMaterial,
                     shadow: AppTheme.Shadow.card)
        .contentShape(Rectangle())
        #if canImport(UIKit)
        .gesture(swipeMonthGesture)
        #endif
    }

    private func daysForMonth() -> [DaySlot] {
        let first = currentMonth.gregorianFirstDayOfMonth
        let leading = first.gregorianWeekday - 1
        let totalDays = currentMonth.gregorianDaysInMonth
        var result: [DaySlot] = []
        for i in 0..<leading {
            result.append(DaySlot(date: first.gregorianAddingDays(-(leading - i)), inCurrentMonth: false))
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

    private var selectedDayCard: some View {
        let huangli = HuangliGenerator.generate(for: selectedDate)
        let selLunar = selectedDate.lunar
        let todayFestivals = FestivalManager.festivals(on: selectedDate, lunar: selLunar)
        let accent: Color = todayFestivals.first.map { Color(hex: $0.accentHex) } ?? Color.appTint
        let todaysEvents = store.events(on: selectedDate)

        return VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.lg) {
                VStack(spacing: 2) {
                    Text("\(selectedDate.day)")
                        .font(AppTheme.Font.numeralXL)
                        .foregroundStyle(foregroundForDayNumber(accent: accent))
                    Text(selectedDate.weekdaySymbol)
                        .font(AppTheme.Font.caption).foregroundStyle(Color.secondaryLabel)
                }
                .frame(width: 92).padding(.vertical, AppTheme.Spacing.md)
                .background {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                        .fill(selectedDate.isToday ? Color.todayCapsule : Color.themeQuaternaryFill)
                    RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                        .stroke(accent.opacity(0.16), lineWidth: AppTheme.Stroke.hair)
                }

                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Text(selLunar.displayString).font(AppTheme.Font.title3).foregroundStyle(Color.label)
                    if !todayFestivals.isEmpty {
                        HStack(spacing: AppTheme.Spacing.xs) {
                            ForEach(Array(todayFestivals.prefix(2)), id: \.name) { f in
                                Text("\(f.emoji) \(f.name)")
                                    .font(AppTheme.Font.caption).fontWeight(.bold)
                                    .capsuleTag(fill: Color(hex: f.accentHex).opacity(0.16),
                                                border: Color(hex: f.accentHex).opacity(0.25))
                                    .foregroundStyle(Color(hex: f.accentHex))
                            }
                        }
                    }
                    HStack(spacing: AppTheme.Spacing.xs) {
                        ChipLabel(title: "\(selLunar.yearGanZhi)", tint: Color.systemIndigo)
                        ChipLabel(title: selLunar.yearAnimal, systemImage: "pawprint.circle.fill", tint: Color.systemOrange)
                    }
                }
                Spacer(minLength: 0)
            }

            if !huangli.yi.isEmpty || !huangli.ji.isEmpty {
                HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                    yiBlock(huangli.yi, maxShown: 6)
                    Divider().frame(maxHeight: .infinity)
                    jiBlock(huangli.ji, maxShown: 6)
                }
                .padding(AppTheme.Spacing.md)
                .background {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                        .fill(.thinMaterial)
                    RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                        .stroke(Color.separator.opacity(0.18), lineWidth: AppTheme.Stroke.hair)
                }
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack {
                    Text("今日安排").font(AppTheme.Font.bodyBold).foregroundStyle(Color.label)
                    Spacer()
                    if !todaysEvents.isEmpty {
                        Text("\(todaysEvents.count) 项").font(AppTheme.Font.caption).foregroundStyle(Color.tertiaryLabel)
                    }
                }
                if todaysEvents.isEmpty {
                    // 空态插画：柔和色图标 + 渐变底框，引导点击
                    HStack(spacing: AppTheme.Spacing.md) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [accent.opacity(0.18), accent.opacity(0.06)],
                                                     startPoint: .top, endPoint: .bottom))
                                .frame(width: 48, height: 48)
                            Image(systemName: "sparkles")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(accent)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("这一天很空闲").font(AppTheme.Font.bodyBold).foregroundStyle(Color.label)
                            Text("去安排点美好的事吧 ✨").font(AppTheme.Font.caption).foregroundStyle(Color.tertiaryLabel)
                        }
                        Spacer()
                    }
                    .padding(AppTheme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                        .fill(.ultraThinMaterial))
                    .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                        .stroke(Color.separator.opacity(0.18), lineWidth: AppTheme.Stroke.hair))
                } else {
                    let slice = isPanelExpanded ? todaysEvents : Array(todaysEvents.prefix(3))
                    VStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(slice) { ev in
                            NavigationLink {
                                EventEditView(editing: ev, defaultDate: selectedDate).environment(store)
                            } label: {
                                EventRow(event: ev, compact: !isPanelExpanded).environment(store)
                            }.buttonStyle(.plain)
                                .pressableFeedback()
                        }
                    }
                    if todaysEvents.count > 3 {
                        Button {
                            withAnimation(AppTheme.Motion.screen) {
                                isPanelExpanded.toggle()
                            }
                        } label: {
                            HStack {
                                Spacer()
                                Text(isPanelExpanded ? "收起" : "查看全部 \(todaysEvents.count) 项 →")
                                    .font(AppTheme.Font.caption.weight(.bold)).foregroundStyle(accent)
                                Spacer()
                            }
                            .frame(minHeight: AppTheme.Touch.chipHeight)
                            .background(Capsule().fill(accent.opacity(0.10)))
                            .contentShape(Capsule())
                        }.buttonStyle(.plain)
                            .pressableFeedback()
                    }
                }
            }

            HStack(spacing: AppTheme.Spacing.sm) {
                NavigationLink {
                    DayDetailView(date: selectedDate).environment(store)
                } label: {
                    Label("查看黄历详情", systemImage: "doc.text.magnifyingglass")
                        .font(AppTheme.Font.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: AppTheme.Touch.minTarget)
                        .background {
                            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                                .fill(.thinMaterial)
                            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                                .stroke(Color.separator.opacity(0.20), lineWidth: AppTheme.Stroke.hair)
                        }
                        .foregroundStyle(Color.label)
                        .contentShape(Rectangle())
                }
                .pressableFeedback()

                NavigationLink {
                    EventEditView(editing: nil, defaultDate: selectedDate).environment(store)
                } label: {
                    Label("新建日程", systemImage: "plus.circle.fill")
                        .font(AppTheme.Font.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: AppTheme.Touch.minTarget)
                        .background {
                            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                                .fill(LinearGradient(colors: [accent, accent.opacity(0.82)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                                .stroke(Color.white.opacity(0.24), lineWidth: AppTheme.Stroke.hair)
                        }
                        .overlay(alignment: .top) {
                            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                                .fill(LinearGradient(colors: [Color.white.opacity(0.22), .clear],
                                                     startPoint: .top, endPoint: .bottom))
                                .frame(height: 22).allowsHitTesting(false)
                                .offset(y: 2)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
                        }
                        .foregroundStyle(.white)
                        .shadow(color: accent.opacity(0.28), radius: 10, x: 0, y: 4)
                        .contentShape(Rectangle())
                }
                .pressableFeedback()
            }.buttonStyle(.plain)
        }
        .padding(AppTheme.Spacing.xl)
        .liquidCard(radius: 28, material: .regularMaterial,
                     tint: accent, shadow: AppTheme.Shadow.raised, highlight: 0.14)
    }

    private func foregroundForDayNumber(accent: Color) -> Color {
        if selectedDate.isToday { return Color.systemRed }
        if !Calendar(identifier: .gregorian).isDate(selectedDate, equalTo: Date(), toGranularity: .month) {
            return Color.tertiaryLabel
        }
        return Color.label
    }

    private func yiBlock(_ yi: [String], maxShown: Int) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: 4) {
                Text("宜").font(AppTheme.Font.caption2.weight(.bold))
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.systemGreen)).foregroundStyle(.white)
                Text("宜做").font(AppTheme.Font.caption.weight(.semibold)).foregroundStyle(Color.secondaryLabel)
            }
            TagCloudView(tags: Array(yi.prefix(maxShown)), tint: Color.systemGreen)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func jiBlock(_ ji: [String], maxShown: Int) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: 4) {
                Text("忌").font(AppTheme.Font.caption2.weight(.bold))
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.systemRed)).foregroundStyle(.white)
                Text("勿做").font(AppTheme.Font.caption.weight(.semibold)).foregroundStyle(Color.secondaryLabel)
            }
            TagCloudView(tags: Array(ji.prefix(maxShown)), tint: Color.systemRed)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TagCloudView: View {
    let tags: [String]
    var tint: Color = .appTint
    var font: Font = AppTheme.Font.caption2
    var body: some View {
        FlowLayout(spacing: 4, lineSpacing: 4) {
            ForEach(tags, id: \.self) { tag in
                Text(tag).font(font).fontWeight(.medium)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(tint.opacity(0.12)))
                    .foregroundStyle(tint)
            }
            if tags.isEmpty {
                Text("—").font(font).foregroundStyle(Color.quaternaryLabel)
            }
        }
    }
}

#Preview { CalendarMonthView().environment(EventStore.shared) }
#Preview("iPad Split") { iPadRootView().environment(EventStore.shared) }

#endif
