#if canImport(SwiftUI)
import SwiftUI
import Foundation

// MARK: - Live Activity 剩余时间文案（docs #26：信息少、一眼懂、时间优先）
//
// 为什么不统一用系统 `Text(date, style: .timer)`：它的格式被系统固定为
// H:MM:SS / MM:SS —— 数小时/数十天的倒计时会显示成 "4:31:10"、"717:59:59" 这类冗长读数。
// 而"自定义短格式"（如 4h 31m）只能用静态字符串，活动长时间挂在岛上时会显示陈旧值
// （iOS 不允许 App 在后台定时刷新 Live Activity）。
//
// 因此采用"既简短、又永不显示错误值"的分档策略：
//   < 1 小时        → 系统 timer（MM:SS，自动走秒，紧迫感最强）
//   1 – 24 小时     → 显示目标时刻（如 15:00）—— 绝对时间不会过期
//   ≥ 24 小时       → 显示「N天」—— 粒度与稳定性匹配（最多一天变一次）
//   已到点/已开始    → 系统 timer 正计时，表达"已开始"
//
// 「N天」的口径与 App 内倒数日列表保持完全一致：
// 取 startOfDay 之间的日历日差（CountdownEvent.daysFrom 用的是同一套算法），
// 避免"列表显示还有 1 天、岛上却显示 2天"这类不一致。
enum LiveActivityRemainingText {

    #if canImport(ActivityKit) && canImport(WidgetKit) && !os(macOS)
    @ViewBuilder
    static func view(for date: Date, now: Date = Date()) -> some View {
        let remaining = date.timeIntervalSince(now)
        if remaining <= 0 {
            Text(date, style: .timer)
                .monospacedDigit()
        } else if remaining < 3600 {
            Text(date, style: .timer)
                .monospacedDigit()
        } else if remaining < 24 * 3600 {
            Text(date.formatted(.dateTime.hour().minute()))
                .monospacedDigit()
        } else {
            Text(daysText(from: now, to: date))
        }
    }
    #endif

    /// 「N天」：日历日差（与 CountdownEvent.daysFrom 同口径），最小 1 天
    static func daysText(from now: Date, to target: Date) -> String {
        let cal = Calendar(identifier: .gregorian)
        let days = cal.dateComponents(
            [.day],
            from: cal.startOfDay(for: now),
            to: cal.startOfDay(for: target)
        ).day ?? 0
        return "\(max(days, 1))天"
    }
}
#endif
