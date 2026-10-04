#if canImport(SwiftUI)
import SwiftUI
import LunarCore

// MARK: - N-3 月卡 chrome 高度上报

/// 月卡固定 chrome（月份标题 + 节气条 + 星期表头 + 卡片内外边距）的累加上报。
/// 各段用 `.background(GeometryReader)` 写入自身高度，reduce 求和后由
/// `CalendarMonthView` 读取，替换 `elasticCellHeight` 里的 170 魔数。
/// 节气条显隐两态天然正确：不存在时该段不上报，高度按 0 参与求和。
struct MonthChromeHeightKey: PreferenceKey {
    // N-3 修复：Swift 6 严格并发下 `static var` 是非隔离的全局共享可变状态，不并发安全。
    // PreferenceKey 协议只要求 get-only，`static let` 满足协议且为 Sendable 不可变状态
    // （Xcode 建议方案①，也是 SwiftUI 官方在 Swift 6 下的标准写法）。
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value += nextValue()
    }
}

struct CalendarMonthView: View {
    @State var currentMonth: Date = Date().firstDayOfMonth
    /// 本地选中日期（唯一真相，@State 保证点击后必然重绘）。
    /// 外部传入 binding 时（iPad 双栏）通过 onChange 双向同步，不在 init 里手动接线，
    /// 彻底规避"点击日期无反应"（此前 @Binding←局部引用/投影接线的运行时失效问题）。
    @State var selectedDate: Date = Date()
    /// 月份卡片滑动的进入方向：.trailing=下月从右侧滑入，.leading=上月从左侧滑入
    /// 交互态集中在 `MonthGridInteraction`（P4-1 第 5b 步第 1 小步）。
    /// 这与"数据态"（selectedDate / currentMonth / auxiliaryPage / eventEditSheet）分开：
    /// 前者是拖拽与测量，后者是业务真相。集中之后，monthColumn/calendarShell 的抽取
    /// 才会从"13 个输入 + 6 个回调 + 手势类型"退化成"传一个模型 + 几个回调"。
    /// 用 class + @Observable：闭包里对它的字段赋值不需要 `self` 可变（正是 @State 能用的原因）。
    @State var interaction = MonthGridInteraction()

    #if canImport(UIKit)
    /// 跟手滑动偏移：手指移动多少卡片就移动多少（1:1），松手后回弹或翻页
    /// 拖动中预览的相邻月份（左滑=下月、右滑=上月），缓存预填充后零卡顿
    /// 日历容器宽度（翻页/回弹阈值判定用），由 background GeometryReader 注入
    /// 最小拖动距离：小于该距离视为点按（日期选中仍可用）
    let swipeThreshold: CGFloat = 8
    #endif
    /// 中栏可视高度（仅 iPad 用）：弹性行高的计算依据，由背景 GeometryReader 注入。
    /// 0 = 尚未测量，此时行高退回 `minHeight: 56` 的旧行为（多一次布局即可修正）。
    /// N-3：月卡「chrome」真实高度（月份标题 + 节气条 + 星期表头 + 卡片内外边距），
    /// 由 `MonthChromeHeightKey` PreferenceKey 上报求和替换旧的 170 魔数。
    /// 节气条显隐两态都会上报真实值（不存在时不上报，天然为 0 参与求和）。
    /// 0 = 尚未测量，此时回退旧估算值（多一次布局即可修正，行为不劣化）。
    /// 月网格派生数据缓存：仅当月份或事件版本变化时重建。
    /// 横滑期间 interaction.dragOffsetX 每帧令 body 重算，但命中此缓存后 42 格的
    /// 农历转换/黄历生成/节日遍历/事件统计全部 O(1) 复用，不再每帧重算。
    /// 月网格派生数据缓存（多月份字典）：key = "月份-版本"。
    /// 滑动切换月份时相邻月份已预填充 → 动画期间零同步重算，消除卡顿。
    @State var gridCache: [String: MonthGridModel] = [:]
    /// 每周起始日（Calendar weekday 语义：1=周日，2=周一；设置页可改）
    @AppStorage("Lunisolar.weekStart") var weekStart: Int = 1
    @Environment(EventStore.self) var store
    @Environment(\.horizontalSizeClass) private var hSizeClass

