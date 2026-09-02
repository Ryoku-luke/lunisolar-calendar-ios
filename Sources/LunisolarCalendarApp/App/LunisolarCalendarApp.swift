#if canImport(SwiftUI)
import SwiftUI
import Observation
// N5-1 修复：setupCloudSyncIfNeeded 中 AppLogger.sync.warning/error 两条日志走
// os.Logger，其字符串插值 init(stringInterpolation:) / appendLiteral /
// appendInterpolation(_:privacy:attributes:) 在 module `os` 内定义；本文件 SwiftUI
// 在某些 iOS SDK 组合下不自动 transitively 引入 os，Xcode 就把每条日志级联为 6 条
// "defining module 'os'"错误，共 7 条（warning 有 2 次插值次数不同）。
#if canImport(os)
import os
#endif

// MARK: - App 入口

@main
struct LunisolarCalendarApp: App {

    @State private var store = EventStore.shared
    @State private var countdownStore = CountdownStore.shared
    /// 持有同步协调器强引用（EventStore.syncCoordinator 为 weak，需要这里保活）
    @State private var syncCoordinator: EventSyncCoordinator?
    /// 外观偏好：跟随系统 / 浅色 / 深色
    @AppStorage("Lunisolar.appearance") private var appearanceRaw: String = AppAppearance.system.rawValue

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRaw) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            AdaptiveRootView()
                .environment(store)
                .environment(countdownStore)
                .preferredColorScheme(appearance.colorScheme)
                .tint(Color.appTint)
                .task {
                    // ⚠️ 启动即重排所有本地提醒：
                    // - 重新安装后 UNUserNotificationCenter 为全新空态，没有任何 pending request
                    // - iOS 系统升级/还原后也可能清掉原有 requests
                    // - 导入/合并非通知调度的冷路径（iCloud pull）需要启动时补位
                    // 放在独立的 task 里（不和 CloudKit setup 串行，避免受 entitlement 阻塞）
                    await NotificationManager.shared.rescheduleAllReminders(in: store)
                }
                .task {
                    await setupCloudSyncIfNeeded()
                }
        }
    }

    // MARK: - iCloud 同步装配（延迟到用户在设置里开启时才真正创建 CloudKit 容器）

    // 注意：绝不在这里无条件调用 CKContainer.default() ——
    // iOS Simulator 没有 CloudKit entitlement 时会直接 EXC_BREAKPOINT 崩溃。
    // RealCloudKitProvider 的创建延迟到 SettingsView 的 Toggle 打开时，
    // 那时用 do/catch 包裹 accountStatus() 探测，失败弹 toast 并保留禁用状态。

    private func setupCloudSyncIfNeeded() async {
        guard syncCoordinator == nil else { return }
        #if canImport(CloudKit)
        // 只读 UserDefaults 里的开关（纯内存操作，不触发任何 CloudKit API）
        let wasEnabled = UserDefaults.standard.bool(forKey: "Lunisolar.sync.enabled")
        if !wasEnabled {
            // 默认不装配 —— 用户从未开启过同步；SettingsView 里开关才会装配
            return
        }

        // 用户上次开启过 → 尝试装配，但如果 entitlement 缺失就静默降级
        do {
            let provider = RealCloudKitProvider()
            // 用 isAvailable 探测 entitlement/账号状态（这是第一个真正跟 CloudKit 通信的点）
            let available = await provider.isAvailable
            if !available {
                AppLogger.sync.warning("iCloud entitlement 或账号不可用，跳过同步装配")
                UserDefaults.standard.set(false, forKey: "Lunisolar.sync.enabled")
                return
            }
            let coordinator = EventSyncCoordinator(
                eventStore: store,
                provider: provider
            )
            coordinator.isEnabled = true
            store.syncCoordinator = coordinator
            syncCoordinator = coordinator
            // 后台首次同步（pull 增量 + push 本地变更）
            // N5-2 修复：原来写 `_ = try? await ...`。`try?` 把 throw 的错误吃成 nil，
            // `do { } catch { }` 的 do-block 中就再没有任何 throwing 语句，
            // iOS 18 SDK 新诊断会报 "'catch' block is unreachable because no errors are thrown in 'do' block"。
            // 这里本意是要 catch CloudKit 装配错误 → 改为 `try await`（真的抛）。
            _ = try await coordinator.syncBidirectional()
        } catch {
            AppLogger.sync.error("CloudKit 装配失败：\(error)")
            UserDefaults.standard.set(false, forKey: "Lunisolar.sync.enabled")
        }
        #endif
    }
}

// MARK: - 自适应根视图：iPhone NavigationStack / iPad NavigationSplitView

/// iPad (regular sizeClass) 用双栏 SplitView：左月历 + 右详情
/// iPhone (compact) 保留单栏 NavigationStack
struct AdaptiveRootView: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass

    var body: some View {
        if hSizeClass == .regular {
            // iPad：双栏布局
            iPadRootView()
        } else {
            // iPhone：单栏布局
            CalendarMonthView()
        }
    }
}

// MARK: - iPad 双栏根视图

struct iPadRootView: View {
    @State private var selectedDate: Date = Date()
    @Environment(EventStore.self) private var store

    var body: some View {
        NavigationSplitView {
            // 左栏：月历
            CalendarMonthView(selectedDate: $selectedDate)
        } detail: {
            // 右栏：当日详情
            DayDetailView(date: selectedDate)
        }
    }
}

// MARK: - SwiftPM 宿主入口 (兼容调用)

@available(iOS 17.0, *)
public struct CalendarAppRootView: View {
    @State private var store = EventStore.shared

    public init() {}

    public var body: some View {
        CalendarMonthView()
            .environment(store)
    }
}


#endif
