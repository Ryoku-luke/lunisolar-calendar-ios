import XCTest
@testable import LunisolarCalendarApp

// MARK: - 农历转换回归测试（17个真值点）

final class LunarDateTests: XCTestCase {

    private let cal = Calendar(identifier: .gregorian)

    /// 已知农历对照真值表（全部通过系统 Calendar(identifier:.chinese) 验证）
    private let knownCases: [(gy: Int, gm: Int, gd: Int, ly: Int, lm: Int, ld: Int, isLeap: Bool, note: String)] = [
        (1900, 1, 31, 1900, 1, 1, false, "基准 正月初一"),
        (1900, 2, 1,  1900, 1, 2, false, "正月初二"),
        (1900, 2, 28, 1900, 1, 29, false, "正月小29天"),
        (1900, 3, 1,  1900, 2, 1, false, "二月初一"),
        (2020, 5, 22, 2020, 4, 30, false, "四月三十"),
        (2020, 5, 23, 2020, 4, 1, true,  "闰四月初一"),
        (2020, 6, 20, 2020, 4, 29, true,  "闰四月廿九"),
        (2020, 6, 21, 2020, 5, 1, false, "五月初一"),
        (2023, 3, 21, 2023, 2, 30, false, "二月三十"),
        (2023, 3, 22, 2023, 2, 1, true,  "闰二月初一"),
        (2023, 4, 19, 2023, 2, 29, true,  "闰二月廿九"),
        (2023, 4, 20, 2023, 3, 1, false, "三月初一"),
        (2024, 2, 10, 2024, 1, 1, false, "2024甲辰年春节"),
        (2025, 1, 29, 2025, 1, 1, false, "2025乙巳年春节"),
        (2026, 2, 17, 2026, 1, 1, false, "2026丙午年春节"),
        (2100, 2, 9,  2100, 1, 1, false, "2100庚申年春节"),
        (2026, 8, 19, 2026, 7, 7, false, "今日2026-08-19 七月初七"),
    ]

    func testLunarConversionAccuracy() throws {
        for c in knownCases {
            var dc = DateComponents()
            dc.year = c.gy; dc.month = c.gm; dc.day = c.gd
            let date = try XCTUnwrap(cal.date(from: dc))
            let l = ChineseCalendar.lunarDate(from: date)

            XCTAssertEqual(l.year, c.ly, "年不符 [\(c.note)]")
            XCTAssertEqual(l.month, c.lm, "月不符 [\(c.note)]")
            XCTAssertEqual(l.day, c.ld, "日不符 [\(c.note)]")
            XCTAssertEqual(l.isLeapMonth, c.isLeap, "闰月标记不符 [\(c.note)]")
        }
    }

    func testLeapMonthYears() {
        XCTAssertEqual(ChineseCalendar.leapMonth(of: 2020), 4, "2020闰四月")
        XCTAssertEqual(ChineseCalendar.leapMonth(of: 2023), 2, "2023闰二月")
        XCTAssertEqual(ChineseCalendar.leapMonth(of: 2024), 0, "2024无闰月")
    }

    func testBoundaryNilSafe() {
        var dc = DateComponents()
        dc.year = 1899; dc.month = 12; dc.day = 31
        let before = cal.date(from: dc)!
        XCTAssertNil(ChineseCalendar.lunarDateSafe(from: before), "1899年应返回 nil")

        dc.year = 2101; dc.month = 1; dc.day = 1
        let after = cal.date(from: dc)!
        XCTAssertNil(ChineseCalendar.lunarDateSafe(from: after), "2101年应返回 nil")

        dc.year = 2026; dc.month = 8; dc.day = 19
        let within = cal.date(from: dc)!
        XCTAssertNotNil(ChineseCalendar.lunarDateSafe(from: within), "2026年应返回非 nil")
    }

    func testReverseConversion() {
        // 测试农历转公历：2024年正月初一 → 2024-02-10
        let solar = ChineseCalendar.solarDate(fromLunar: 2024, month: 1, day: 1, isLeap: false)
        XCTAssertNotNil(solar)
        let comps = cal.dateComponents([.year, .month, .day], from: solar!)
        XCTAssertEqual(comps.year, 2024)
        XCTAssertEqual(comps.month, 2)
        XCTAssertEqual(comps.day, 10)
    }
}

// MARK: - 黄历测试

final class HuangliTests: XCTestCase {

    func testYiJiStability() {
        let date = Date()
        let a = HuangliGenerator.generate(for: date)
        let b = HuangliGenerator.generate(for: date)
        XCTAssertEqual(a.yi, b.yi, "宜连续调用应一致")
        XCTAssertEqual(a.ji, b.ji, "忌连续调用应一致")
    }

    func testChongSha20241001() {
        var dc = DateComponents()
        dc.year = 2024; dc.month = 10; dc.day = 1
        let cal = Calendar(identifier: .gregorian)
        let date = cal.date(from: dc)!
        let h = HuangliGenerator.generate(for: date)
        XCTAssertEqual(h.chong, "冲龙", "2024-10-01 戊戌日 应冲龙")
    }

    func testAuspiciousIsBool() {
        let h = HuangliGenerator.generate(for: Date())
        // isAuspicial 应该是 true 或 false，不应该崩溃
        _ = h.isAuspicious
    }
}

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
}

// MARK: - EventStore 测试

@MainActor
final class EventStoreTests: XCTestCase {

    func testCRUD() async {
        let store = EventStore()
        let today = Date()
        let initial = store.events(on: today).count

        let ev = CalendarEvent(title: "测试CRUD事件", startDate: today, priority: .high)
        store.add(ev)
        XCTAssertEqual(store.events(on: today).count, initial + 1, "新增后+1")

        store.toggleCompleted(ev)
        let toggled = store.events(on: today).first(where: { $0.id == ev.id })?.isCompleted
        XCTAssertTrue(toggled ?? false, "切换完成态")

        store.delete(ev)
        XCTAssertEqual(store.events(on: today).count, initial, "删除后恢复")
    }

    func testMarkNotified() async {
        let store = EventStore()
        let ev = CalendarEvent(title: "通知测试", startDate: Date().addingTimeInterval(3600))
        store.add(ev)

        XCTAssertFalse(ev.isNotified, "初始应为 false")
        store.markNotified(ev)
        let updated = store.events(on: Date()).first(where: { $0.id == ev.id })
        XCTAssertTrue(updated?.isNotified ?? false, "标记后应为 true")

        store.delete(ev)
    }

    func testSearch() async {
        let store = EventStore()
        let ev = CalendarEvent(title: "可搜索的会议", startDate: Date(), location: "会议室A")
        store.add(ev)

        let results = store.search(query: "会议")
        XCTAssertTrue(results.contains { $0.id == ev.id }, "搜索应匹配标题")

        store.delete(ev)
    }
}
