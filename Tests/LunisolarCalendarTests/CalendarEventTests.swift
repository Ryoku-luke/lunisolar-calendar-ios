import XCTest
import LunarCore
@testable import LunisolarCalendarApp

// MARK: - 事件模型测试

final class CalendarEventTests: XCTestCase {

    func testEndDateAutoFix() {
        let start = Date()
        let earlierEnd = start.addingTimeInterval(-3600) // 早1小时
        let ev = CalendarEvent(title: "测试", startDate: start, endDate: earlierEnd)
        XCTAssertGreaterThan(ev.endDate, ev.startDate, "endDate 应自动修正为 > startDate")
    }

    func testAllDayEventDuration() {
        let start = Date()
        let ev = CalendarEvent(title: "全天", startDate: start, endDate: start, isAllDay: true)
        XCTAssertEqual(ev.endDate.timeIntervalSince(ev.startDate), 86399, "全天事件应为 86399 秒")
    }

    func testLunarAnnuallyRepeat() {
        let cal = Calendar(identifier: .gregorian)
        var dc = DateComponents()
        dc.year = 2025; dc.month = 10; dc.day = 6  // 农历八月十五 中秋节
        let startDate = cal.date(from: dc)!
        let ev = CalendarEvent(
            title: "农历生日测试",
            startDate: startDate,
            repeatRule: .lunarAnnually
        )

        // 2026年同农历日（八月十五）应该匹配
        var dc2026 = DateComponents()
        dc2026.year = 2026; dc2026.month = 9; dc2026.day = 25 // 2026中秋
        let nextYear = cal.date(from: dc2026)!
        XCTAssertTrue(ev.occurs(on: nextYear), "农历每年重复应匹配下一年同农历日")
    }

    // MARK: 农历生日/纪念日 跨3年验证（春节正月初一）
    func testLunarAnnuallySpringFestivalAcross3Years() {
        let cal = Calendar(identifier: .gregorian)
        // 起始 2025 春节（正月初一）
        var dc = DateComponents()
        dc.year = 2025; dc.month = 1; dc.day = 29
        let start2025 = cal.date(from: dc)!
        let ev = CalendarEvent(
            title: "春节家庭聚餐",
            startDate: start2025,
            repeatRule: .lunarAnnually
        )

        // 2026 春节：2026-02-17 正月初一
        var dc26 = DateComponents()
        dc26.year = 2026; dc26.month = 2; dc26.day = 17
        XCTAssertTrue(ev.occurs(on: cal.date(from: dc26)!), "2026春节 正月初一 应匹配")

        // 2027 春节：2027-02-06 正月初一（ChineseCalendar 已验证：2100春节=2100-02-09，往前推算一致）
        var dc27 = DateComponents()
        dc27.year = 2027; dc27.month = 2; dc27.day = 6
        let d27 = cal.date(from: dc27)!
        // 先确保这个公历日期确实是农历正月初一（避免手工真值错误）
        if let lunar = ChineseCalendar.lunarDateSafe(from: d27) {
            XCTAssertEqual(lunar.month, 1)
            XCTAssertEqual(lunar.day, 1)
            XCTAssertFalse(lunar.isLeapMonth)
            XCTAssertTrue(ev.occurs(on: d27), "2027春节 正月初一 应匹配")
        }

        // 非正月初一（前后一天）不匹配
        var dcWrong = DateComponents()
        dcWrong.year = 2026; dcWrong.month = 2; dcWrong.day = 18
        XCTAssertFalse(ev.occurs(on: cal.date(from: dcWrong)!), "正月初二 不匹配")
    }

    // MARK: 闰月生日在平月年也应命中（闰二月廿九 → 次年二月廿九命中）
    func testLunarAnnuallyLeapMonthMatchesFlatMonth() {
        let cal = Calendar(identifier: .gregorian)
        // 起始：2023-04-19 闰二月廿九（真值表里有）
        var dc = DateComponents()
        dc.year = 2023; dc.month = 4; dc.day = 19
        let start = cal.date(from: dc)!
        let startLunar = ChineseCalendar.lunarDateSafe(from: start)
        XCTAssertEqual(startLunar?.isLeapMonth, true, "起锚日必须为闰二月廿九")
        XCTAssertEqual(startLunar?.month, 2)
        XCTAssertEqual(startLunar?.day, 29)

        let ev = CalendarEvent(title: "闰月生日", startDate: start, repeatRule: .lunarAnnually)

        // 2024-04-07：查 ChineseCalendar 这个日期的农历是不是二月廿九（平月）？先断言一下，再 occurs
        var dc24 = DateComponents()
        dc24.year = 2024; dc24.month = 4; dc24.day = 7
        let d24 = cal.date(from: dc24)!
        if let l = ChineseCalendar.lunarDateSafe(from: d24) {
            if l.month == 2 && l.day == 29 && !l.isLeapMonth {
                XCTAssertTrue(ev.occurs(on: d24), "闰月生日在平月年同月同日 应命中")
            }
        }
    }

