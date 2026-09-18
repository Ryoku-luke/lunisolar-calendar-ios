import XCTest
@testable import LunisolarCalendarApp

/// 回归测试：倒数日 / 纪念日模型（CountdownEvent）。
/// 纯模型逻辑，Linux / iOS 均可运行。
final class CountdownEventTests: XCTestCase {

    private let gregorian = Calendar(identifier: .gregorian)

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d
        c.hour = 0; c.minute = 0; c.second = 0
        // 不设 timeZone：与被测代码同为当前时区（CI UTC 容器与本地均可复现）
        return gregorian.date(from: c)!
    }

    // MARK: - nextAnniversary

    /// 倒数日（非纪念日）不应返回周年日期。
    func testCountdownKindNextAnniversaryIsNil() {
        let ev = CountdownEvent(title: "考试", date: date(2026, 12, 20), kind: .countdown)
        XCTAssertNil(ev.nextAnniversary(from: date(2026, 9, 14)))
    }

    /// 今年的纪念日还没到 → 返回今年（而不是明年）。
    func testAnniversaryFutureThisYearReturnsThisYear() {
        let ev = CountdownEvent(title: "生日", date: date(2000, 12, 25), kind: .anniversary)
        XCTAssertEqual(ev.nextAnniversary(from: date(2026, 9, 14)), date(2026, 12, 25))
    }

    /// 今年的纪念日已过 → 返回明年同一天（而非 nil 或今年已过的日期）。
    func testAnniversaryPastOccurrenceRollsToNextYear() {
        let ev = CountdownEvent(title: "生日", date: date(2000, 3, 1), kind: .anniversary)
        XCTAssertEqual(ev.nextAnniversary(from: date(2026, 9, 14)), date(2027, 3, 1))
    }

    /// 2/29 生日在非闰年落到 2/28（避免闰日生日跳过 2-3 年）。
    func testLeapDayBirthdayFallsBackToFeb28InNonLeapYear() {
        let ev = CountdownEvent(title: "闰日生日", date: date(2000, 2, 29), kind: .anniversary)
        XCTAssertEqual(ev.nextAnniversary(from: date(2026, 9, 14)), date(2027, 2, 28),
                       "2027 非闰年，2/29 生日应落到 2/28")
    }

    /// 2/29 生日在闰年保持 2/29。
    func testLeapDayBirthdayStaysFeb29InLeapYear() {
        let ev = CountdownEvent(title: "闰日生日", date: date(2000, 2, 29), kind: .anniversary)
        XCTAssertEqual(ev.nextAnniversary(from: date(2027, 9, 14)), date(2028, 2, 29),
                       "2028 闰年，2/29 生日应保持 2/29")
    }

    // MARK: - daysFrom / displayText

    func testDaysFromTodayIsZero() {
        let ev = CountdownEvent(title: "今天", date: date(2026, 9, 14), kind: .countdown)
        XCTAssertEqual(ev.daysFrom(today: date(2026, 9, 14)), 0)
        XCTAssertEqual(ev.displayText(today: date(2026, 9, 14)), "就是今天")
    }

    func testDisplayTextFutureAndPast() {
        let future = CountdownEvent(title: "考试", date: date(2026, 10, 1), kind: .countdown)
        XCTAssertEqual(future.daysFrom(today: date(2026, 9, 14)), 17)
        XCTAssertEqual(future.displayText(today: date(2026, 9, 14)), "还有 17 天")

        let past = CountdownEvent(title: "已过", date: date(2026, 9, 1), kind: .countdown)
        XCTAssertEqual(past.daysFrom(today: date(2026, 9, 14)), -13)
        XCTAssertEqual(past.displayText(today: date(2026, 9, 14)), "已过 13 天")
    }
}
