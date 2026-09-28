#if canImport(SwiftUI)
import SwiftUI
import Observation

// MARK: - App 根视图（宿主复用）
//
// ⚠️ 本模块不声明 @main（避免 swift test 链接时与测试 runner 的 main 冲突，
// 真实进程入口在 LunisolarHostApp/HostApp.swift）。
//
// 宿主 App 必须使用本 `AppRootView` 作为 WindowGroup 根视图——
// iCloud 协调器启动重建、防抖保存后台落盘、通知续排、外观偏好等全部生命周期
// 接线都挂在这里；宿主只负责 @main、WindowGroup 与 App Group ID 注入。
//
// P0 收口说明：launch / scenePhase / 事件 revision / 时间胶囊开关 等生命周期副作用
// 全部在 AppLifecycleCoordinator；"选候选 → ActivityKit" 在 TimeCapsuleCoordinator；
// qinghe:// 深链统一走 DeepLinkRouter；跨 Tab / 跨平台导航状态统一在 NavigationCoordinator。
// 本文件不再直接 import ActivityKit / os（已无对应调用点）。
public struct AppRootView: View {

    @State private var store = EventStore.shared
    @State private var countdownStore = CountdownStore.shared
    /// 外观偏好：跟随系统 / 浅色 / 深色
    @AppStorage("Lunisolar.appearance") private var appearanceRaw: String = AppAppearance.system.rawValue
    @AppStorage("Lunisolar.liveActivity.enabled") private var liveActivityEnabled: Bool = true

    /// 场景生命周期：用于在 App 进入后台时把防抖保存立即落盘
    /// （P2：EventStore/CountdownStore 的 0.5s 防抖在后台终止时可能来不及落盘）
    @Environment(\.scenePhase) private var scenePhase
    /// 系统「减弱动态效果」（设置 → 辅助功能 → 动态效果）
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRaw) ?? .system
    }

    /// 可注入构造（§7.1 数据隔离）：默认仍是单例；UI 测试场景由宿主传临时目录的隔离库。
    /// 纯增量改动——带默认值，现有调用点（HostApp 的无参调用）不受影响。
    public init(store: EventStore = .shared, countdownStore: CountdownStore = .shared) {
        _store = State(initialValue: store)
        _countdownStore = State(initialValue: countdownStore)
        // 注册偏好默认值域：@AppStorage 的默认值不写盘，raw 读取点靠这里兜底
        // （否则"设置页显示开、逻辑判定关"，见 AppSettings）
        AppSettings.registerDefaults()
    }

    public var body: some View {
        AdaptiveRootView()
            .environment(store)
            .environment(countdownStore)
            .preferredColorScheme(appearance.colorScheme)
            .tint(Color.appTint)
            // 报告 §44：尊重「减弱动态效果」——开启时在**整棵子树**内关闭动画。
            // 为什么集中在这里而不是逐个动画点加判断：全仓 22 处动画调用散在 6 个文件里，
            // 逐处判断既容易漏、也会出现「有的降级有的没降」的不一致。
            // 代价：开启后连「月翻页」也变成瞬间切换——这正是 reduce motion 的常规解释
            // （iOS 自身也把 App 切换的缩放换成淡入）。若日后想保留淡入过渡，再细化。
            .transaction { transaction in
                if reduceMotion { transaction.disablesAnimations = true }
            }
            .task {
                AppLifecycleCoordinator.shared.bootstrap(store: store, countdownStore: countdownStore)
                await AppLifecycleCoordinator.shared.onLaunch()
            }
            .onAppear { DeepLinkRouter.handlePendingDeepLink() }
            // 深链统一入口：App 已在前台时 scenePhase 不会变化，必须在这里立即消费，
            // 否则灵动岛 / 小组件的点击会被静默丢弃到下一次前后台切换才生效。
            .onOpenURL { url in DeepLinkRouter.receive(url) }
            .onChange(of: scenePhase, initial: false) { _, newPhase in
                if newPhase == .active { DeepLinkRouter.handlePendingDeepLink() }
                AppLifecycleCoordinator.shared.onScenePhase(newPhase)
            }
            .onChange(of: store.revision, initial: false) { _, _ in
                AppLifecycleCoordinator.shared.onEventsChanged()
            }
            .onChange(of: liveActivityEnabled, initial: false) { _, enabled in
                AppLifecycleCoordinator.shared.onLiveActivityEnabledChanged(enabled)
            }
    }

}

// MARK: - 自适应根视图：iPhone NavigationStack / iPad NavigationSplitView

