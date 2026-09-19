import XCTest
import LunarCore

// MARK: - 传统节日 Golden Tests（文档 #38）

/// 以中国政府网《国务院办公厅关于2026年部分节假日安排的通知》及
/// 农历权威换算表为真值，锁定"农历节日 → 公历"与"公历 → 农历节日"
/// 双向转换锚点。防止历法算法回归导致节日错位。
final class FestivalGoldenTests: XCTestCase {

    private let cal = Calendar(identifier: .gregorian)

    private func gregorian(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var dc = DateComponents()
        dc.year = y; dc.month = m; dc.day = d
        return cal.date(from: dc)!
    }

    /// 农历 → 公历：断言节日落在正确公历日期
    private func assertLunarFestival(_ ly: Int, _ lm: Int, _ ld: Int,
                                     gy: Int, gm: Int, gd: Int,
                                     note: String, isLeap: Bool = false) {
        let solar = ChineseCalendar.solarDate(fromLunar: ly, month: lm, day: ld, isLeap: isLeap)
        XCTAssertNotNil(solar, "[\(note)] 农历→公历不应为 nil")
        guard let solar else { return }
        let c = cal.dateComponents([.year, .month, .day], from: solar)
        XCTAssertEqual(c.year,  gy, "[\(note)] 公历年不符")
        XCTAssertEqual(c.month, gm, "[\(note)] 公历月不符")
        XCTAssertEqual(c.day,   gd, "[\(note)] 公历日不符")
    }

    /// 公历 → 农历：断言该公历日期的农历为指定节日
    private func assertGregorianFestival(_ gy: Int, _ gm: Int, _ gd: Int,
                                         ly: Int, lm: Int, ld: Int,
                                         note: String) {
        let lunar = ChineseCalendar.lunarDate(from: gregorian(gy, gm, gd))
        XCTAssertEqual(lunar.year,  ly, "[\(note)] 农历年不符")
        XCTAssertEqual(lunar.month, lm, "[\(note)] 农历月不符")
        XCTAssertEqual(lunar.day,   ld, "[\(note)] 农历日不符")
    }

    // MARK: - 2026 年（春节 2/17，国务院已确认端午 6/19、中秋 9/25）

    func test2026FestivalsLunarToSolar() {
        assertLunarFestival(2026, 1, 15, gy: 2026, gm: 3,  gd: 3,  note: "2026 元宵")
        assertLunarFestival(2026, 5, 5,  gy: 2026, gm: 6,  gd: 19, note: "2026 端午（国务院确认）")
        assertLunarFestival(2026, 7, 7,  gy: 2026, gm: 8,  gd: 19, note: "2026 七夕")
        assertLunarFestival(2026, 8, 15, gy: 2026, gm: 9,  gd: 25, note: "2026 中秋（国务院确认）")
        assertLunarFestival(2026, 9, 9,  gy: 2026, gm: 10, gd: 18, note: "2026 重阳")
    }

    func test2026FestivalsSolarToLunar() {
        assertGregorianFestival(2026, 3,  3,  ly: 2026, lm: 1, ld: 15, note: "2026-03-03 元宵")
        assertGregorianFestival(2026, 6,  19, ly: 2026, lm: 5, ld: 5,  note: "2026-06-19 端午")
        assertGregorianFestival(2026, 9,  25, ly: 2026, lm: 8, ld: 15, note: "2026-09-25 中秋")
        assertGregorianFestival(2026, 10, 18, ly: 2026, lm: 9, ld: 9,  note: "2026-10-18 重阳")
    }

    // MARK: - 2025 年

    func test2025Festivals() {
        assertLunarFestival(2025, 1, 15, gy: 2025, gm: 2, gd: 12, note: "2025 元宵")
        assertLunarFestival(2025, 5, 5,  gy: 2025, gm: 5, gd: 31, note: "2025 端午")
        // 2025 闰六月：八月十五顺延至 10-06（与 2025 国庆中秋连假一致）
        assertLunarFestival(2025, 8, 15, gy: 2025, gm: 10, gd: 6, note: "2025 中秋（闰六月年顺延）")
    }

    // MARK: - 闰月年的农历节日（2025 闰六月、2028 闰五月）

    func testLeapMonthYearsDoNotShiftFestivals() {
        // 2025 闰六月：七月初七顺延至 08-29
        assertLunarFestival(2025, 7, 7, gy: 2025, gm: 8, gd: 29, note: "2025 七夕（闰六月年）")
        // 2028 闰五月：八月十五顺延至 10-03
        assertLunarFestival(2028, 8, 15, gy: 2028, gm: 10, gd: 3, note: "2028 中秋（闰五月年）")
    }
}
