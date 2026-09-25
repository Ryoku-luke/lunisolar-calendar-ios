import Foundation

// MARK: - 「年月日」：与时区无关的日期真相
//
// 为什么需要它：全天事件原先只以**绝对瞬时**（创建地本地 00:00）持久化。
// 2026-09-06T00:00+08:00 与 2026-09-05T16:00Z 是同一个瞬时，所以同一份数据在 UTC−5 的
// 设备上会渲染成 9 月 5 日 —— 跨设备、跨时区必然错位一天（旅行改时区同理）。
//
// 解法：全天事件在**编解码时**额外携带年月日分量。编码时从写入设备的日历派生，
// 解码时按读取设备的时区物化成当地 00:00。这样月历、occurs、通知、Widget 读到的
// `startDate` 永远是「本设备上那一天的 00:00」，显示与判断都与时区无关。
//
// 约定：模型内**不保存**分量（`CalendarEvent` 没有对应的存储属性），分量只存在于
// 编码产物里。因此不存在「分量与 startDate 不同步」这种失效模式。

public struct CalendarDayKey: Codable, Hashable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// 取某个瞬时在给定时区下的日历日（默认设备时区）
    public init(_ date: Date, in calendar: Calendar = Calendar(identifier: .gregorian)) {
        self.year = calendar.component(.year, from: date)
        self.month = calendar.component(.month, from: date)
        self.day = calendar.component(.day, from: date)
    }

    /// 该日 00:00（给定时区）。日期分量不合法（如 2 月 31 日）时返回 nil。
    public func startOfDay(in calendar: Calendar = Calendar(identifier: .gregorian)) -> Date? {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        guard let date = calendar.date(from: comps) else { return nil }
        // date(from:) 不保证落在 00:00（少数时区/历史历法下会偏移），再归一一次
        return calendar.startOfDay(for: date)
    }

    /// 该日 23:59:59（给定时区）。
    ///
    /// ⚠️ 刻意用 `+ 86_399` 而不是「次日 00:00 减 1 秒」，因为这是 App 既有的全天口径
    /// （`CalendarEvent.init` 的兜底与 ICS 导入都用它），而 `CalendarEvent.occurs(on:)` 靠
    /// `startOfDay(endDate)` 判断事件落在哪几天 —— 若改成「次日 00:00 减 1 秒」，
    /// `startOfDay(endDate)` 会变成次日，单日全天事件会显示成两天。
    /// 已知代价：夏令时切换日（该日 23 小时）会多出 1 小时、落到次日 00:59:59，
    /// 这是既有口径就存在的问题，本次不改（中国无夏令时，影响面极小）。
    public func endOfDay(in calendar: Calendar = Calendar(identifier: .gregorian)) -> Date? {
        guard let start = startOfDay(in: calendar) else { return nil }
        return start.addingTimeInterval(86_399)
    }
}
