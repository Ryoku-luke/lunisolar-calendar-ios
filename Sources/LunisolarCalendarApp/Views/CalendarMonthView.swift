#if canImport(SwiftUI)
import SwiftUI
import LunarCore
#if canImport(UIKit)
import UIKit
#endif

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
    /// 节假日名（如"中秋节"）：节日当天格内只显示节日名，不显示农历
    let festivalName: String?
    /// 节气名（如"秋分"）：节气日格内只显示节气名，不显示农历
    let solarTermName: String?
    /// 节气主题色（绿色系），用于格内"·秋分"小字
    let solarTermTint: Color?
    let holidayType: HolidayType
    let eventCount: Int
    /// 当日全部事件优先级（按事件顺序），格子事件点逐个着色
    let eventPriorities: [Priority]
    var id: Date { date }
}

fileprivate struct MonthGridModel {
    let monthKey: Date
    let revision: Int
    let cells: [GridCellModel]
    /// 缓存键：月份时间戳 + 事件版本（用于多月份网格缓存字典）
    var cacheKey: String { "\(monthKey.timeIntervalSince1970)-\(revision)" }
}

struct CalendarMonthView: View {
    @State private var currentMonth: Date = Date().firstDayOfMonth
    /// 本地选中日期（唯一真相，@State 保证点击后必然重绘）。
    /// 外部传入 binding 时（iPad 双栏）通过 onChange 双向同步，不在 init 里手动接线，
    /// 彻底规避"点击日期无反应"（此前 @Binding←局部引用/投影接线的运行时失效问题）。
    @State private var selectedDate: Date = Date()
    @State private var isPanelExpanded: Bool = false
    @State private var showDateJump = false
    /// 月份卡片滑动的进入方向：.trailing=下月从右侧滑入，.leading=上月从左侧滑入
    @State private var monthSlideEdge: Edge = .trailing
    #if canImport(UIKit)
    /// 跟手滑动偏移：手指移动多少卡片就移动多少（1:1），松手后回弹或翻页
    @State private var dragOffsetX: CGFloat = 0
    @State private var isDragging: Bool = false
    /// 拖动中预览的相邻月份（左滑=下月、右滑=上月），缓存预填充后零卡顿
    @State private var previewMonth: Date? = nil
    /// 日历容器宽度（翻页/回弹阈值判定用），由 background GeometryReader 注入
    @State private var monthWidth: CGFloat = 0
    /// 最小拖动距离：小于该距离视为点按（日期选中仍可用）
    private let swipeThreshold: CGFloat = 8
    #endif
    /// 月网格派生数据缓存：仅当月份或事件版本变化时重建。
    /// 横滑期间 dragOffsetX 每帧令 body 重算，但命中此缓存后 42 格的
    /// 农历转换/黄历生成/节日遍历/事件统计全部 O(1) 复用，不再每帧重算。
    /// 月网格派生数据缓存（多月份字典）：key = "月份-版本"。
    /// 滑动切换月份时相邻月份已预填充 → 动画期间零同步重算，消除卡顿。
    @State private var gridCache: [String: MonthGridModel] = [:]
    /// 每周起始日（Calendar weekday 语义：1=周日，2=周一；设置页可改）
    @AppStorage("Lunisolar.weekStart") private var weekStart: Int = 1
    @Environment(EventStore.self) private var store
    @Environment(\.horizontalSizeClass) private var hSizeClass

    /// 是否由本视图自行包一层 NavigationStack。
    /// - iPhone 根页：true（自身即导航根）
    /// - iPad 双栏侧栏：false（由 NavigationSplitView 的列提供导航上下文，避免侧栏内嵌栈）
    private let embedsInNavigationStack: Bool
    /// 可选外部绑定（iPad 双栏与 DayDetailView 联动）；本地 @State 为唯一真相，onChange 双向同步
    private var externalSelectedDate: Binding<Date>?
    // iPad 侧栏内「倒数日 / 设置」改用 sheet 弹出（push 会挤在窄列里）
    @State private var showCountdown = false
    @State private var showSettings = false

