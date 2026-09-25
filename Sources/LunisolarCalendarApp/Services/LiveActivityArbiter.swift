import Foundation
#if canImport(ActivityKit) && !os(macOS)
import ActivityKit
#endif

// MARK: - 灵动岛占用仲裁（docs #20 / #25：V1 同一时间只维护一个主要活动）
//
// 背景：iOS 允许多个 Live Activity 并存，长按展开后是**系统的**活动列表，用户需左右滑动切换；
// 两个活动互相挤压时切换体验很差，App 也无法自定义该系统列表。
// 因此把"谁占用灵动岛"收敛为确定性规则，从根上避免并存：
//
//     倒数日 / 纪念日倒计时（用户主动上岛或新建时自动上岛）
//         > 时间胶囊（自动候选：提醒 / 高优先级日程 / 节气）
//
// 具体规则：
// - 倒数日启动 → 结束时间胶囊（抢占）；
// - 存在倒数日活动时，时间胶囊不再自动上岛（让位，不互相挤压）；
// - 倒数日下岛 / 删除 / 自然过期 → 时间胶囊在下次 refresh 时自动接管。
//
// 占用状态直接由系统活动列表推导（不做额外记账），跨启动天然可靠、无状态不同步风险。

@MainActor
public enum LiveActivityArbiter {

    /// 灵动岛当前占用者
    public enum Occupant: Sendable, Equatable {
        case none
        case countdown        // 倒数日 / 纪念日倒计时（用户意图明确，优先级更高）
        case timeCapsule      // 时间胶囊（自动：提醒 / 高优先级日程 / 节气）
    }

    /// 从系统真实活动列表推导当前占用者。
    /// 只统计**仍在展示**的活动：已结束（`.ended`）/ 已被系统收走（`.dismissed`）的残留项
    /// 不算占用，否则一次系统收走的活动会让这里的判断永久卡在 `.countdown`，
    /// 时间胶囊再也等不到让位（表现为「灵动岛什么都没有」）。
    public static func currentOccupant() -> Occupant {
        #if canImport(ActivityKit) && !os(macOS)
        if Activity<CountdownActivityAttributes>.activities.contains(where: { LiveActivityOccupancy.isShowing($0) }) {
            return .countdown
        }
        if Activity<QingheLiveActivityAttributes>.activities.contains(where: { LiveActivityOccupancy.isShowing($0) }) {
            return .timeCapsule
        }
        return .none
        #else
        return .none
        #endif
    }

    /// 时间胶囊是否允许（自动）上岛：存在倒数日活动时让位
    public static func canTimeCapsuleTakeOver() -> Bool {
        currentOccupant() != .countdown
    }

    /// 抢占：结束除目标类型外的所有 Live Activity（倒数日上岛前调用）
    public static func endActivities(otherThan kind: Occupant) {
        #if canImport(ActivityKit) && !os(macOS)
        if kind != .countdown {
            for id in Activity<CountdownActivityAttributes>.activities.map(\.id) {
                CountdownActivityManager.end(id: id)
            }
        }
        if kind != .timeCapsule {
            QingheLiveActivityManager.endCurrent()
        }
        #endif
    }
}
