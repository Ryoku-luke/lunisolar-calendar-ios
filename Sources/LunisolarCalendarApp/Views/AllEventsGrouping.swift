import Foundation
import LunarCore

// MARK: - 「全部日程」的分块规则（纯函数，便于单测）

/// 把事件分成「今天起」与「已过去」两块的规则。
///
/// 抽出来是因为这两条规则都出现过「同一事实在两个页面结论相反」的问题：
/// - 跨天事件（昨天 23:30 → 今天 00:30）今天仍在进行，当日卡片与黄历详情会列出它，
///   若这里判成「已过去」就会被折叠隐藏；
/// - 重复日程的 startDate 可能是半年前的锚点，直接拿它当组头会显示历史日期，
///   与「今天起优先」的承诺矛盾。
enum AllEventsGrouping {

    /// 已过去 = 一次性、开始日早于今天，**且今天已不再发生**。
    static func isPast(_ event: CalendarEvent,
                       todayStart: Date,
                       calendar: Calendar = QingheCalendarContext.userCalendar) -> Bool {
        guard event.repeatRule == .never, event.startDate < todayStart else { return false }
        return !event.occurs(on: todayStart)
    }

    /// 按天分组（入参需已按 startDate 升序，分组顺序天然有序）。
    /// - Parameter clampingTo: 早于该时刻的开始日一律归到该组（用于「今天起」分块）
    static func groups(from events: [CalendarEvent],
                       clampingTo floor: Date? = nil,
                       calendar: Calendar = QingheCalendarContext.userCalendar)
    -> [(day: Date, events: [CalendarEvent])] {
        var result: [(day: Date, events: [CalendarEvent])] = []
        for event in events {
            var day = calendar.startOfDay(for: event.startDate)
            if let floor, day < floor { day = floor }
            if let last = result.last, last.day == day {
                result[result.count - 1].events.append(event)
            } else {
                result.append((day, [event]))
            }
        }
        return result
    }
}