/// iPad (regular sizeClass) 用双栏 SplitView：左月历 + 右详情
/// iPhone (compact) 保留单栏 NavigationStack
public struct AdaptiveRootView: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass

    public init() {}

    public var body: some View {
        Group {
            if hSizeClass == .regular {
                // iPad：双栏布局
                iPadRootView()
            } else {
                // iPhone：底部 TabBar（设计稿图1：日历 / 黄历 / 我的）
                PhoneTabRootView()
            }
        }
        .onAppear {
            // 启动时根据日期自动切换主/春节图标（仅在窗口内切换，否则回主图标）
            #if canImport(UIKit)
            AlternateIconManager.shared.applyTodayIfNeeded()
            #endif
        }
    }
}

// MARK: - iPhone 底部 TabBar（设计稿图1）
// 日历：主月历；黄历：当日黄历详情；我的：设置。
struct PhoneTabRootView: View {
    @Environment(EventStore.self) private var store
    @State private var nav = NavigationCoordinator.shared

    var body: some View {
        @Bindable var nav = nav
        return TabView(selection: $nav.phoneTab) {
            NavigationStack {
                CalendarMonthView(selectedDate: $nav.selectedDate, embedsInNavigationStack: false)
            }
            .tabItem { Label(NSLocalizedString("日历", comment: ""), systemImage: "calendar") }
            .tag(NavigationCoordinator.PhoneTab.calendar)

            NavigationStack {
                DayDetailView(date: nav.selectedDate, embedsInNavigationStack: false)
            }
            .tabItem { Label(NSLocalizedString("黄历", comment: ""), systemImage: "book.and.wrench") }
            .tag(NavigationCoordinator.PhoneTab.huangli)

            AIAssistantView().environment(store)
                .tabItem { Label(NSLocalizedString("AI 助手", comment: ""), systemImage: "sparkles") }
                .tag(NavigationCoordinator.PhoneTab.ai)

            NavigationStack {
                SettingsView().environment(store)
            }
            .tabItem { Label(NSLocalizedString("我的", comment: ""), systemImage: "person.crop.circle") }
            .tag(NavigationCoordinator.PhoneTab.me)
        }
        .tint(Color.appTint)
    }
}
//
// sidebar：主导航（日历 / AI 助手 / 全部日程 / 倒数日 / 设置）
// content：随 sidebar 切换（月历 / AI 助手 / 全部日程 / 倒数日 / 设置）
// detail：上下文 Inspector（§33/§36 裁决 2026-09-26）——日历节显示选中日详情，
//         倒数日节显示选中条目详情，AI 助手/全部日程/设置节隐藏右栏
//
// 2026-09-27 批次 3 的两处结构调整（见 docs/IPAD_UI_DESIGN_2026-09-27.md）：
// - 年视图不再是侧栏节（P0-1 裁决走方案 C：移出侧栏，入口统一到
//   「跳转到日期 → 全年视图」，而 iPad 上该入口本已存在，不需新造）；
// - 新增「AI 助手」节（P0-3）：原先只能从设置页头部卡进，入口埋两层深。
struct iPadRootView: View {
    @State private var nav = NavigationCoordinator.shared
    @Environment(EventStore.self) private var store
    /// 深链聚焦的倒数日条目。nav.pendingOpenCountdownID 只负责「投递一次」，
    /// 实际高亮目标由本 State 持有——否则 nav 被清空后 focusID 立刻变回 nil，高亮一闪即灭。
    /// （与 iPhone 侧 CalendarMonthView.countdownFocusID 同构）
    @State private var countdownFocusID: UUID?
    /// 栏位显隐（绑定给 `NavigationSplitView`；用户手动拖拽侧栏时系统会把值写回这里）
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    /// 窗口宽度：用于决定窄屏（竖屏 / 分屏）要不要把侧栏收起来。
    /// 不用 sizeClass 的理由：iPad 横竖屏都是 `.regular`，区分不了。
    /// 用 `background` 里的 GeometryReader 读：不参与布局、不改变高度（与月历读容器宽度同一手法）。
    @State private var windowWidth: CGFloat = 0