    init(selectedDate: Binding<Date>? = nil, embedsInNavigationStack: Bool = true) {
        self.embedsInNavigationStack = embedsInNavigationStack
        self.externalSelectedDate = selectedDate
        if let binding = selectedDate {
            // 外部绑定存在时以它的当前值作为初始选中（@State 显式初始化是官方支持模式）
            self._selectedDate = State(initialValue: binding.wrappedValue)
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
            // iPad 侧栏：同样包 ScrollView，防止内容超高被裁切（网格 7 列在窄栏自适应）
            ScrollView(showsIndicators: false) {
                monthColumn(accent: accent)
            }
        }
        .navigationTitle("日历")
        #if canImport(UIKit)
        // inline 模式：导航栏紧凑（减少头部大块空白）、标题必然渲染、
        // 无 large↔inline 折叠动画（过渡更稳定）。月视图内容本身是网格+卡片，
        // 不需要 large title 的空间感。
        .navigationBarTitleDisplayMode(.inline)
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
                        .accessibilityIdentifier(AccessibilityID.todayJump)
                }
                    .tint(accent)
                    .pressableFeedback()
            }
            ToolbarItem(placement: .topBarTrailing) {
                // 原生 iOS 风格：系统「+」进入新建日程（替代原自定义渐变 FAB）
                NavigationLink {
                    EventEditView(editing: nil, defaultDate: selectedDate).environment(store)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .touchTarget(min: AppTheme.Touch.minTarget)
                }
                .accessibilityLabel("新建日程")
                .accessibilityIdentifier(AccessibilityID.monthNewEvent)
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
            // SettingsView 自身不再包导航栈，sheet 场景补一层（push 场景继承外层导航）
            NavigationStack { SettingsView().environment(store) }
        }
        // 本地选中 → 同步外部（iPad 双栏联动 DayDetailView）
        .onChange(of: selectedDate) { _, newValue in
            externalSelectedDate?.wrappedValue = newValue
        }
        // 外部选中变化（DateJumpView / 双栏联动）→ 同步本地
        .onChange(of: externalSelectedDate?.wrappedValue) { _, newValue in
            guard let nv = newValue, !nv.isSameDay(as: selectedDate) else { return }
            selectedDate = nv
            currentMonth = nv.firstDayOfMonth
        }
        // 月份变化 → 预填充相邻两个月网格（滑动动画期间直接命中缓存，零同步重算）
        // 同时清空滑动预览月（切月后 preview 网格已无意义，避免重复渲染）
        .onChange(of: currentMonth) { _, newMonth in
            #if canImport(UIKit)
            previewMonth = nil
            #endif
            prefetchGrid(for: newMonth.addingMonths(-1))
            prefetchGrid(for: newMonth)
            prefetchGrid(for: newMonth.addingMonths(1))
        }
        // 网格缓存填充（SwiftUI 未定义行为警告修复）：
        // 在 body 求值之外异步重建缓存；期间 body 命中缓存或临时纯计算，不再写 @State
        .task(id: gridCacheKey) {
            let model = buildGridModel(for: currentMonth)
            gridCache[model.cacheKey] = model
        }
    }

    /// 预构建某月网格模型写入缓存（滑动切换零卡顿的关键）
    private func prefetchGrid(for month: Date) {
        let model = buildGridModel(for: month)
        gridCache[model.cacheKey] = model
    }

    /// 月历纵向列：月份标题 + 节气条 + 网格（iPhone 下方还有当日卡片）。
    private func monthColumn(accent: Color) -> some View {
        VStack(spacing: 0) {
            monthHeader()
                .padding(.horizontal, AppTheme.Spacing.xl)
                .padding(.top, 8).padding(.bottom, AppTheme.Spacing.sm)
            solarTermBar(accent: accent)
                .padding(.horizontal, AppTheme.Spacing.xl)
                .padding(.bottom, AppTheme.Spacing.xs)
            // 卡片式月份滑动（完全跟手）：
            // 拖动中当前月卡片 1:1 跟随手指位移，相邻月网格预渲染在另一侧同速移动；
            // 松手后按位移/速度决定翻页（transition 接管收尾动画）或回弹。
            #if canImport(UIKit)
            ZStack {
                // 底层：拖动方向的相邻月（左滑=下月在右、右滑=上月在左），跟手同速
                if let pm = previewMonth {
                    calendarShell(accent: accent)
                        .id(pm)
                        .offset(x: dragOffsetX < 0 ? dragOffsetX + monthWidth : dragOffsetX - monthWidth)
                }
                // 顶层：当前月，1:1 跟手
                calendarShell(accent: accent)
                    .id(currentMonth)
                    .offset(x: dragOffsetX)
                    .scaleEffect(isDragging ? 0.992 : 1.0)
                    .transition(.asymmetric(
                        insertion: .move(edge: monthSlideEdge),
                        removal: .move(edge: monthSlideEdge == .trailing ? .leading : .trailing)
                    ))
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            // 容器宽度（翻页阈值用）：background 里读尺寸，不改变布局高度
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { monthWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, w in monthWidth = w }
                }
            )
            .simultaneousGesture(swipeMonthGesture(width: monthWidth))
            #else
            calendarShell(accent: accent)
                .id(currentMonth)
                .padding(.horizontal, AppTheme.Spacing.md)
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

    /// 原生风格背景：系统分组背景 + 极淡节日染色（去掉 iOS 26 模糊色斑壁纸特效）
    @ViewBuilder
    private func festiveBackground(accent: Color) -> some View {
        ZStack {
            Color.systemGroupedBackground
            LinearGradient(
                colors: [accent.opacity(0.04), Color.clear],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    private func monthHeader() -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.md) {
            // 月份标题可点击 → 弹出日期跳转（主流日历交互：点标题选月份/年份）
            Button {
                showDateJump = true
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.sm) {
                    // verbatim：避免 LocalizedStringKey 对 Int 插值按系统 locale 加千位分隔
                    // （英文 locale 下 2026 会渲染成 "2,026"）；numericText 让月/年数字滚动过渡更自然
                    Text(verbatim: "\(currentMonth.month)月")
                        .font(AppTheme.Font.hero).foregroundStyle(Color.label)
                        .contentTransition(.numericText())
                    Text(verbatim: "\(currentMonth.year)")
                        .font(AppTheme.Font.title3).foregroundStyle(Color.tertiaryLabel)
                        .contentTransition(.numericText())
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.tertiaryLabel)
                        .padding(.bottom, 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pressableFeedback()
            .accessibilityLabel("选择月份或年份")
            .accessibilityHint("打开日期跳转面板")
            Spacer()
            HStack(spacing: AppTheme.Spacing.sm) {
                Button {
                    changeMonth(by: -1)
                } label: { chevronButton("chevron.left") }
                    .pressableFeedback()
                Button {
                    changeMonth(by: 1)
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
                    Text(String(format: NSLocalizedString("还有 %d 天", comment: ""), next.daysRemaining))
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
        Image(systemName: name).font(.title2.weight(.semibold)).foregroundStyle(Color.systemBlue)
            .frame(width: AppTheme.Touch.minTarget, height: AppTheme.Touch.minTarget)
            .contentShape(Circle())
            .accessibilityLabel(name == "chevron.left" ? String(localized: "上个月") : String(localized: "下个月"))
    }

    /// 卡片式月份切换：设置滑动进入方向后用 withAnimation 变更 currentMonth，
    /// 触发 ZStack 中日历网格的 .id + .transition 滑动转场（旧网格滑出、新网格滑入）。
    /// 同时把选中日期联动到新月份（同日存在则保持，否则取月末），
    /// 避免"切月后日期卡仍显示上月内容"的逻辑不通。
    private func changeMonth(by offset: Int) {
        monthSlideEdge = offset > 0 ? .trailing : .leading
        withAnimation(AppTheme.Motion.screen) {
            currentMonth = currentMonth.addingMonths(offset)
            selectedDate = Self.clampedToMonth(selectedDate, in: currentMonth)
        }
    }

    /// 将日期钳制到目标月份：同日存在则保持原日，否则取目标月最后一天（如 1/31 → 2/28）。
    private static func clampedToMonth(_ date: Date, in month: Date) -> Date {
        let cal = Calendar(identifier: .gregorian)
        var comps = cal.dateComponents([.year, .month, .day], from: date)
        let target = cal.dateComponents([.year, .month], from: month)
        comps.year = target.year
        comps.month = target.month
        if let day = comps.day,
           let dayCount = cal.range(of: .day, in: .month, for: month)?.count,
           day > dayCount {
            comps.day = dayCount
        }
        return cal.date(from: comps) ?? date
    }

    #if canImport(UIKit)
    /// 完全跟手滑动：拖动中卡片 1:1 跟随手指；松手后按位移/甩动速度判定翻页或回弹。
    private func swipeMonthGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: swipeThreshold, coordinateSpace: .local)
            .onChanged { value in
                let dx = value.translation.width
                if !isDragging {
                    let dy = value.translation.height
                    // 首次水平判定：水平占主导才进入跟手态；
                    // 纵向滚动（页面滚动）与轻微点按（日期选中）一律放行
                    guard abs(dx) > 1.5 * abs(dy) else { return }
                }
                isDragging = true
                dragOffsetX = dx
                // 左滑预渲染下月（右侧）、右滑预渲染上月（左侧）；缓存预填充后零卡顿
                previewMonth = dx < 0 ? currentMonth.addingMonths(1) : currentMonth.addingMonths(-1)
            }
            .onEnded { value in
                isDragging = false
                let dx = value.translation.width
                let predicted = value.predictedEndTranslation.width
                // 容器宽度兜底：background GeometryReader 未注入前（首帧）用保守值，防止误翻页
                let w = width > 0 ? width : 360
                // 翻页判定：位移超过容器宽度 28% 或甩动速度足够
                if abs(dx) > w * 0.28 || abs(predicted - dx) > w * 0.45 {
                    let target = dx < 0 ? currentMonth.addingMonths(1) : currentMonth.addingMonths(-1)
                    monthSlideEdge = dx < 0 ? .trailing : .leading
                    withAnimation(AppTheme.Motion.screen) {
                        currentMonth = target
                        selectedDate = Self.clampedToMonth(selectedDate, in: target)
                        dragOffsetX = 0
                    }
                } else {
                    // 未过阈值：回弹原位（preview 网格在屏幕外，直接清空）
                    previewMonth = nil
                    withAnimation(AppTheme.Motion.screen) {
                        dragOffsetX = 0
                    }
                }
            }
    }
    #endif

    /// 返回当前月的网格派生数据；月份/事件版本未变时直接复用缓存。
    /// SwiftUI 未定义行为警告修复：body 求值期间**不再回写 @State gridCache**
    /// （Xcode 报 "Modifying state during view update, this will cause undefined behavior"，
    ///  调用栈直指本方法）。未命中时直接构建返回（纯计算无副作用），
    /// 缓存由 `.task(id: gridCacheKey)` 在 body 外异步填充。
    private func gridModel(for month: Date) -> MonthGridModel {
        // body 求值期间只读缓存，不写 @State（避免 SwiftUI 未定义行为警告）；
        // 缓存写入统一由 .task(id:) 与 onChange 预填充负责
        if let cached = gridCache[cacheKey(month: month)] { return cached }
        return buildGridModel(for: month)
    }

    /// 纯计算构建网格模型（无副作用，可在 body 与 .task 中安全调用）。
    private func buildGridModel(for month: Date) -> MonthGridModel {
        let slots = daysForMonth(month)
        var cells: [GridCellModel] = []
        cells.reserveCapacity(slots.count)
        for slot in slots {
            let d = slot.date
            // 农历转换 → 节日查询（复用预计算 lunar）→ 颜色解析，每月只做一次
            let lunar = d.lunar
            let festivals = FestivalManager.festivals(on: d, lunar: lunar)
            // 节气与节日可同日并存（如清明既是节气也是祭祖日）：
            // 节气 → 格内绿色"节气名"文字标注，不染色背景；
            // 节日 → 格内节日名文字 + 节日色（不再浅染背景，除选中外无"选择框"）
            let solarTermFest = festivals.first { $0.kind == .solarTerm }
            let otherFest = festivals.first { $0.kind != .solarTerm }
            let festivalTint = otherFest.map { Color(hex: $0.accentHex) }
            let festivalName = otherFest?.localizedName
            let solarTermName = solarTermFest?.localizedName
            let solarTermTint = solarTermFest.map { Color(hex: $0.accentHex) }
            let stats = store.eventStats(on: d)
            cells.append(GridCellModel(
                date: d,
                inCurrentMonth: slot.inCurrentMonth,
                lunar: lunar,
                huangli: HuangliGenerator.generate(for: d),
                festivalTint: festivalTint,
                festivalName: festivalName,
                solarTermName: solarTermName,
                solarTermTint: solarTermTint,
                holidayType: HolidayProvider.info(for: d).type,
                eventCount: stats.count,
                eventPriorities: stats.priorities
            ))
        }
        return MonthGridModel(monthKey: month, revision: store.revision, cells: cells)
    }

    /// 缓存键：月份时间戳 + 事件版本
    private func cacheKey(month: Date) -> String {
        "\(month.timeIntervalSince1970)-\(store.revision)"
    }

    /// 缓存失效键：月份或事件版本变化时重建（用于 .task(id:) 触发）。
    private var gridCacheKey: String {
        "\(currentMonth.timeIntervalSince1970)-\(store.revision)"
    }

    private func calendarShell(accent: Color) -> some View {
        let grid = gridModel(for: currentMonth)
        let columns = [GridItem](repeating: GridItem(.flexible(), spacing: 0), count: 7)
        return VStack(alignment: .leading, spacing: 0) {
            WeekHeaderView(weekStart: weekStart)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(grid.cells) { cell in
                    let d = cell.date
                    DayCellView(date: d, isCurrentMonth: cell.inCurrentMonth,
                                isSelected: d.isSameDay(as: selectedDate),
                                isToday: d.isToday,
                                lunar: cell.lunar,
                                huangli: cell.huangli,
                                hasEvents: cell.eventCount > 0,
                                eventPriorities: cell.eventPriorities,
                                eventCount: cell.eventCount,
                                festivalTint: cell.festivalTint,
                                cellAccent: cell.festivalTint
                                    ?? (d.isSameDay(as: selectedDate) ? accent : nil),
                                festivalName: cell.festivalName,
                                solarTermName: cell.solarTermName,
                                solarTermTint: cell.solarTermTint,
                                holidayType: cell.holidayType)
                        .equatable()
                        .frame(minHeight: AppTheme.Touch.minCellHeight)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(AppTheme.Motion.pressInOut) { selectedDate = d }
                        }
                        // 原生上下文菜单：长按日期格 → 快捷操作（原创，克制不加额外功能）
                        .contextMenu {
                            Button {
                                withAnimation(AppTheme.Motion.pressInOut) { selectedDate = d }
                            } label: {
                                Label("选中此日", systemImage: "checkmark.circle")
                            }
                            Button {
                                copyDateText(d)
                            } label: {
                                Label("复制日期", systemImage: "doc.on.doc")
                            }
                        }
                }
            }
            // 原生选中触觉反馈：选中日期轻震（iOS 17+ 系统 sensoryFeedback，无自定义引擎）
            .sensoryFeedback(.selection, trigger: selectedDate)
            .padding(.horizontal, isIPadSplit ? AppTheme.Spacing.lg : AppTheme.Spacing.md)
            .padding(.bottom, AppTheme.Spacing.lg)
        }
        .padding(.top, AppTheme.Spacing.xs)
        // 原生化：液态玻璃卡片 → 系统次要分组背景卡片（去自定义阴影）
        .background(
            Color.secondarySystemGroupedBackground,
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.xxl, style: .continuous)
        )
        .contentShape(Rectangle())
        // 月份横滑手势统一在 monthColumn 以 simultaneousGesture 挂载（避免拦截日期点按与纵向滚动）
    }

    /// 复制选中日期的中文长格式到剪贴板（上下文菜单动作）
    private func copyDateText(_ date: Date) {
        #if canImport(UIKit)
        UIPasteboard.general.string = date.formatted(
            Date.FormatStyle(date: .long, time: .omitted, locale: Locale(identifier: "zh_Hans_CN")))
        #endif
    }

    private func daysForMonth(_ month: Date) -> [DaySlot] {
        let first = month.firstDayOfMonth
        // 按每周起始日计算前置空位：weekStart=1(周日) → (wd-1)；weekStart=2(周一) → (wd+5)%7
        let leading = (first.weekday - weekStart + 7) % 7
        let totalDays = month.daysInMonth
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

        return VStack(alignment: .leading, spacing: 0) {
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
                    if selLunar.isUnsupported {
                        // 越界（1900 前 / 2100 后）：隐藏农历与干支/生肖
                        Text("农历数据暂不支持此日期")
                            .font(AppTheme.Font.title3).foregroundStyle(Color.secondaryLabel)
                    } else {
                        // 农历规范两行排版：年干支小字一行，月日大字一行，
                        // 视觉层级清晰且不再被右侧天气块挤压换行（月日行单行保护）
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(selLunar.yearGanZhi)年")
                                .font(AppTheme.Font.caption2.weight(.medium))
                                .foregroundStyle(Color.secondaryLabel)
                                .lineLimit(1)
                            Text("\(selLunar.monthName)\(selLunar.dayName)")
                                .font(AppTheme.Font.title3)
                                .foregroundStyle(Color.label)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        HStack(spacing: AppTheme.Spacing.xs) {
                            // 年干支/生肖按农历春节为界（与离散黄历库口径一致；立春口径 API 已提供备用）
                            ChipLabel(title: "\(selLunar.yearGanZhi)", tint: Color.systemIndigo)
                            ChipLabel(title: selLunar.yearAnimal, systemImage: "pawprint.circle.fill", tint: Color.systemOrange)
                        }
                    }
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
                }
                Spacer(minLength: 0)
                // 日期卡片右上：大天气图标（随天气码直观切换）+ 图标下方文字块（温度大字），
                // 整体底部与左侧日期块对齐（Spacer 撑开）
                VStack(alignment: .trailing, spacing: 6) {
                    WeatherIconView(selectedDate: selectedDate)
                    WeatherCardView(selectedDate: selectedDate, alignment: .trailing)
                    Spacer(minLength: 0)
                }
            }

            // 宜做/勿做卡片：固定高度（标题行 + 两行标签），位置与尺寸不随
            // 宜忌条目数量/词条换行浮动，始终锚定在日期天气卡片下方固定位置；
            // 即使某日宜忌为空也渲染占位（"—"），避免下方"今日安排"上下跳动。
            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                yiBlock(huangli.yi, maxShown: 6)
                Divider().frame(maxHeight: .infinity)
                jiBlock(huangli.ji, maxShown: 6)
            }
            // 固定两行标签高度：标题行 20 + 间距 4 + 标签两行约 46 ≈ 70，加上下留白
            .frame(height: 78, alignment: .top)
            .clipped()
            // 顶部/横向/底部 padding 都在背景内：背景框撑满块状感，同时
            // 让「宜/勿」标题距离背景顶边 8pt 呼吸，不贴边缘（外部 12pt 间隙不变）
            .padding(.top, AppTheme.Spacing.sm)
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.bottom, AppTheme.Spacing.sm)
            .softChipBackground(material: .thinMaterial)
            // 顶部 12pt 固定间隙放在背景框之外：与日期天气卡片之间始终是
            // 固定的透明间距（不随日期内容、天气行数变化）
            .padding(.top, AppTheme.Spacing.md)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack {
                    Text("今日安排").font(AppTheme.Font.bodyBold).foregroundStyle(Color.label)
                    Spacer()
                    if !todaysEvents.isEmpty {
                        Text(String(format: NSLocalizedString("%d 项", comment: ""), todaysEvents.count)).font(AppTheme.Font.caption).foregroundStyle(Color.tertiaryLabel)
                    }
                }
                if todaysEvents.isEmpty {
                    // 空态插画：扁平纯色圆底图标（去渐变，符合 iOS 扁平风格）
                    HStack(spacing: AppTheme.Spacing.md) {
                        ZStack {
                            Circle()
                                .fill(accent.opacity(0.10))
                                .frame(width: 48, height: 48)
                            Image(systemName: "sparkles")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(accent)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "这一天很空闲")).font(AppTheme.Font.bodyBold).foregroundStyle(Color.label)
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
                                Text(isPanelExpanded ? String(localized: "收起") : String(format: NSLocalizedString("查看全部 %d 项 →", comment: ""), todaysEvents.count))
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
            // 今日安排与上方宜忌块之间保留正常区块间距（VStack 已 spacing 0）
            .padding(.top, AppTheme.Spacing.md)

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
            // 与上方今日安排内容之间固定 12pt 间距（不随日程条数变化）
            .padding(.top, AppTheme.Spacing.md)
        }
        .padding(AppTheme.Spacing.xl)
        .glassCard(radius: 28, material: .regularMaterial,
                   tint: accent, shadow: AppTheme.Shadow.raised)
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
        // 宜/忌标签是整体展示信息：VoiceOver 一次性读出全部，避免逐个标签打断
        .accessibilityElement(children: .combine)
    }
}

#Preview { CalendarMonthView().environment(EventStore.shared) }
#Preview("iPad Split") { iPadRootView().environment(EventStore.shared) }

#endif
