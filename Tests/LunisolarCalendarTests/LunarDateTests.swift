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
        let s2024 = ChineseCalendar.solarDate(fromLunar: 2024, month: 1, day: 1, isLeap: false)
        XCTAssertNotNil(s2024)
        let c2024 = cal.dateComponents([.year, .month, .day], from: s2024!)
        XCTAssertEqual(c2024.year, 2024); XCTAssertEqual(c2024.month, 2); XCTAssertEqual(c2024.day, 10)

        // 春节（正月初一）双向反查：农历→公历，与公开真值一致
        typealias CNY = (ly: Int, gy: Int, gm: Int, gd: Int, tag: String)
        let cnyCases: [CNY] = [
            (1900, 1900, 1, 31, "1900庚子鼠年春节"),
            (2020, 2020, 1, 25, "2020庚子鼠年春节"),
            (2023, 2023, 1, 22, "2023癸卯兔年春节"),
            (2025, 2025, 1, 29, "2025乙巳蛇年春节"),
            (2026, 2026, 2, 17, "2026丙午马年春节"),
            (2100, 2100, 2,  9, "2100庚申猴年春节 · 上界"),
        ]
        for c in cnyCases {
            let s = ChineseCalendar.solarDate(fromLunar: c.ly, month: 1, day: 1, isLeap: false)
            XCTAssertNotNil(s, "[\(c.tag)] 反查不应返回 nil")
            guard let s = s else { continue }
            let cp = cal.dateComponents([.year, .month, .day], from: s)
            XCTAssertEqual(cp.year,  c.gy, "[\(c.tag)] 公历年不符")
            XCTAssertEqual(cp.month, c.gm, "[\(c.tag)] 公历月不符")
            XCTAssertEqual(cp.day,   c.gd, "[\(c.tag)] 公历日不符")

            // 反向：公历→农历应为 正月初一
            var dc = DateComponents(); dc.year = c.gy; dc.month = c.gm; dc.day = c.gd
            let date = cal.date(from: dc)!
            let l = ChineseCalendar.lunarDate(from: date)
            XCTAssertEqual(l.year, c.ly, "[\(c.tag)] 反推农历年不符")
            XCTAssertEqual(l.month, 1, "[\(c.tag)] 反推农历月应为正月")
            XCTAssertEqual(l.day, 1, "[\(c.tag)] 反推农历日应为初一")
            XCTAssertFalse(l.isLeapMonth, "[\(c.tag)] 正月不能是闰月")
        }
    }
}