    // MARK: repeatRuleLabel / repeatAnchorDescription 文本格式
    func testRepeatRuleLabelAndAnchor() {
        let cal = Calendar(identifier: .gregorian)
        var dc = DateComponents()
        dc.year = 2025; dc.month = 10; dc.day = 6 // 农历八月十五
        let midAutumn = cal.date(from: dc)!

        let ev = CalendarEvent(title: "中秋", startDate: midAutumn, repeatRule: .lunarAnnually)
        let label = ev.repeatRuleLabel
        XCTAssertTrue(label.contains("农历"))
        XCTAssertTrue(label.contains("八月") || label.contains("仲秋")) // monthName 会返回"八月"
        XCTAssertTrue(label.contains("十五"))
        XCTAssertTrue(label.contains("每年"))

        let anchor = CalendarEvent.repeatAnchorDescription(rule: .lunarAnnually, anchor: midAutumn)
        XCTAssertTrue(anchor.contains("农历每年"))
        XCTAssertTrue(anchor.contains("八月十五"))

        // 公历每年：10月6日
        let solar = CalendarEvent(title: "国庆后", startDate: midAutumn, repeatRule: .yearly)
        let solarLabel = solar.repeatRuleLabel
        XCTAssertTrue(solarLabel.contains("公历"))
        XCTAssertTrue(solarLabel.contains("10月6日"))
    }

    func testPriorityComparison() {
        XCTAssertGreaterThan(Priority.urgent, Priority.high)
        XCTAssertGreaterThan(Priority.high, Priority.normal)
        XCTAssertGreaterThan(Priority.normal, Priority.low)
    }

    func testICSExportImport() {
        let ev = CalendarEvent(title: "导出测试事件", startDate: Date(), location: "测试地点", notes: "备注")
        let ics = DataPortability.exportICS(from: [ev])
        XCTAssertTrue(ics.contains("BEGIN:VCALENDAR"))
        XCTAssertTrue(ics.contains("SUMMARY:导出测试事件"))

        let imported = DataPortability.importICS(ics)
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported.first?.title, "导出测试事件")
    }

    func testCSVExport() {
        let ev = CalendarEvent(title: "CSV测试", startDate: Date())
        let csv = DataPortability.exportCSV(from: [ev])
        XCTAssertTrue(csv.contains("标题,类型,开始时间"))
        XCTAssertTrue(csv.contains("CSV测试"))
    }

    // MARK: BUG #1 回归：lunarAnnually 同一天内发生时间早于锚点时刻 也必须命中
    // 其他规则统一使用 startOfDay 归一化 target/start 进行比较；
    // 修复前 lunarAnnually 使用原始的 date >= startDate 导致 起锚20:00的事件 当天上午09:00查不到。
    func testLunarAnnuallySameDayEarlyHourMustMatch() {
        let cal = Calendar(identifier: .gregorian)
        // 锚点：2025-10-06 20:00（农历八月十五当天的家宴时间）
        var dcPM = DateComponents()
        dcPM.year = 2025; dcPM.month = 10; dcPM.day = 6
        dcPM.hour = 20; dcPM.minute = 0; dcPM.second = 0
        let startPM = cal.date(from: dcPM)!
        let ev = CalendarEvent(title: "中秋晚宴", startDate: startPM, repeatRule: .lunarAnnually)

        // 当天 09:00：必须命中（虽然比锚点时刻早，但属于"当天的日期"）
        var dcAM = DateComponents()
        dcAM.year = 2025; dcAM.month = 10; dcAM.day = 6
        dcAM.hour = 9; dcAM.minute = 0; dcAM.second = 0
        let sameDayAM = cal.date(from: dcAM)!
        XCTAssertTrue(ev.occurs(on: sameDayAM),
                      "lunarAnnually 起锚20:00的事件，当天09:00查询必须命中（BUG #1 回归）")

        // 昨天（10-05）：不命中
        var dcY = DateComponents()
        dcY.year = 2025; dcY.month = 10; dcY.day = 5
        let yesterday = cal.date(from: dcY)!
        XCTAssertFalse(ev.occurs(on: yesterday), "起锚前一天 不应命中")

        // 对比 yearly/monthly/... 等规则都应该命中同一天的清晨时刻
        for rule: RepeatRule in [.daily, .weekly, .monthly, .yearly] {
            let e = CalendarEvent(title: "t", startDate: startPM, repeatRule: rule)
            XCTAssertTrue(e.occurs(on: sameDayAM), "BUG #1 一致性校验：\(rule) 同一天清晨必须命中")
        }
    }

    // MARK: BUG #2 回归：锚点超范围(1899/2101)时 label/anchor/occurs 都不能崩溃
    func testLunarAnnuallyOutOfBoundsAnchorIsNilSafe() {
        let cal = Calendar(identifier: .gregorian)
        var dc = DateComponents()
        dc.year = 1899; dc.month = 12; dc.day = 31
        let oob1899 = cal.date(from: dc)!
        // 1. label：不崩（lunarDateSafe 返回 nil → 走 fallback）
        let ev = CalendarEvent(title: "OOB", startDate: oob1899, repeatRule: .lunarAnnually)
        XCTAssertFalse(ev.repeatRuleLabel.isEmpty, "超范围锚点的 repeatRuleLabel 应给出 fallback 文案")
        // 2. anchor description：不崩
        let desc = CalendarEvent.repeatAnchorDescription(rule: .lunarAnnually, anchor: oob1899)
        XCTAssertTrue(desc.contains("公历锚点"), "超范围锚点的 anchorDescription 至少含公历锚点")
        // 3. occurs：返回 false，不能崩溃
        XCTAssertFalse(ev.occurs(on: Date()), "超范围锚点 occurs 必须返回 false")

        var dc2 = DateComponents()
        dc2.year = 2101; dc2.month = 1; dc2.day = 1
        let oob2101 = cal.date(from: dc2)!
        let ev2101 = CalendarEvent(title: "OOB2", startDate: oob2101, repeatRule: .lunarAnnually)
        XCTAssertFalse(ev2101.repeatRuleLabel.isEmpty)
        XCTAssertFalse(ev2101.occurs(on: Date()))
    }
}
