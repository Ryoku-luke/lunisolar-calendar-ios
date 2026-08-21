#if canImport(SwiftUI)
import SwiftUI
import Observation

// MARK: - App 入口

@main
struct LunisolarCalendarApp: App {

    @State private var store = EventStore.shared
    /// 持有同步协调器强引用（EventStore.syncCoordinator 为 weak，需要这里保活）
    @State private var syncCoordinator: EventSyncCoordinator?

    var body: some Scene {
        WindowGroup {
            AdaptiveRootView()
                .environment(store)
                .preferredColorScheme(.none)
                .tint(Color.systemBlue)
                .task {
                    await setupCloudSyncIfNeeded()
                }
        }
    }

    // MARK: - iCloud 同步装配

    /// 首次出现时装配 RealCloudKitProvider：
    /// - 仅 Apple 平台（有 CloudKit）
    /// - isEnabled 由 UserDefaults 控制（默认 opt-in = false，用户在设置里开启）
    /// - 开启后自动后台同步一次（pull 增量 + push 本地变更）
    private func setupCloudSyncIfNeeded() async {
        guard syncCoordinator == nil else { return }
        #if canImport(CloudKit)
        // 防止用户禁用后又开时反复创建
        let provider = RealCloudKitProvider()
        let coordinator = EventSyncCoordinator(
            eventStore: store,
            provider: provider
        )
        // 读取持久化的开关状态（默认 false = 用户首次需在设置里显式开启）
        let enabled = UserDefaults.standard.bool(forKey: "Lunisolar.sync.enabled")
        coordinator.isEnabled = enabled
        store.syncCoordinator = coordinator
        syncCoordinator = coordinator

        // 开启 → 后台首次同步
        if enabled {
            let available = await provider.isAvailable
            if available {
                _ = try? await coordinator.syncBidirectional()
            } else {
                coordinator.isEnabled = false
            }
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
