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

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRaw) ?? .system
    }

    public init() {}

    public var body: some View {
        AdaptiveRootView()
            .environment(store)
            .environment(countdownStore)
            .preferredColorScheme(appearance.colorScheme)
            .tint(Color.appTint)
            .task {
                AppLifecycleCoordinator.shared.bootstrap(store: store, countdownStore: countdownStore)
                await AppLifecycleCoordinator.shared.onLaunch()
            }
            .onAppear { DeepLinkRouter.handlePendingDeepLink() }
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
// sidebar：主导航（日历 / 倒数日 / 设置）
// content：随 sidebar 切换（月历 / 倒数日 / 设置）
// detail：右侧常驻当日信息列（日期/农历/宜忌/节气/生肖等，DayDetailView）
struct iPadRootView: View {
    @State private var nav = NavigationCoordinator.shared
    @Environment(EventStore.self) private var store

    var body: some View {
        @Bindable var nav = nav
        return NavigationSplitView {
            List(selection: $nav.iPadSection) {
                ForEach([NavigationCoordinator.iPadSection.calendar, .year, .countdown, .settings], id: \.self) { s in
                    switch s {
                    case .calendar:
                        Label("日历", systemImage: "calendar").tag(NavigationCoordinator.iPadSection.calendar)
                    case .year:
                        Label("年视图", systemImage: "calendar.circle").tag(NavigationCoordinator.iPadSection.year)
                    case .countdown:
                        Label("倒数日", systemImage: "hourglass").tag(NavigationCoordinator.iPadSection.countdown)
                    case .settings:
                        Label("设置", systemImage: "gearshape").tag(NavigationCoordinator.iPadSection.settings)
                    }
                }
            }
            .navigationTitle("清和日历")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        } content: {
            switch nav.iPadSection ?? .calendar {
            case .calendar:
                CalendarMonthView(selectedDate: $nav.selectedDate, embedsInNavigationStack: false)
                    .navigationSplitViewColumnWidth(min: 340, ideal: 390, max: 480)
            case .year:
                NavigationStack {
                    YearOverviewView(targetDate: $nav.selectedDate) { date in
                        nav.selectedDate = date
                        nav.iPadSection = .calendar
                    }
                }
            case .countdown:
                NavigationStack { CountdownView() }
            case .settings:
                NavigationStack { SettingsView().environment(store) }
            }
        } detail: {
            // context-aware detail：只在日历/年视图下显示 DayDetail，其他分支显示占位
            switch nav.iPadSection ?? .calendar {
            case .calendar, .year:
                DayDetailView(date: nav.selectedDate, embedsInNavigationStack: false)
                    .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 460)
            case .countdown, .settings:
                // 占位：倒数日/设置详情在 content 列已展示，右栏留空
                Text("")
                    .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 460)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}


#endif
