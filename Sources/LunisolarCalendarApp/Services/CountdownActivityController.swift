import Foundation
// 与 CountdownEvent.swift / CountdownActivity.swift 保持同一编译守卫：
// 无 SwiftUI 的平台（Linux CI）上不编译倒数日相关类型。
#if canImport(SwiftUI)
#if canImport(ActivityKit) && !os(macOS)
@preconcurrency import ActivityKit
#endif

// MARK: - 倒数日灵动岛控制器（P0 遗留收口）
//
// 调用链：View（CountdownRow / CountdownEditor）→ 本控制器 → CountdownActivityManager → ActivityKit。
// 系统「实时活动」权限探测、上岛/下岛结果、保存后自动上岛策略统一收在这里；
// View 只按 ToggleOutcome 弹对应 alert，不再 import ActivityKit / 接触 Manager。
// 无 ActivityKit / WidgetKit 的编译组合（macOS / Linux）下全部方法安全降级。

@MainActor
public final class CountdownActivityController {
    public static let shared = CountdownActivityController()

    /// 行内「上岛/下岛」开关一次点击的结果（View 按此弹对应 alert / 更新图标态）
    public enum ToggleOutcome: Sendable {
        /// 成功上岛
        case started
        /// 成功下岛
        case ended
        /// 系统「实时活动」总开关被关闭（引导用户去系统设置）
        case systemDenied
        /// 启动失败（系统预算 / 权限窗口 / 设备限制等），附错误描述如实展示
        case failed(String)
    }

    private init() {}

    /// 系统「实时活动」总开关是否开启（设置 → 通知 → 清和日历）
    public func liveActivitiesAllowed() -> Bool {
        #if canImport(ActivityKit) && !os(macOS)
        return ActivityAuthorizationInfo().areActivitiesEnabled
        #else
        return false
        #endif
    }

    /// 该倒数日当前是否在岛上（含"系统已悄悄结束"的清理）
    public func isOnIsland(eventID: UUID) -> Bool {
        #if canImport(ActivityKit) && canImport(WidgetKit) && !os(macOS)
        CountdownActivityManager.activeActivityID(for: eventID) != nil
        #else
        false
        #endif
    }

    /// 行内「上岛 / 下岛」开关。语义与原 CountdownRow.toggleIsland 逐一对应。
    public func toggleIsland(for event: CountdownEvent) -> ToggleOutcome {
        #if canImport(ActivityKit) && canImport(WidgetKit) && !os(macOS)
        if CountdownActivityManager.activeActivityID(for: event.id) != nil {
            CountdownActivityManager.end(for: event.id)
            return .ended
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return .systemDenied
        }
        switch CountdownActivityManager.start(event: event) {
        case .success:
            return .started
        case .failure(let error):
            return .failed(error.localizedDescription)
        }
        #else
        return .failed("Live Activities unavailable on this platform")
        #endif
    }

    /// 结束全部倒数日活动（设置页关闭「时间胶囊」开关时调用，避免残留倒计时）。
    public func endAllActivities() {
        #if canImport(ActivityKit) && canImport(WidgetKit) && !os(macOS)
        for id in Activity<CountdownActivityAttributes>.activities.map(\.id) {
            CountdownActivityManager.end(id: id)
        }
        #endif
    }

    /// 编辑器保存后的自动上岛策略（不打扰、不弹窗）：
    /// - 新建倒数日 → 自动上岛（核心诉求）
    /// - 编辑且当前已在岛上 → 同步新内容（start 内部幂等：内容未变不重启）
    /// - 编辑但已手动下岛 → 保持下岛，尊重用户主动选择
    public func autoStartAfterSave(isNew: Bool, event: CountdownEvent) {
        #if canImport(ActivityKit) && canImport(WidgetKit) && !os(macOS)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if isNew || CountdownActivityManager.activeActivityID(for: event.id) != nil {
            _ = CountdownActivityManager.start(event: event)
        }
        #endif
    }
}
#endif
