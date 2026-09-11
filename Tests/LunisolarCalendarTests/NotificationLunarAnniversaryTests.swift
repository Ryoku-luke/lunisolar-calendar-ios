import XCTest
@testable import LunisolarCalendarApp
@testable import LunarCore

/// 回归测试：NotificationManager 农历周年提醒日期计算。
/// 核心逻辑已抽为纯函数 nextSolarDateForLunarAnniversary，可在 Linux 直接测试。
final class NotificationLunarAnniversaryTests: XCTestCase {

    private let gregorian = Calendar(identifier: .gregorian)

    /// P1 回归：事件起始日距今超过 16 年（农历生日从出生日起算），
    /// 旧实现搜索区间 `lunar.year...lunar.year+16` 全落在过去 → 返回 nil → 永不提醒。
    /// 修复后必须从「今天所在农历年」开始搜，返回未来第一个匹配日。
    func testLunarAnniversaryFromFarPastReturnsFutureDate() throws {
        // 农历 1990 年五月初五（端午），距今 >16 年
        guard let birthSolar = ChineseCalendar.solarDate(
            fromLunar: 1990, month: 5, day: 5, isLeap: false
        ) else {
            return XCTFail("无法构造 1990 农历五月初五的公历日期")
        }

        // 取一个明确的"今天"：2026-09-06
        var nowComps = DateComponents()
        nowComps.year = 2026; nowComps.month = 9; nowComps.day = 6
        nowComps.hour = 12; nowComps.minute = 0; nowComps.second = 0
        nowComps.timeZone = TimeZone(identifier: "Asia/Shanghai")
        let now = gregorian.date(from: nowComps)!

        let result = NotificationManager.nextSolarDateForLunarAnniversary(
            lunarSource: birthSolar,
            timeSource: birthSolar,
            now: now
        )

        XCTAssertNotNil(result, "农历生日提醒不应因起始日久远而返回 nil")
        let next = try XCTUnwrap(result)
        XCTAssertTrue(next > now, "返回的提醒日期必须在未来")

        // 返回日的农历月/日必须与源一致（五月初五）
        let nextLunar = ChineseCalendar.lunarDateSafe(from: next)
        XCTAssertEqual(nextLunar?.month, 5)
        XCTAssertEqual(nextLunar?.day, 5)
        XCTAssertEqual(nextLunar?.isLeapMonth, false)
    }

    /// 今年的农历生日已过 → 返回明年的同一天（而非 nil）。
    func testLunarAnniversaryAfterThisYearsOccurrenceReturnsNextYear() throws {
        // 农历 1995 年正月初一（春节）
        guard let springSolar = ChineseCalendar.solarDate(
            fromLunar: 1995, month: 1, day: 1, isLeap: false
        ) else {
            return XCTFail("无法构造 1995 农历正月初一的公历日期")
        }

        // "今天" = 2026 年春节之后（2026 春节 = 2026-02-17）
        var nowComps = DateComponents()
        nowComps.year = 2026; nowComps.month = 3; nowComps.day = 1
        nowComps.hour = 0; nowComps.minute = 0; nowComps.second = 0
        nowComps.timeZone = TimeZone(identifier: "Asia/Shanghai")
        let now = gregorian.date(from: nowComps)!

        let result = NotificationManager.nextSolarDateForLunarAnniversary(
            lunarSource: springSolar,
            timeSource: springSolar,
            now: now
        )

        let next = try XCTUnwrap(result)
        XCTAssertTrue(next > now)

        // 下一个正月初一应在 2027 年
        let nextLunar = ChineseCalendar.lunarDateSafe(from: next)
        XCTAssertEqual(nextLunar?.month, 1)
        XCTAssertEqual(nextLunar?.day, 1)
        // 2027 春节公历日期
        guard let expected2027 = ChineseCalendar.solarDate(
            fromLunar: 2027, month: 1, day: 1, isLeap: false
        ) else { return }
        XCTAssertTrue(
            gregorian.isDate(next, inSameDayAs: expected2027),
            "2026 年春节后，下一次正月初一应在 2027 年春节当天"
        )
    }

    /// 农历"三十"生日在目标年该月只有 29 天时回退到廿九（不跳过该年）。
    func testLunarAnniversaryDay30FallsBackTo29() throws {
        // 动态找一个腊月有 30 天的农历年份作为源（保证源确实是"三十"）
        var sourceYear: Int?
        for y in 1980...2020 {
            if ChineseCalendar.daysInLunarMonth(year: y, month: 12, isLeap: false) == 30 {
                sourceYear = y
                break
            }
        }
        guard let sy = sourceYear else {
            return XCTFail("未找到腊月有 30 天的年份，无法测试三十→廿九回退")
        }
        guard let source = ChineseCalendar.solarDate(
            fromLunar: sy, month: 12, day: 30, isLeap: false
        ) else {
            return XCTFail("无法构造 \(sy) 农历腊月三十")
        }

        var nowComps = DateComponents()
        nowComps.year = 2026; nowComps.month = 1; nowComps.day = 1
        nowComps.timeZone = TimeZone(identifier: "Asia/Shanghai")
        let now = gregorian.date(from: nowComps)!

        let result = NotificationManager.nextSolarDateForLunarAnniversary(
            lunarSource: source,
            timeSource: source,
            now: now
        )

        let next = try XCTUnwrap(result)
        let nextLunar = ChineseCalendar.lunarDateSafe(from: next)
        // 源是腊月三十，目标年腊月不论 29 还是 30 天都必须返回有效日期（30→29 fallback）
        XCTAssertEqual(nextLunar?.month, 12)
        XCTAssertTrue(nextLunar?.day == 29 || nextLunar?.day == 30,
                       "腊月三十生日应回退到廿九或保持三十，实际 day=\(nextLunar?.day ?? -1)")
    }
}
