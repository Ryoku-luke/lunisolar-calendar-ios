import XCTest
import LunarCore
@testable import LunisolarCalendarApp

// MARK: - 「全部日程」分块规则
//
// 这两条规则曾导致「同一事实在两个页面结论相反」或「组头显示半年前的日期」，
// 且失败方式是**静默隐藏/错排**（列表里少了一条，没人会发现），故抽出纯函数并锁定。

final class AllEventsGroupingTests: XCTestCase {

    private let cal = QingheCalendarContext.userCalendar

    private var today: Date { cal.startOfDay(for: Date()) }

    private func day(_ offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: today)!
    }

    private func at(_ hour: Int, on date: Date) -> Date {
        date.addingTimeInterval(TimeInterval(hour * 3600))
    }

    // MARK: 已过去判定

    func testCrossDayEventStartingYesterdayIsNotPast() {
        // 昨天 23:30 → 今天 00:30：今天仍在进行，当日卡片会列出它
        let ev = CalendarEvent(title: "跨天值班",
                               startDate: cal.date(byAdding: .minute, value: -30, to: today)!,
                               endDate: cal.date(byAdding: .minute, value: 30, to: today)!)
        XCTAssertFalse(AllEventsGrouping.isPast(ev, todayStart: today))
    }

    func testEventEndedYesterdayIsPast() {
        let start = at(0, on: day(-1))
        let ev = CalendarEvent(title: "昨天的会", startDate: start, endDate: start.addingTimeInterval(3600))
        XCTAssertTrue(AllEventsGrouping.isPast(ev, todayStart: today))
    }

    func testRepeatingEventIsNeverPast() {
        let ev = CalendarEvent(title: "每周例会", startDate: day(-30), repeatRule: .weekly)
        XCTAssertFalse(AllEventsGrouping.isPast(ev, todayStart: today), "重复日程会继续发生")
    }

    func testTodayEventIsNotPast() {
        let ev = CalendarEvent(title: "今天的会", startDate: at(10, on: today))
        XCTAssertFalse(AllEventsGrouping.isPast(ev, todayStart: today))
    }

    // MARK: 分组（含「今天起」的组头夹取）

    func testUpcomingGroupingClampsOldAnchorsToToday() {
        // 重复日程的锚点在 180 天前：组头应显示「今天」，而不是半年前
        let repeating = CalendarEvent(title: "每周打卡", startDate: day(-180), repeatRule: .weekly)
        let todayEvent = CalendarEvent(title: "今天的会", startDate: at(10, on: today))
        let tomorrowEvent = CalendarEvent(title: "明天的会", startDate: at(10, on: day(1)))

        let groups = AllEventsGrouping.groups(from: [repeating, todayEvent, tomorrowEvent],
                                              clampingTo: today)

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.first?.day, today, "早于今天的开始日应归到「今天」组")
        XCTAssertEqual(groups.first?.events.count, 2)
        XCTAssertEqual(groups.last?.day, day(1))
    }

    func testGroupingWithoutClampKeepsOriginalDays() {
        let old = CalendarEvent(title: "半年前", startDate: day(-180))
        let now = CalendarEvent(title: "今天", startDate: at(10, on: today))

        let groups = AllEventsGrouping.groups(from: [old, now])

        XCTAssertEqual(groups.count, 2, "不夹取时按各自开始日分组（用于「已过去」分块）")
        XCTAssertEqual(groups.first?.day, day(-180))
    }

    func testSameDayEventsAreMergedIntoOneGroup() {
        let morning = CalendarEvent(title: "上午", startDate: at(9, on: today))
        let afternoon = CalendarEvent(title: "下午", startDate: at(15, on: today))

        let groups = AllEventsGrouping.groups(from: [morning, afternoon], clampingTo: today)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.events.count, 2)
    }

    func testEmptyInputProducesNoGroups() {
        XCTAssertTrue(AllEventsGrouping.groups(from: [], clampingTo: today).isEmpty)
    }
}
