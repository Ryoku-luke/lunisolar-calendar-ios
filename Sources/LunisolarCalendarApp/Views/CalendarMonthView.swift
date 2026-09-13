#if canImport(SwiftUI)
import SwiftUI
import LunarCore

fileprivate final class _Box<T>: @unchecked Sendable { var value: T; init(_ v: T) { self.value = v } }
fileprivate struct DaySlot: Identifiable, Hashable {
    let date: Date
    let inCurrentMonth: Bool
    /// 以日期作为稳定标识：横滑手势期间 dragOffsetX 每帧触发 body 重算，
    /// 若用 UUID() 会导致 42 个格子每帧被 ForEach 判定为全新元素而重建掉帧。
    /// 月历网格内日期天然唯一，可直接作 id。
    var id: Date { date }
}

/// 月历单格的全部派生显示数据（农历/黄历/节日色/法定假日/事件统计）。
/// 这些数据只依赖「日期 + EventStore.revision」，与拖拽偏移/选中态无关，
/// 按月份整体预计算一次后跨帧复用。
fileprivate struct GridCellModel: Identifiable {
    let date: Date
    let inCurrentMonth: Bool
    let lunar: LunarDate
    let huangli: HuangliDay
    let festivalTint: Color?
    let holidayType: HolidayType
    let eventCount: Int
    let eventPriority: Priority?
    var id: Date { date }
}

fileprivate struct MonthGridModel {
    let monthKey: Date
    let revision: Int
    let cells: [GridCellModel]
}

struct CalendarMonthView: View {
    @State private var currentMonth: Date = Date().firstDayOfMonth
    @Binding private var selectedDate: Date
    @State private var isPanelExpanded: Bool = false
    @State private var showDateJump = false
    #if canImport(UIKit)
    @GestureState private var dragOffsetX: CGFloat = 0
    @State private var isDragging: Bool = false
    private let swipeThreshold: CGFloat = 28
    #endif
    /// 月网格派生数据缓存：仅当月份或事件版本变化时重建。
    /// 横滑期间 dragOffsetX 每帧令 body 重算，但命中此缓存后 42 格的
    /// 农历转换/黄历生成/节日遍历/事件统计全部 O(1) 复用，不再每帧重算。
    @State private var gridCache: MonthGridModel?
    @Environment(EventStore.self) private var store
    @Environment(\.horizontalSizeClass) private var hSizeClass

    /// 是否由本视图自行包一层 NavigationStack。
    /// - iPhone 根页：true（自身即导航根）
    /// - iPad 双栏侧栏：false（由 NavigationSplitView 的列提供导航上下文，避免侧栏内嵌栈）
    private let embedsInNavigationStack: Bool
    // iPad 侧栏内「倒数日 / 设置」改用 sheet 弹出（push 会挤在窄列里）
    @State private var showCountdown = false
    @State private var showSettings = false

    init(selectedDate: Binding<Date>? = nil, embedsInNavigationStack: Bool = true) {
        self.embedsInNavigationStack = embedsInNavigationStack
        if let binding = selectedDate {
            self._selectedDate = binding
        } else {
            let localBox = _Box(Date())
            self._selectedDate = Binding(get: { localBox.value }, set: { localBox.value = $0 })
        }
    }

    private var isIPadSplit: Bool { hSizeClass == .regular }

    var body: some View {
        if embedsInNavigationStack {
            NavigationStack { calendarContent }
        } else {
            calendarContent
        }
    }

