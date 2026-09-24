import Foundation
#if canImport(ActivityKit) && !os(macOS)
import ActivityKit
#endif

// MARK: - 时间胶囊协调器（P0-5）
//
// 把"选岛候选 → 组装 display → 调用 QingheLiveActivityManager.sync"这条链路
// 从 AppLifecycleCoordinator 抽出来，AppLifecycleCoordinator 只负责调 start/refresh。
// View 永远不直接访问本类。

@MainActor
public final class TimeCapsuleCoordinator {
    public static let shared = TimeCapsuleCoordinator()

    private init() {}

    /// 根据当前状态刷新时间胶囊（启动 / 回到前台 / 事件变更 / 开关变化时调用）。
    public func refresh() {
        #if canImport(ActivityKit) && !os(macOS) && canImport(WidgetKit)
        let now = Date()
        let enabled = UserDefaults.standard.bool(forKey: "Lunisolar.liveActivity.enabled")
        guard enabled,
              ActivityAuthorizationInfo().areActivitiesEnabled,
              let candidate = EventService.shared.timeCapsuleCandidate(now: now) else {
            QingheLiveActivityManager.sync(target: nil)
            return
        }
        let title: String
        if candidate.type == .solarTerm {
            title = SolarTermProvider.termOn(candidate.startDate)
                ?? SolarTermProvider.nextTerm(from: now)?.name
                ?? "节气"
        } else {
            guard let event = EventService.shared.store.events.first(where: { $0.id == candidate.eventID }) else {
                QingheLiveActivityManager.sync(target: nil)
                return
            }
            title = event.title
        }
        let display = QingheTimeCapsuleDisplay(
            eventID: candidate.eventID,
            type: candidate.type,
            phase: candidate.startDate <= now ? .live : .upcoming,
            title: title,
            icon: QingheLiveActivityManager.icon(for: candidate.type),
            startDate: candidate.startDate,
            endDate: candidate.endDate,
            countdownTarget: candidate.type == .solarTerm ? candidate.startDate : nil,
            isImportant: candidate.priority >= .important
        )
        QingheLiveActivityManager.sync(target: display)
        #endif
    }

    /// 结束当前时间胶囊（用户关闭开关 / 无候选）。
    public func end() {
        #if canImport(ActivityKit) && !os(macOS) && canImport(WidgetKit)
        QingheLiveActivityManager.endCurrent()
        #endif
    }
}