    /// 是否由本视图自行包一层 NavigationStack。
    /// - iPhone 根页：true（自身即导航根）
    /// - iPad 双栏侧栏：false（由 NavigationSplitView 的列提供导航上下文，避免侧栏内嵌栈）
    private let embedsInNavigationStack: Bool
    /// 可选外部绑定（iPad 双栏与 DayDetailView 联动）；本地 @State 为唯一真相，onChange 双向同步
    // MARK: - 输入与派生
    private var externalSelectedDate: Binding<Date>?
    // iPad 侧栏内「倒数日 / 设置」改用 sheet 弹出（push 会挤在窄列里）。
    // 两类模态各收一个枚举驱动（MonthAuxiliaryPage / MonthEventEditSheet），
    // 5 个 sheet 收敛为 3 个 `.sheet(item:)`，sheet 本体见 CalendarMonthSheets.swift。
    /// 程序化入口的辅助页（导航性质：倒数日 / 设置）
    @State var auxiliaryPage: MonthAuxiliaryPage?
    /// 事件编辑模态的两种目标（长按日期格新建 / 深链打开已有事件）
    @State var eventEditSheet: MonthEventEditSheet?
    /// N-4：DayAccent 缓存。`DayAccent(date:)` 内部做农历转换 + 节日遍历 + 颜色对比度解析，
    /// 横滑期间 body 每帧重算会重复这串 O(节日表) 工作。改为：选中日变化时才重建，
    /// body 每帧直接读缓存（滑动月份不变选中日 → 命中缓存零重算）。
    @State private var cachedDayAccent: DayAccent = DayAccent(date: Date())

    init(selectedDate: Binding<Date>? = nil, embedsInNavigationStack: Bool = true) {
        self.embedsInNavigationStack = embedsInNavigationStack
        self.externalSelectedDate = selectedDate
        if let binding = selectedDate {
            // 外部绑定存在时以它的当前值作为初始选中（@State 显式初始化是官方支持模式）
            self._selectedDate = State(initialValue: binding.wrappedValue)
        }
    }

    /// 是否走 iPad 分栏布局（弹性行高/更大间距）。
    /// ⚠️ 不能用 `hSizeClass == .regular`：iPhone Plus/Max 横屏也是 regular，
    /// 会让手机套上 iPad 的网格布局（P3-2）。判据统一在 `LayoutIdiom`。
    private var isIPadSplit: Bool { LayoutIdiom.usesSplitLayout(horizontalSizeClass: hSizeClass) }