    /// 日历主体。导航标题/工具条/sheet 挂在此处；外层是否再包 NavigationStack 由
    /// `embedsInNavigationStack` 决定（iPhone 根页自包，iPad 双栏侧栏复用 SplitView 列）。
    private var calendarContent: some View {
        // accentColorForToday 内部要做农历转换 + 节日遍历 + 颜色解析，
        // 背景/FAB/tint/节气条/工具条/网格选中格都要用，每次 body 只算一次后透传，
        // 避免横滑每帧重复 6~8 次。
        let accent = accentColorForToday
        return ZStack {
            // 节日自适应柔和渐变背景（春节自动偏红、中秋偏金、平日系统灰）
            festiveBackground(accent: accent)
                .ignoresSafeArea()

            // iPhone：当日卡片内容可能超过一屏，允许纵向滚动；
            // iPad 侧栏只有标题+网格，固定不滚动。
            if isIPadSplit {
                monthColumn(accent: accent)
            } else {
                ScrollView(showsIndicators: false) {
                    monthColumn(accent: accent)
                }
            }

            if !isIPadSplit {
                VStack { Spacer(); HStack {
                    Spacer()
                    NavigationLink {
                        EventEditView(editing: nil, defaultDate: selectedDate).environment(store)
                    } label: {
                        // 液态玻璃 FAB：节日色自动切换，克制装饰（去除顶部高光 overlay 叠加层）
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 60, height: 60)
                            .background(
                                Circle().fill(LinearGradient(
                                    colors: [accent, accent.opacity(0.80)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ))
                            )
                            .overlay(Circle().stroke(Color.white.opacity(0.22), lineWidth: AppTheme.Stroke.hair))
                            .shadow(color: accent.opacity(0.30), radius: 18, x: 0, y: 8)
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
                        currentMonth = Date().firstDayOfMonth; selectedDate = Date()
                    }
                } label: {
                    Label("今天", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .touchTarget(min: AppTheme.Touch.minTarget)
                }
                    .tint(accent)
                    .pressableFeedback()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { withAnimation(AppTheme.Motion.screen) {
                        currentMonth = Date().firstDayOfMonth; selectedDate = Date()
                    } } label: { Label("回到今天", systemImage: "location.circle") }
                    Button { showDateJump = true } label: { Label("跳转到日期", systemImage: "calendar.badge.clock") }
                    Divider()
                    if isIPadSplit {
                        // iPad 侧栏内 push 会被挤在窄列，改为 sheet 弹出
                        Button { showCountdown = true } label: { Label("倒数日", systemImage: "hourglass") }
                        Button { showSettings = true } label: { Label("设置", systemImage: "gearshape") }
                    } else {
                        NavigationLink { CountdownView() } label: { Label("倒数日", systemImage: "hourglass") }
                        NavigationLink { SettingsView().environment(store) }
                            label: { Label("设置", systemImage: "gearshape") }
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.title3).foregroundStyle(Color.secondaryLabel)
                        .symbolRenderingMode(.hierarchical)
                        .touchTarget(min: AppTheme.Touch.minTarget)
                }
                .pressableFeedback()
            }
        }
        #endif
        .tint(accent)
        .sheet(isPresented: $showDateJump) {
            DateJumpView(targetDate: Binding(
                get: { selectedDate },
                set: { newDate in
                    selectedDate = newDate
                    currentMonth = newDate.firstDayOfMonth
                }
            ))
        }
        .sheet(isPresented: $showCountdown) {
            // CountdownView 的列表自身不包导航栈，sheet 中补一层
            NavigationStack { CountdownView() }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environment(store)
        }
    }

    /// 月历纵向列：月份标题 + 节气条 + 网格（iPhone 下方还有当日卡片）。
    private func monthColumn(accent: Color) -> some View {
        VStack(spacing: 0) {
            monthHeader()
                .padding(.horizontal, AppTheme.Spacing.xl)
                .padding(.top, 12).padding(.bottom, AppTheme.Spacing.sm)
            solarTermBar(accent: accent)
                .padding(.horizontal, AppTheme.Spacing.xl)
                .padding(.bottom, AppTheme.Spacing.xs)
            calendarShell(accent: accent)
                .padding(.horizontal, AppTheme.Spacing.md)
                #if canImport(UIKit)
                // 拖拽视差 + 轻微缩放，增强手势感（仅在判定为水平拖拽时）
                .offset(x: dragOffsetX * 0.25)
                .scaleEffect(isDragging ? 0.992 : 1.0)
                .animation(isDragging ? AppTheme.Motion.pressInOut
                                      : AppTheme.Motion.screen, value: isDragging)
                // simultaneousGesture 只观察、不拦截：
                // 日期格子的点按与 ScrollView 的纵向滚动始终优先可用。
                .simultaneousGesture(swipeMonthGesture)
                #endif
            if !isIPadSplit {
                selectedDayCard
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.top, AppTheme.Spacing.md)
                    .padding(.bottom, AppTheme.Spacing.xxl)
            }
        }
        .frame(maxWidth: .infinity)
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
    private func festiveBackground(accent: Color) -> some View {
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

    private func monthHeader() -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.md) {
            Text("\(currentMonth.month)月")
                .font(AppTheme.Font.hero).foregroundStyle(Color.label)
            Text("\(currentMonth.year)")
                .font(AppTheme.Font.title3).foregroundStyle(Color.tertiaryLabel)
            Spacer()
            HStack(spacing: AppTheme.Spacing.sm) {
                Button {
                    withAnimation(AppTheme.Motion.screen) {
                        currentMonth = currentMonth.addingMonths(-1)
                    }
                } label: { chevronButton("chevron.left") }
                    .pressableFeedback()
                Button {
                    withAnimation(AppTheme.Motion.screen) {
                        currentMonth = currentMonth.addingMonths(1)
                    }
                } label: { chevronButton("chevron.right") }
                    .pressableFeedback()
            }
        }
    }