    /// 侧栏行。**抽成独立的 `@ViewBuilder` 方法**：5 个 case 内联在 `ForEach` 闭包里会让
    /// 类型检查器超时（实测报 `unable to type-check this expression in reasonable time`，
    /// 加到第 5 个 case 时触发）。拆出来后恢复正常。
    @ViewBuilder
    private func sidebarRow(_ s: NavigationCoordinator.iPadSection) -> some View {
        switch s {
        case .calendar:
            Label("日历", systemImage: "calendar").tag(NavigationCoordinator.iPadSection.calendar)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(AccessibilityID.iPadSidebarCalendar)
        case .ai:
            Label("AI 助手", systemImage: "sparkles").tag(NavigationCoordinator.iPadSection.ai)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(AccessibilityID.iPadSidebarAI)
        case .agenda:
            Label("全部日程", systemImage: "list.bullet.rectangle").tag(NavigationCoordinator.iPadSection.agenda)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(AccessibilityID.iPadSidebarAgenda)
        case .countdown:
            Label("倒数日", systemImage: "hourglass").tag(NavigationCoordinator.iPadSection.countdown)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(AccessibilityID.iPadSidebarCountdown)
        case .settings:
            Label("设置", systemImage: "gearshape").tag(NavigationCoordinator.iPadSection.settings)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(AccessibilityID.iPadSidebarSettings)
        }
    }

