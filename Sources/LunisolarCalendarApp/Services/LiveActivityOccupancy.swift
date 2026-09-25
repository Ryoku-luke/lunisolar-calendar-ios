import Foundation

// MARK: - 「这个活动还在岛上吗」的共享判据
//
// 为什么必须有这一层：`Activity<T>.activities` 返回的**不只是正在展示的活动**，还包含
// 系统已经结束（`.ended`）但尚未从列表移除的残留项——系统 8 小时上限、用户在系统活动
// 列表里把它划掉、App 被上滑杀掉（系统会结束其全部活动），都会留下这种残留。
//
// 此前所有调用点都只看「id 在不在列表里」，于是残留项会被当成「还在岛上」，造成两类故障：
//   1. 仲裁器认为倒数日仍占着灵动岛 → 时间胶囊永远让位 → 表现为「灵动岛什么都没有」；
//   2. 管理器认为活动还在 → 走 update 路径去更新一个已经结束、根本不在屏幕上的活动，
//      接口还返回成功，屏幕上什么都不出现，连一条失败日志都不会有（排查时毫无线索）。
//
// 判据只认「仍在展示」的两态；未来 SDK 新增的状态一律按「不在岛上」处理——宁可重建一个
// 活动（幂等且留痕），也不要停在一个可能已经消失的活动上。

/// 活动展示状态（`ActivityKit.ActivityState` 的平台无关投影，便于在单测里覆盖判据表）
public enum LiveActivityDisplayState: Sendable, Equatable {
    case active
    case stale
    case ended
    case dismissed
    /// 未来 SDK 新增、当前版本还不认识的状态
    case unknown
}

public enum LiveActivityOccupancy {
    /// 该状态是否「仍在灵动岛/锁屏上展示」
    public static func isShowing(_ state: LiveActivityDisplayState) -> Bool {
        switch state {
        case .active, .stale: return true
        case .ended, .dismissed, .unknown: return false
        }
    }
}

#if canImport(ActivityKit) && !os(macOS)
// 同 CountdownActivity.swift：把系统框架的 Activity 实例交给 @concurrent 闭包时，
// Swift 6 严格并发需要 @preconcurrency 放宽。
@preconcurrency import ActivityKit

extension LiveActivityDisplayState {
    /// 由系统状态投影。未识别的状态（含未来 SDK 新增）归到 `.unknown`，
    /// 由 `isShowing` 按「不在岛上」处理。
    public init(_ state: ActivityState) {
        switch state {
        case .active: self = .active
        case .stale: self = .stale
        case .ended: self = .ended
        case .dismissed: self = .dismissed
        default: self = .unknown
        }
    }
}

extension LiveActivityOccupancy {
    /// 该活动当前是否仍在岛上展示（`.ended` / `.dismissed` 均不算）
    public static func isShowing<A: ActivityAttributes>(_ activity: Activity<A>) -> Bool {
        isShowing(LiveActivityDisplayState(activity.activityState))
    }
}
#endif
