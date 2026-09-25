import XCTest
import LunarCore
@testable import LunisolarCalendarApp

// MARK: - ICS 导入健壮性（两条 P1 回归）
//
// 1) 子块泄漏：导入循环只认 `END:VEVENT`，于是 `BEGIN:VALARM … END:VALARM` 里的键值
//    被当成事件属性解析。Apple / Google 导出的事件都带
//    `BEGIN:VALARM / ACTION:DISPLAY / DESCRIPTION:提醒`，且该行位于事件自身
//    DESCRIPTION **之后** → 导入后备注被替换成「提醒」，原备注永久丢失；
//    若子块里再有 UID，还会覆盖事件 UID、让重复导入去重失效。
//
// 2) 格式化器未固定 locale/calendar：系统区域用佛历 / 和历时，`yyyy` 是该历法年号，
//    `DTSTART;VALUE=DATE:20260906` 会被解析成公历 1483 年。

final class ICSImportRobustnessTests: XCTestCase {

    private func ics(_ body: String) -> String {
        """
        BEGIN:VCALENDAR\r
        VERSION:2.0\r
        \(body)\r
        END:VCALENDAR\r
        """
    }

    // MARK: 子块不参与解析

    func testValarmDescriptionDoesNotOverwriteEventNotes() throws {
        let content = ics("""
        BEGIN:VEVENT\r
        UID:abc-123\r
        SUMMARY:季度评审\r
        DTSTART:20260925T100000Z\r
        DTEND:20260925T110000Z\r
        DESCRIPTION:记得带上季度报表\r
        BEGIN:VALARM\r
        ACTION:DISPLAY\r
        DESCRIPTION:提醒\r
        TRIGGER:-PT10M\r
        END:VALARM\r
        END:VEVENT
        """)

        let events = DataPortability.importICS(content)
        let ev = try XCTUnwrap(events.first)
        XCTAssertEqual(ev.title, "季度评审")
        let notes = try XCTUnwrap(ev.notes)
        XCTAssertTrue(notes.contains("记得带上季度报表"), "事件自己的备注必须保留")
        XCTAssertFalse(notes.contains("\n提醒"), "VALARM 的 DESCRIPTION 不得混进备注：\(notes)")
    }

    /// 同一事件带不带 VALARM 必须算出同一个伪 UUID（否则重复导入会产生副本）
    func testValarmDoesNotChangePseudoIdentity() throws {
        let plain = ics("""
        BEGIN:VEVENT\r
        UID:abc-123\r
        SUMMARY:季度评审\r
        DTSTART:20260925T100000Z\r
        DTEND:20260925T110000Z\r
        END:VEVENT
        """)
        let withAlarm = ics("""
        BEGIN:VEVENT\r
        UID:abc-123\r
        SUMMARY:季度评审\r
        DTSTART:20260925T100000Z\r
        DTEND:20260925T110000Z\r
        BEGIN:VALARM\r
        ACTION:DISPLAY\r
        DESCRIPTION:提醒\r
        UID:alarm-uid-should-be-ignored\r
        TRIGGER:-PT10M\r
        END:VALARM\r
        END:VEVENT
        """)

        let a = try XCTUnwrap(DataPortability.importICS(plain).first)
        let b = try XCTUnwrap(DataPortability.importICS(withAlarm).first)
        XCTAssertEqual(a.id, b.id, "带 VALARM 不得改变事件身份（重复导入应被去重）")
    }

    /// 缺 END:VALARM 的畸形输入：跳过逻辑不得吃掉事件的 END:VEVENT，
    /// 否则后面事件的内容会被并进当前事件
    func testMalformedUnclosedAlarmDoesNotSwallowNextEvent() throws {
        let content = ics("""
        BEGIN:VEVENT\r
        UID:first\r
        SUMMARY:第一个\r
        DTSTART:20260925T100000Z\r
        DTEND:20260925T110000Z\r
        BEGIN:VALARM\r
        ACTION:DISPLAY\r
        DESCRIPTION:提醒\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        UID:second\r
        SUMMARY:第二个\r
        DTSTART:20260926T100000Z\r
        DTEND:20260926T110000Z\r
        END:VEVENT
        """)

        let events = DataPortability.importICS(content)
        XCTAssertEqual(events.count, 2, "两个事件都应在，不能被吞并")
        XCTAssertEqual(events.map(\.title), ["第一个", "第二个"])
    }

    /// 正常事件不能被跳过逻辑误伤（没有子块时行为不变）
    func testPlainEventStillParsesAllFields() throws {
        let content = ics("""
        BEGIN:VEVENT\r
        UID:plain-1\r
        SUMMARY:晨会\r
        DTSTART:20260925T100000Z\r
        DTEND:20260925T110000Z\r
        LOCATION:会议室\r
        DESCRIPTION:带上笔记本\r
        PRIORITY:1\r
        STATUS:COMPLETED\r
        END:VEVENT
        """)

        let ev = try XCTUnwrap(DataPortability.importICS(content).first)
        XCTAssertEqual(ev.title, "晨会")
        XCTAssertEqual(ev.location, "会议室")
        XCTAssertTrue(ev.notes?.contains("带上笔记本") ?? false)
        XCTAssertEqual(ev.priority, .urgent)
        XCTAssertTrue(ev.isCompleted)
    }

    // MARK: 格式化器口径固定（结构性守卫）

    /// 只设 dateFormat 不足以摆脱设备日历；这里钉住 locale 与 calendar 的显式固定。
    /// （真机上的佛历/和历场景无法在命令行测试里复现，故用结构性断言守回归。）
    func testFormattersArePinnedToPosixGregorian() {
        let utc = DataPortability.formatter("yyyyMMdd'T'HHmmss'Z'", timeZone: QingheCalendarContext.utcTimeZone)
        XCTAssertEqual(utc.locale.identifier, "en_US_POSIX")
        XCTAssertEqual(utc.calendar.identifier, .gregorian)

        let local = DataPortability.formatter("yyyyMMdd", timeZone: .current)
        XCTAssertEqual(local.locale.identifier, "en_US_POSIX")
        XCTAssertEqual(local.calendar.identifier, .gregorian)
    }

    /// 解析出的绝对时刻必须与 UTC 字面量一致（当前设备历法下的正确性）
    func testUTCTimestampParsesToExactInstant() throws {
        let content = ics("""
        BEGIN:VEVENT\r
        UID:utc-1\r
        SUMMARY:UTC 事件\r
        DTSTART:20260925T020000Z\r
        DTEND:20260925T030000Z\r
        END:VEVENT
        """)

        let ev = try XCTUnwrap(DataPortability.importICS(content).first)
        var dc = DateComponents()
        dc.year = 2026; dc.month = 9; dc.day = 25; dc.hour = 2; dc.minute = 0
        var gregorianUTC = Calendar(identifier: .gregorian)
        gregorianUTC.timeZone = QingheCalendarContext.utcTimeZone
        XCTAssertEqual(ev.startDate, try XCTUnwrap(gregorianUTC.date(from: dc)))
    }
}
