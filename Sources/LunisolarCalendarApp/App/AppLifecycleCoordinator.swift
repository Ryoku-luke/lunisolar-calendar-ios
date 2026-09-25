import Foundation
import SwiftUI
#if canImport(CloudKit)
import CloudKit
#endif
// N5-1 教训：AppLogger.sync.* 的字符串插值定义在 module `os` 内，
// 是否可见与所在文件 import 了什么都无必然关系；显式引入避免 SDK 组合差异级联报错。
#if canImport(os)
import os
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

    /// 本次「前台周期」是否已做过全量通知重排。
    ///
    /// 冷启动时 `.task(onLaunch)` 与 `scenePhase → .active` 会各触发一次
    /// （cancelAll + 遍历全部 reminder 重挂 → badge 闪两次、系统调用翻倍）。
    /// 回到后台时复位，保证下一次回前台仍会重排。
    private var didRescheduleThisForeground = false

    private init() {}

    /// AppRootView 启动时调用
    public func bootstrap(store: EventStore, countdownStore: CountdownStore) {
        self.store = store
        self.countdownStore = countdownStore
    }

    /// 全量重排本地提醒：同一「前台周期」内只做一次（冷启动的两条触发路径共用）
    private func rescheduleRemindersOnce(in store: EventStore) async {
        guard !didRescheduleThisForeground else { return }
        didRescheduleThisForeground = true   // 先置位：并发的第二路调用直接跳过
        await NotificationManager.shared.rescheduleAllReminders(in: store)
    }

    /// 启动后异步任务
    public func onLaunch() async {
        guard let store else { return }

        // 1. 重排所有本地提醒（与 scenePhase→.active 去重，避免冷启动排两遍）
        await rescheduleRemindersOnce(in: store)

        // 2. 清理孤儿倒数日灵动岛 + 刷新时间胶囊
        #if canImport(ActivityKit) && canImport(WidgetKit) && !os(macOS)
        if let countdownStore {
            CountdownActivityManager.cleanupOrphans(validEventIDs: Set(countdownStore.events.map(\.id)))
        }
        TimeCapsuleCoordinator.shared.refresh()
        #endif

        // 3. 小组件快照窗口滑动到「今天」。
        //    跨天后窗口首日还是昨天，小组件拿不到今天的桶 → 「今日待办」显示 0/0
        //    与「今日还没安排」，与真实数据矛盾。快照原本只在数据变更时写，
        //    所以「打开 App」这条路径必须补上。
        store.refreshWidgetSnapshotIfDayChanged()

        // 4. 一次性清理旧版 ICS 导入遗留的备注污染（幂等：无改动时不写盘）
        let cleanedNotes = EventService.shared.cleanUpLegacyImportNotes()
        if cleanedNotes > 0 {
            AppLogger.app.info("清理了 \(cleanedNotes) 条旧版导入遗留的备注")
        }

        // 5. 装配 CloudKit 同步（如果用户上次开启过）
        await setupCloudSyncIfNeeded()
    }

    /// scenePhase 变化
    public func onScenePhase(_ phase: ScenePhase) {
        guard let store, let countdownStore else { return }
        switch phase {
        case .active:
            Task { @MainActor in
                await rescheduleRemindersOnce(in: store)
                store.refreshWidgetSnapshotIfDayChanged()
                #if canImport(ActivityKit) && canImport(WidgetKit) && !os(macOS)
                TimeCapsuleCoordinator.shared.refresh()
                #endif
            }
        case .background, .inactive:
            // 进入后台：复位"本前台周期已重排"标记，回到前台时再排一次
            didRescheduleThisForeground = false
            store.flushPendingSave()
            countdownStore.flushPendingSave()
        @unknown default:
            break
        }
    }

    /// 事件 revision 变化 → 重新选择时间胶囊
    public func onEventsChanged() {
        #if canImport(ActivityKit) && canImport(WidgetKit) && !os(macOS)
        TimeCapsuleCoordinator.shared.refresh()
        #endif
    }

    /// 时间胶囊开关变化
    public func onLiveActivityEnabledChanged(_ enabled: Bool) {
        #if canImport(ActivityKit) && canImport(WidgetKit) && !os(macOS)
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
        // entitlement 缺失（免费个人团队等）：连 provider 都不构造，直接跳过装配。
        // 不清除开关标记——这是构建属性而非账号问题，换成付费构建后应自动续用。
        guard RealCloudKitProvider.hasCloudKitEntitlements() else {
            AppLogger.sync.warning("当前构建签名不含 iCloud 容器 entitlement，跳过同步装配")
            return
        }
        let wasEnabled = UserDefaults.standard.bool(forKey: "Lunisolar.sync.enabled")
        guard wasEnabled else { return }
        do {
            let provider = RealCloudKitProvider()
            let available = await provider.isAvailable
            guard available else {
                AppLogger.sync.warning("iCloud entitlement 或账号不可用，跳过同步装配")
                UserDefaults.standard.set(false, forKey: "Lunisolar.sync.enabled")
                return
            }
            let coordinator = EventSyncCoordinator(eventStore: store, provider: provider)
            coordinator.isEnabled = true
            store.syncCoordinator = coordinator
            syncCoordinator = coordinator
            _ = try await coordinator.syncBidirectional()
        } catch {
            AppLogger.sync.error("CloudKit 装配失败：\(error)")
            UserDefaults.standard.set(false, forKey: "Lunisolar.sync.enabled")
        }
        #endif
    }

    // MARK: - iCloud 同步控制（P0 遗留收口）
    //
    // 设置页只发意图（首次开启 / 开关切换 / 立即同步），CloudKit Provider 装配、
    // coordinator 生命周期、UserDefaults 开关标记全部收在本类。
    // View 不再 import CloudKit / 构造 RealCloudKitProvider。
    // 设置页仍只读 store.syncCoordinator 的 status/lastResult 做状态展示（只读，允许）。

    /// 首次开启 iCloud 同步的结局（设置页按此映射不同 toast）。
    public enum CloudSyncEnableResult: Sendable {
        /// 装配 + 首次双向同步完成
        case success
        /// 当前构建签名不含 iCloud/CloudKit 权限（如免费个人团队账号）：
        /// 这是构建/账号类型限制，不是代码缺陷，也不代表设备未登录 iCloud
        case unsupportedBuild
        /// 有 iCloud 权限，但账号未登录 / 状态异常（受限、暂时不可用等）
        case accountUnavailable
        /// 装配成功但首次同步失败（开关保持开启，与旧行为一致，可后续重试）
        case syncFailed
    }

    /// 首次开启：装配 provider/coordinator、写开关标记、首次双向同步 + 通知重排。
    @discardableResult
    public func enableCloudSync() async -> CloudSyncEnableResult {
        #if canImport(CloudKit)
        guard let store else { return .accountUnavailable }
        // 先判构建能力，再判账号 —— 两者提示文案不同，避免误导用户去登录 iCloud
        guard RealCloudKitProvider.hasCloudKitEntitlements() else {
            AppLogger.sync.warning("当前构建签名不含 iCloud 容器 entitlement，CloudKit 同步不可用")
            return .unsupportedBuild
        }
        let provider = RealCloudKitProvider()
        let available = await provider.isAvailable
        guard available else {
            AppLogger.sync.warning("iCloud 账号不可用：未登录或状态异常")
            return .accountUnavailable
        }
        let coordinator = EventSyncCoordinator(eventStore: store, provider: provider)
        coordinator.isEnabled = true
        store.syncCoordinator = coordinator
        syncCoordinator = coordinator
        UserDefaults.standard.set(true, forKey: "Lunisolar.sync.enabled")
        do {
            _ = try await coordinator.syncBidirectional()
        } catch {
            AppLogger.sync.error("首次开启 iCloud 同步失败：\(error)")
            return .syncFailed
        }
        // 首次双向同步后：远端可能有新 reminder，需要排本地通知
        await NotificationManager.shared.rescheduleAllReminders(in: store)
        return .success
        #else
        // 未编译 CloudKit 的平台：能力缺失等价于「当前构建不含 iCloud 权限」。
        // 旧代码返回的 `.unavailable` 在 CloudSyncEnableResult 里**根本不存在**
        // （枚举只有 success / unsupportedBuild / accountUnavailable / syncFailed），
        // 属死分支 —— 假想平台一接就编译失败。
        return .unsupportedBuild
        #endif
    }

    /// 设置页「启用 iCloud 同步」开关切换（已有 coordinator 后的 enable/disable）。
    public func setCloudSyncEnabled(_ enabled: Bool) {
        #if canImport(CloudKit)
        guard let co = syncCoordinator ?? store?.syncCoordinator else { return }
        co.isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "Lunisolar.sync.enabled")
        if enabled {
            Task { @MainActor in
                do {
                    _ = try await co.syncBidirectional()
                    if let store {
                        await NotificationManager.shared.rescheduleAllReminders(in: store)
                    }
                } catch {
                    AppLogger.sync.warning("开启同步后首次同步失败：\(error)")
                }
            }
        }
        #endif
    }

    /// 设置页「立即同步」。返回 nil 表示成功；失败返回错误对象（调用方格式化 toast）。
    @discardableResult
    public func syncNow() async -> Error? {
        #if canImport(CloudKit)
        guard let co = syncCoordinator ?? store?.syncCoordinator else { return nil }
        do {
            _ = try await co.syncBidirectional()
            if let store {
                await NotificationManager.shared.rescheduleAllReminders(in: store)
            }
            return nil
        } catch {
            AppLogger.sync.error("立即同步失败：\(error)")
            return error
        }
        #else
        return nil
        #endif
    }
}