    /// 节气倒计时条：显示下一个节气及剩余天数
    @ViewBuilder
    private func solarTermBar(accent: Color) -> some View {
        if let next = SolarTermProvider.nextTerm(from: Date()) {
            HStack(spacing: 6) {
                Image(systemName: "leaf")
                    .font(.caption)
                    .foregroundStyle(Color.secondaryLabel)
                Text("下一个节气")
                    .font(.caption)
                    .foregroundStyle(Color.tertiaryLabel)
                Text(next.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                if next.daysRemaining > 0 {
                    Text("还有 \(next.daysRemaining) 天")
                        .font(.caption)
                        .foregroundStyle(Color.secondaryLabel)
                } else if next.daysRemaining == 0 {
                    Text("今天")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.festiveRed)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.xs)
            .background(Capsule().fill(.ultraThinMaterial))
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
                let dx = value.translation.width
                let dy = value.translation.height
                // 只在「水平占主导」时响应；纵向滑动（页面滚动）与轻微点按一律放行，
                // 否则手指上下动时整个日历会横向抖动，还会抢占日期格的点按。
                guard abs(dx) > abs(dy) else { state = 0; return }
                if !isDragging { Task { @MainActor in isDragging = true } }
                state = dx
            }
            .onEnded { value in
                isDragging = false
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > swipeThreshold && abs(dx) > 1.5 * abs(dy) else { return }
                withAnimation(AppTheme.Motion.screen) {
                    currentMonth = dx < 0
                        ? currentMonth.addingMonths(1)
                        : currentMonth.addingMonths(-1)
                }
            }
    }
    #endif

    /// 返回当前月的网格派生数据；月份/事件版本未变时直接复用缓存。
    /// 注意：这里在 body 求值期间条件性回写 @State 是 SwiftUI 允许的模式
    /// （仅在 key 失配时写一次，写入后下一帧即命中，不构成更新循环）。
    private func gridModel() -> MonthGridModel {
        if let cached = gridCache,
           cached.monthKey == currentMonth,
           cached.revision == store.revision {
            return cached
        }
        let slots = daysForMonth()
        var cells: [GridCellModel] = []
        cells.reserveCapacity(slots.count)
        for slot in slots {
            let d = slot.date
            // 农历转换 → 节日查询（复用预计算 lunar）→ 颜色解析，每月只做一次
            let lunar = d.lunar
            let festivalTint = FestivalManager.festivals(on: d, lunar: lunar).first
                .map { Color(hex: $0.accentHex) }
            let stats = store.eventStats(on: d)
            cells.append(GridCellModel(
                date: d,
                inCurrentMonth: slot.inCurrentMonth,
                lunar: lunar,
                huangli: HuangliGenerator.generate(for: d),
                festivalTint: festivalTint,
                holidayType: HolidayProvider.info(for: d).type,
                eventCount: stats.count,
                eventPriority: stats.priority
            ))
        }
        let model = MonthGridModel(monthKey: currentMonth, revision: store.revision, cells: cells)
        gridCache = model
        return model
    }

    private func calendarShell(accent: Color) -> some View {
        let grid = gridModel()
        let columns = [GridItem](repeating: GridItem(.flexible(), spacing: 0), count: 7)
        return VStack(alignment: .leading, spacing: 0) {
            WeekHeaderView()
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(grid.cells) { cell in
                    let d = cell.date
                    DayCellView(date: d, isCurrentMonth: cell.inCurrentMonth,
                                isSelected: d.isSameDay(as: selectedDate),
                                isToday: d.isToday,
                                lunar: cell.lunar,
                                huangli: cell.huangli,
                                hasEvents: cell.eventCount > 0,
                                eventPriority: cell.eventPriority,
                                eventCount: cell.eventCount,
                                festivalTint: cell.festivalTint,
                                cellAccent: cell.festivalTint
                                    ?? (d.isSameDay(as: selectedDate) ? accent : nil),
                                holidayType: cell.holidayType)
                        .equatable()
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
        // 月份横滑手势统一在 monthColumn 以 simultaneousGesture 挂载（避免拦截日期点按与纵向滚动）
    }

    private func daysForMonth() -> [DaySlot] {
        let first = currentMonth.firstDayOfMonth
        let leading = first.weekday - 1
        let totalDays = currentMonth.daysInMonth
        var result: [DaySlot] = []
        for i in 0..<leading {
            result.append(DaySlot(date: first.addingDays(-(leading - i)), inCurrentMonth: false))
        }
        for i in 0..<totalDays {
            result.append(DaySlot(date: first.addingDays(i), inCurrentMonth: true))
        }
        var i = 0
        while result.count < 42 {
            result.append(DaySlot(date: first.addingDays(totalDays + i), inCurrentMonth: false))
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
                        .foregroundStyle(foregroundForDayNumber())
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
                .softChipBackground(material: .thinMaterial)
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
                    .softChipBackground(material: .ultraThinMaterial)
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
                    DayDetailView(date: selectedDate, embedsInNavigationStack: false).environment(store)
                } label: {
                    Label("查看黄历详情", systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(SecondaryActionButtonStyle(accent: accent))

                NavigationLink {
                    EventEditView(editing: nil, defaultDate: selectedDate).environment(store)
                } label: {
                    Label("新建日程", systemImage: "plus.circle.fill")
                }
                .buttonStyle(PrimaryActionButtonStyle(accent: accent))
            }
        }
        .padding(AppTheme.Spacing.xl)
        .liquidCard(radius: 28, material: .regularMaterial,
                     tint: accent, shadow: AppTheme.Shadow.raised, highlight: 0.14)
    }

    private func foregroundForDayNumber() -> Color {
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
