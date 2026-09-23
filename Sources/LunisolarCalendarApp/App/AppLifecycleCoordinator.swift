import Foundation
import SwiftUI
#if canImport(CloudKit)
import CloudKit
#endif

// MARK: - App 生命周期协调器（P0-1）
//
// 把 AppRootView 里散落的 .task / .onChange(scenePhase) / CloudKit 装配 /
// 通知重排逻辑收口到这里。AppRootView 只负责注入环境和挂载本协调器。
// 时间胶囊逻辑已抽到 TimeCapsuleCoordinator。

@MainActor
public final class AppLifecycleCoordinator {
    public static let shared = AppLifecycleCoordinator()

    private var store: EventStore?
    private var countdownStore: CountdownStore?
    private var syncCoordinator: EventSyncCoordinator?

    private init() {}

    /// AppRootView 启动时调用
    public func bootstrap(store: EventStore, countdownStore: CountdownStore) {
        self.store = store
        self.countdownStore = countdownStore
    }

    /// 启动后异步任务
    public func onLaunch() async {
        guard let store else { return }

        // 1. 重排所有本地提醒
        await NotificationManager.shared.rescheduleAllReminders(in: store)

        // 2. 清理孤儿倒数日灵动岛 + 刷新时间胶囊
        #if canImport(ActivityKit) && canImport(WidgetKit)
        if let countdownStore {
            CountdownActivityManager.cleanupOrphans(validEventIDs: Set(countdownStore.events.map(\.id)))
        }
        TimeCapsuleCoordinator.shared.refresh()
        #endif

        // 3. 装配 CloudKit 同步（如果用户上次开启过）
        await setupCloudSyncIfNeeded()
    }

    /// scenePhase 变化
    public func onScenePhase(_ phase: ScenePhase) {
        guard let store, let countdownStore else { return }
        switch phase {
        case .active:
            Task { @MainActor in
                await NotificationManager.shared.rescheduleAllReminders(in: store)
                #if canImport(ActivityKit) && canImport(WidgetKit)
                TimeCapsuleCoordinator.shared.refresh()
                #endif
            }
        case .background, .inactive:
            store.flushPendingSave()
            countdownStore.flushPendingSave()
        @unknown default:
            break
        }
    }

    /// 事件 revision 变化 → 重新选择时间胶囊
    public func onEventsChanged() {
        #if canImport(ActivityKit) && canImport(WidgetKit)
        TimeCapsuleCoordinator.shared.refresh()
        #endif
    }

    /// 时间胶囊开关变化
    public func onLiveActivityEnabledChanged(_ enabled: Bool) {
        #if canImport(ActivityKit) && canImport(WidgetKit)
        if enabled {
            TimeCapsuleCoordinator.shared.refresh()
        } else {
            TimeCapsuleCoordinator.shared.end()
        }
        #endif
    }

    // MARK: - CloudKit

    private func setupCloudSyncIfNeeded() async {
        guard let store, syncCoordinator == nil else { return }
        #if canImport(CloudKit)
        let wasEnabled = UserDefaults.standard.bool(forKey: "Lunisolar.sync.enabled")
        guard wasEnabled else { return }
        do {
            let provider = RealCloudKitProvider()
            let available = await provider.isAvailable
            guard available else {
                UserDefaults.standard.set(false, forKey: "Lunisolar.sync.enabled")
                return
            }
            let coordinator = EventSyncCoordinator(eventStore: store, provider: provider)
            coordinator.isEnabled = true
            store.syncCoordinator = coordinator
            syncCoordinator = coordinator
            _ = try await coordinator.syncBidirectional()
        } catch {
            UserDefaults.standard.set(false, forKey: "Lunisolar.sync.enabled")
        }
        #endif
    }
}