    /// 侧栏列。
    @ViewBuilder
    private var sidebar: some View {
        @Bindable var nav = nav
        List(selection: $nav.iPadSection) {
            // P2-3 侧栏品牌区：图标 + 名称 + 版本（与设置页 Hero 卡同源的纯装饰区，不参与选择）
            Section {
                HStack(spacing: AppTheme.Spacing.md) {
                    Image("AppIcon")
                        .resizable().aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("清和日历", comment: "App名"))
                            .font(AppTheme.Font.bodyBold)
                            .foregroundStyle(Color.label)
                        Text("Version \(sidebarVersionString)")
                            .font(AppTheme.Font.caption2)
                            .foregroundStyle(Color.secondaryLabel)
                    }
                    Spacer()
                }
                .accessibilityElement(children: .combine)
                .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
            }
            ForEach([NavigationCoordinator.iPadSection.calendar, .ai, .agenda, .countdown, .settings], id: \.self) { s in
                sidebarRow(s)
            }
        }
        .navigationTitle("清和日历")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationSplitViewColumnWidth(min: splitColumnWidths.sidebar.0,
                                        ideal: splitColumnWidths.sidebar.1,
                                        max: splitColumnWidths.sidebar.2)
    }

    /// 侧栏品牌区的版本号（与 `SettingsView.appVersionString` 同口径：只显示 CFBundleShortVersionString）
    private var sidebarVersionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    /// iPad 三栏列宽，按设备尺寸分档（UI 报告 §37：11" → 220/520/320；13" → 240/640/380）。
    /// 用 `windowWidth` 判档：横屏 11"（Air 1180 / Pro 1194pt）≤ 1194，13"（Pro 12.9" 1366 / M4 1376）≥ 1290，
    /// 阈值取 1200 可无歧义分开；竖屏 / 分屏时窗口更窄，取小档后仍能容纳。
    /// 元组顺序 = (min, ideal, max)。max 略宽于报告值，给系统拖拽留余量。
    private var splitColumnWidths: (sidebar: (CGFloat, CGFloat, CGFloat),
                                    content: (CGFloat, CGFloat, CGFloat),
                                    detail: (CGFloat, CGFloat, CGFloat)) {
        if windowWidth >= 1200 {
            return ((200, 240, 260), (480, 640, 680), (300, 380, 410))
        } else {
            return ((180, 220, 240), (460, 520, 560), (280, 320, 340))
        }
    }

    /// 中栏：随侧栏节切换。
    ///
    /// 三列为什么都抽成独立视图：**整个 `NavigationSplitView` 表达式内联三个闭包 + 两个
    /// switch 时，类型检查器会超时**——实测报
    /// `the compiler is unable to type-check this expression in reasonable time`，
    /// 在给侧栏加到第 5 个 case 时触发。拆成三个属性后恢复正常编译。
    @ViewBuilder
    private var contentColumn: some View {
        switch nav.iPadSection ?? .calendar {
        case .calendar:
            CalendarMonthView(selectedDate: $nav.selectedDate, embedsInNavigationStack: false)
                .navigationSplitViewColumnWidth(min: splitColumnWidths.content.0,
                                                ideal: splitColumnWidths.content.1,
                                                max: splitColumnWidths.content.2)
        case .ai:
            // 注意：AIAssistantView 自身已含 NavigationStack（body 就是
            // `NavigationStack { List { ... } }`），这里**不要再包一层**，否则是套娃。
            // 其余节之所以要包，是因为那些视图自身不带导航栈。
            AIAssistantView().environment(store)
        case .agenda:
            NavigationStack { AllEventsView().environment(store) }
        case .countdown:
            NavigationStack {
                CountdownView(focusID: countdownFocusID,
                              selectedID: nav.iPadCountdownSelection,
                              onSelect: { nav.iPadCountdownSelection = $0 })
            }
        case .settings:
            NavigationStack { SettingsView().environment(store) }
        }
    }

    /// 右栏：§33/§36 上下文 Inspector（2026-09-26 裁决）——跟随侧栏节的上下文，
    /// 而非全节常驻日详情：
    /// - 日历：选中日的详情（`DayDetailView`，与 `nav.selectedDate` 联动）
    /// - 倒数日：选中条目的详情列（`CountdownDetailView`）
    /// - AI 助手 / 全部日程 / 设置：无合适上下文，右栏整体收起（见 `body` 里的 `columnVisibility`）
    @ViewBuilder
    private var detailColumn: some View {
        @Bindable var nav = nav
        switch nav.iPadSection ?? .calendar {
        case .calendar:
            DayDetailView(date: nav.selectedDate, embedsInNavigationStack: false)
                .navigationSplitViewColumnWidth(min: splitColumnWidths.detail.0,
                                                ideal: splitColumnWidths.detail.1,
                                                max: splitColumnWidths.detail.2)
        case .countdown:
            CountdownDetailView(selection: $nav.iPadCountdownSelection)
                .navigationSplitViewColumnWidth(min: splitColumnWidths.detail.0,
                                                ideal: splitColumnWidths.detail.1,
                                                max: splitColumnWidths.detail.2)
        case .agenda, .settings, .ai:
            EmptyView()
        }
    }

    /// 栏位显隐的唯一决策点。
    ///
    /// **实测结论（2026-09-27 批次 3，由 Flow 9 当场抓出）**：`.doubleColumn` 在**三栏**
    /// 布局里的语义是「显示内容列 + 详情列、**隐藏侧栏**」——不是本文件旧注释声称的
    /// 「隐藏右栏」。旧代码正是用 `.doubleColumn` 表示「无 Inspector 的节不出右栏」，
    /// 结果**把侧栏一起收掉了**：切到「全部日程 / 设置」后用户失去侧栏入口。真 bug，已修。
    ///
    /// 现在的规则：
    /// - 宽屏（横屏、非分屏）→ `.all`：三栏并排。无 Inspector 的节因为 `detailColumn`
    ///   返回 `EmptyView()`，右栏没有内容可占位（是否仍占一列空白，需截图确认）。
    /// - 窄屏（竖屏约 820pt / 分屏）→ `.doubleColumn`：竖屏的侧栏是**浮层且会盖住中栏**
    ///   （实测展开后中栏日期格 `isHittable == false`），自动收起来。
    ///
    /// 已知取舍：宽屏下用户手动收起侧栏后，**切换节会把三栏恢复**（本方法无条件重算）。
    /// 要保留手动态就得引入「是不是用户拖的」标记，收益不大，本批未做。
    private func applyColumnVisibility() {
        columnVisibility = (windowWidth > 0 && windowWidth < 1000) ? .doubleColumn : .all
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } content: {
            contentColumn
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
        // 读窗口宽度 → 决定栏位显隐。放在 background 里：不参与布局、不改变高度。
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        windowWidth = geo.size.width
                        applyColumnVisibility()
                    }
                    .onChange(of: geo.size.width) { _, w in
                        windowWidth = w
                        applyColumnVisibility()
                    }
            }
        )
        // 换节时也重算一次（宽屏下各节都是 .all；窄屏下换节继续自动收起侧栏）
        .onChange(of: nav.iPadSection, initial: true) { _, _ in
            applyColumnVisibility()
        }
        // P1：倒数日 / 纪念日卡片点击（qinghe://countdown/<UUID>）→ 高亮该条。
        // 用 initial: true 消费：冷启动直接点卡片进 App 时也生效（与 CalendarMonthView 一致）。
        // iPad 上 CalendarMonthView 不会消费本字段——openCountdownDetail 必然同时把侧栏切到
        // .countdown，CalendarMonthView 当次即被移出视图树，只有这里能收到。
        .onChange(of: nav.pendingOpenCountdownID, initial: true) { _, id in
            guard let id else { return }
            countdownFocusID = id
            // Inspector 选中同步：深链进来右栏直接定位到该条目详情
            nav.iPadCountdownSelection = id
            nav.pendingOpenCountdownID = nil
        }
        // 离开「倒数日」节即清高亮与 Inspector 选中，对齐 iPhone 侧 sheet 关闭后的
        // onDismiss 重置，避免下次从侧栏进入仍残留高亮
        .onChange(of: nav.iPadSection) { _, section in
            if section != .countdown {
                countdownFocusID = nil
                nav.iPadCountdownSelection = nil
            }
        }
    }
}


#endif
