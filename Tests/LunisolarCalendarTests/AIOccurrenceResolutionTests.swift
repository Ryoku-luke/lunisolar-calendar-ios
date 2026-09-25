import XCTest
import LunarCore
@testable import LunisolarCalendarApp

// MARK: - 「用户指的那一次出现」解析
//
// 重复日程在数据层只有一条记录，`startDate` 是序列锚点。删除/修改确认区若直接展示
// 锚点日期（可能是几个月前），用户会以为要动的是另一条日程、不敢确认；
// 若回执只说「已删除该日程」，用户会以为只删了「明天那次」，实际整条序列都没了。
// 这里锁定"命中那一次"的日期合成规则。

final class AIOccurrenceResolutionTests: XCTestCase {

    private let cal = QingheCalendarContext.userCalendar

    private var today: Date { cal.startOfDay(for: Date()) }

    private func day(_ offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: today)!
    }

    private func at(_ hour: Int, _ minute: Int, on date: Date) -> Date {
        let dc = DateComponents(hour: hour, minute: minute)
        return cal.date(bySettingHour: dc.hour!, minute: dc.minute!, second: 0, of: date)!
    }

    func testNonRepeatingEventKeepsItsOwnStart() {
        let ev = CalendarEvent(title: "一次性的会", startDate: at(15, 0, on: day(-3)))
        // 非重复日程：无论 criteria.day 是什么，都返回它自己的开始时刻
        XCTAssertEqual(AIAssistantService.occurrenceStart(of: ev, on: day(1)), ev.startDate)
    }

    func testRepeatingEventUsesCriteriaDayWithOriginalTimeOfDay() {
        // 每周三 15:00 的例会，锚点在 90 天前
        let anchor = at(15, 0, on: day(-90))
        let ev = CalendarEvent(title: "每周例会", startDate: anchor, repeatRule: .weekly)

        let occurrence = AIAssistantService.occurrenceStart(of: ev, on: day(1))

        XCTAssertEqual(cal.startOfDay(for: occurrence), day(1), "应落在用户所说的那一天")
        XCTAssertEqual(cal.component(.hour, from: occurrence), 15, "保留原本的时")
        XCTAssertEqual(cal.component(.minute, from: occurrence), 0, "保留原本的分")
    }

    func testRepeatingEventKeepsMinutesToo() {
        let anchor = at(9, 45, on: day(-200))
        let ev = CalendarEvent(title: "每月复盘", startDate: anchor, repeatRule: .monthly)

        let occurrence = AIAssistantService.occurrenceStart(of: ev, on: day(5))

        XCTAssertEqual(cal.startOfDay(for: occurrence), day(5))
        XCTAssertEqual(cal.component(.hour, from: occurrence), 9)
        XCTAssertEqual(cal.component(.minute, from: occurrence), 45)
    }

    /// 农历每年（生日类）同样适用：锚点是过去的生日，确认区应展示用户说的那天
    func testLunarAnnuallyRepeatingEventAlsoUsesCriteriaDay() {
        let anchor = at(8, 0, on: day(-400))
        let ev = CalendarEvent(title: "妈妈生日", startDate: anchor, repeatRule: .lunarAnnually)

        let occurrence = AIAssistantService.occurrenceStart(of: ev, on: day(30))

        XCTAssertEqual(cal.startOfDay(for: occurrence), day(30))
        XCTAssertEqual(cal.component(.hour, from: occurrence), 8)
    }
}