    // MARK: - 视图主体
    // 目录（P4-1）：本文件已按职责分成若干私有方法，抽取成独立 struct 时按这些分段走即可：
    //   月列与外壳 → monthColumn / calendarShell / elasticCellHeight
    //   头部       → monthHeader / solarTermBar / chevronButton
    //   强调色     → dayAccentForToday / accentColorForToday / festiveBackground
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
        // dayAccentForToday 内部要做农历转换 + 节日遍历 + 颜色解析，
        // 背景/FAB/tint/节气条/工具条/网格选中格都要用，每次 body 只算一次后透传，
        // 避免横滑每帧重复 6~8 次。控件层（tint / 填充）取其中已过对比度校验的那两层。
        let dayAccent = dayAccentForToday
        let accent = dayAccent.decorative
        let controlTint = dayAccent.controlTint
        return ZStack {
            // 节日自适应柔和渐变背景（春节自动偏红、中秋偏金、平日系统灰）
            festiveBackground(accent: accent)
                .ignoresSafeArea()

            // iPhone：当日卡片内容可能超过一屏，允许纵向滚动。
            // iPad：仍包 ScrollView（防止内容超高被裁切），但先把可视高度量出来交给月卡，
            // 让格子按可视区高度弹性分配（56~96pt），避免月卡下方留出大片空白。
            // 量高度放在背景 GeometryReader 里：不参与布局、不改变高度（与 interaction.monthWidth 同一手法）。
            ScrollView(showsIndicators: false) {
                monthColumn(accent: dayAccent)
            }
            // N-3：读取月卡 chrome 真实高度（月份标题 + 节气条 + 星期表头）
            .onPreferenceChange(MonthChromeHeightKey.self) { value in
                interaction.chromeHeight = value
            }
            // P1-2：方向键移动选中日期（iPad 外接键盘）。
            // selectDay 本身处理跨月联动，越界日期（1900 前/2100 后）由 LunarDate 层兜底。
            .onKeyPress(.leftArrow) {
                selectDay(selectedDate.addingDays(-1))
                return .handled
            }
            .onKeyPress(.rightArrow) {
                selectDay(selectedDate.addingDays(1))
                return .handled
            }
            // 2026-09-29：取消折叠后 iPhone 不再按可视区弹性分配行高——
            // 恢复内容自适应高度（格子高度由内容决定，避免大屏上格子过高、
            // 日期数字与农历/节气文字之间的上下留白过大）。
            // 可视高度测量仅保留给 iPad 分栏（elasticCellHeight 的 guard 已恢复 isIPadSplit）。
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { interaction.columnHeight = geo.size.height }
                        .onChange(of: geo.size.height) { _, h in interaction.columnHeight = h }
                }
            }
        }
        .navigationTitle("日历")
        #if canImport(UIKit)
        // inline 模式：导航栏紧凑（减少头部大块空白）、标题必然渲染、
        // 无 large↔inline 折叠动画（过渡更稳定）。月视图内容本身是网格+卡片，
        // 不需要 large title 的空间感。
        #if canImport(UIKit)
        .inlineTitleBar()
        #endif
        .toolbarBackground(.navBar, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .platformTopBarLeading) {
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
                    .tint(controlTint)
                    .pressableFeedback()
                    // P1-2：⌘T 回到今天（iPad 键盘/妙控板用户）
                    .keyboardShortcut("t", modifiers: .command)
            }
            ToolbarItem(placement: .platformTopBarTrailing) {
                // 原生 iOS 风格：系统「+」进入新建日程（替代原自定义渐变 FAB）
                NavigationLink {
                    EventEditView(editing: nil, defaultDate: selectedDate).environment(store)
                } label: {
                    Image(systemName: "plus")
                        .font(AppTheme.Font.title3)
                        .touchTarget(min: AppTheme.Touch.minTarget)
                }
                .accessibilityLabel("新建日程")
                .accessibilityIdentifier(AccessibilityID.monthNewEvent)
                // P1-2：⌘N 新建日程（iPad 键盘/妙控板用户）
                .keyboardShortcut("n", modifiers: .command)
            }
            ToolbarItem(placement: .platformTopBarTrailing) {
                Menu {
                    // 入口收敛（UI_DESIGN_REVIEW P0-2）：同一功能只留一条主路径。
                    // - 「回到今天」已由左侧工具栏按钮承担，菜单里删掉；
                    // - iPhone 的「设置」由底部「我的」Tab 承担；
                    // - iPad 的「倒数日 / 设置」由侧栏承担（本页在 iPad 只是月历节）。
                    // 保留 iPhone 的「倒数日」：它是 iPhone 上**唯一**的入口（没有对应 Tab，
                    // 只有卡片深链能绕开菜单），删掉等于让这个功能消失。
                    Button { auxiliaryPage = .dateJump } label: { Label("跳转到日期", systemImage: "calendar.badge.clock") }
                    if !isIPadSplit {
                        Divider()
                        // 全部日程：统一管理页（搜索 / 筛选 / 批量查看）
                        NavigationLink { AllEventsView().environment(store) }
                            label: { Label("全部日程", systemImage: "list.bullet.rectangle") }
                        NavigationLink { CountdownView() } label: { Label("倒数日", systemImage: "hourglass") }
                    }
                } label: {
                    // P3-6：这里原先是光秃秃的 `Image(systemName:)`，实测**控件在无障碍树里
                    // 没有名字**（名字落在子 Image 上），而给它挂 `.accessibilityLabel` 也不生效
                    // （挪到 `.pressableFeedback()` 之后、加 `children: .combine` 都试过，见计划）。
                    // 换成 `Label`（文字给无障碍、导航栏里仍只渲图标，与工具栏里的 `Label` 一致），
                    // 不再依赖任何 accessibility 修饰符。
                    Label(NSLocalizedString("功能菜单", comment: "月历工具栏入口菜单"),
                          systemImage: "slider.horizontal.3")
                        .font(.title3).foregroundStyle(Color.secondaryLabel)
                        .symbolRenderingMode(.hierarchical)
                        .touchTarget(min: AppTheme.Touch.minTarget)
                }
                .pressableFeedback()
                // 稳定标识：菜单标题来自 SF Symbol，随界面语言变化，UI 测试不能按文案找
                .accessibilityIdentifier(AccessibilityID.monthMenu)
            }
        }
        #endif
        // sheet 分工与本体已收口到 CalendarMonthSheets.swift：
        // 5 个布尔/可选状态收敛为 auxiliaryPage / eventEditSheet 两个枚举驱动的 .sheet(item:)        .tint(controlTint)
        .modifier(MonthSheetsModifier(
            auxiliaryPage: $auxiliaryPage,
            eventEditSheet: $eventEditSheet,
            selectedDate: $selectedDate,
            currentMonth: $currentMonth
        ))
        // P1：深链 / 通知 / Live Activity 点击 → 直接打开事件详情
        // initial: true —— 深链可能在视图出现之前就写好了 ID（冷启动、iPad 切侧栏到日历节时
        // 中间栏是新建的），此时 onChange 默认不会触发，必须让首次求值也消费一次。
        .onChange(of: NavigationCoordinator.shared.pendingOpenEventID, initial: true) { _, id in
            guard let id else { return }
            if let ev = store.events.first(where: { $0.id == id }) {
                // 同步选中日期到该事件所在月
                selectedDate = ev.startDate
                currentMonth = ev.startDate.firstDayOfMonth
                eventEditSheet = .existing(ev)
            }
            NavigationCoordinator.shared.pendingOpenEventID = nil
        }
        // P1：倒数日 / 纪念日卡片点击 → 打开倒数日列表并聚焦该条（同上，需 initial 消费）
        .onChange(of: NavigationCoordinator.shared.pendingOpenCountdownID, initial: true) { _, id in
            guard let id else { return }
            auxiliaryPage = .countdown(focusID: id)
            NavigationCoordinator.shared.pendingOpenCountdownID = nil
        }
        // 本地选中 → 同步外部（iPad 双栏联动 DayDetailView）。
        // initial: true —— 外部 binding 提供的初始选中日也要走一次缓存重建，
        // 避免 @State 默认 Date() 与真实初始日不一致。
        .onChange(of: selectedDate, initial: true) { _, newValue in
            externalSelectedDate?.wrappedValue = newValue
            // N-4：选中日变化 → 重建 DayAccent 缓存（横滑翻月时选中日不变，跳过此处）
            cachedDayAccent = DayAccent(date: newValue)
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
            interaction.previewMonth = nil
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
            // 缓存收敛到「当前月 ±1」：键里带 revision，每编辑一次事件就会产生一批新键，
            // 旧键永不淘汰 → 内存随「浏览月份数 × 编辑次数」单调增长。
            // 未命中时 gridModel(for:) 会退回纯计算，因此淘汰永远安全。
            let keep = [currentMonth.addingMonths(-1), currentMonth, currentMonth.addingMonths(1)]
                .map { cacheKey(month: $0) }
            if gridCache.count > keep.count {
                gridCache = gridCache.filter { keep.contains($0.key) }
            }
        }
    }

    /// 预构建某月网格模型写入缓存（滑动切换零卡顿的关键）
    // MARK: - 月列与外壳
    private func monthColumn(accent: DayAccent) -> some View {
        // 装配层：只负责把 interaction 与回调递给月列，并挂上横滑手势。
        // 状态都不在这里——数据态在 CalendarMonthView，交互态在 MonthGridInteraction。
        let column = CalendarMonthColumn(interaction: interaction,
                            month: currentMonth,
                            accent: accent,
                            isIPadSplit: isIPadSplit,
                            selectedDate: selectedDate,
                            weekStart: weekStart,
                            gridProvider: { gridModel(for: $0) },
                            onSelectDay: { selectDay($0) },
                            onNewEvent: { d in selectedDate = d; eventEditSheet = .new(d) },
                            onCopyDate: { copyDateText($0) },
                            onChangeMonth: { by in changeMonth(by: by) },
                            onTapDateJump: { auxiliaryPage = .dateJump },
                            onCommitMonth: { target in
                                currentMonth = target
                                selectedDate = Self.clampedToMonth(selectedDate, in: target)
                            })
        // 横滑手势不在这里挂：它必须挂在列内部的**网格区**上。
        // 2026-10-04 回归：P4-1 抽取时把手势上移到了整列（= ScrollView 的直接子视图），
        // 于是 DragGesture 抢走纵向拖动，真机表现为"主页上下无法滑动"。
        return column
    }
    // MARK: - 节日自适应背景与强调色

    /// 当天节日强调色，按 P0-4 分两层（见 `DayAccent`）。
    /// 注意：这里被 `calendarContent` 每次 body 取一次后逐层透传，避免重复做节日遍历。
    /// N-4：DayAccent 缓存读取。真正的重建在 `onChange(of: selectedDate)` 里做，
    /// 滑动翻月（选中日不变）时 body 每帧直接命中缓存，零重复计算。
    // MARK: - 强调色
    private var dayAccentForToday: DayAccent { cachedDayAccent }
    private var accentColorForToday: Color { cachedDayAccent.decorative }

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

    // MARK: - 头部：月份标题 / 节气条 / 箭头
    /// 弹性行高：把可视高度扣掉「月份标题 + 节气条 + 星期表头 + 内边距」后
    /// 按行均分，夹在 56（可点下限）~96（大屏上限）之间。
    /// 2026-09-29：恢复 `isIPadSplit` 守卫——仅 iPad 分栏启用；
    /// iPhone 取消折叠后恢复内容自适应高度（格子过高会拉开数字与农历的上下留白）。
    /// 返回 nil 表示不限高 —— 仅在可视高度尚未测量时回退 `minHeight` 行为。
    ///
    /// N-3：chrome 不再用 170 魔数，改用 `MonthChromeHeightKey` 上报的真实高度
    /// （月份标题 + 节气条 + 星期表头）加上固定的卡片内外边距与网格行距。
    /// 上报未就绪（=0）时回退旧估算值 170——行为不劣化，多一次布局即修正。
    /// 单个月份卡片（表头 + 42 格网格）。
    /// 必须按传入月份取网格：跟手滑动时同一份日历要同时渲染当前月与相邻月。
}


#Preview { CalendarMonthView().environment(EventStore.shared) }
#Preview("iPad Split") { iPadRootView().environment(EventStore.shared) }

#endif