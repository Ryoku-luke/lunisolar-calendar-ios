import XCTest
@testable import LunisolarCalendarApp
import LunarCore

// MARK: - 年视图数据构建的功能测试（P3-5 挪线程的护栏）
//
// `computeMarks` 原本是视图里的私有方法、测不到；为了把它挪到后台（`@concurrent`），
// 它变成了「纯函数」形态——顺手就有了这组测试。它是挪线程的安全网：
// 语义若有偏差（月数、天数、首日星期、节气/节日落位、todayDay），这里会红。

final class YearMarksBuilderTests: XCTestCase {

    private let cal = Calendar(identifier: .gregorian)

    private func marks(year: Int = 2026,
                       now: Date = DateComponents(calendar: Calendar(identifier: .gregorian),
                                                  year: 2026, month: 10, day: 3).date!,
                       events: [CalendarEvent] = []) async -> [Int: YearOverviewView.MonthMarks] {
        await YearOverviewView.computeMarks(year: year, events: events, now: now, cal: cal)
    }

    func testBuildsAllTwelveMonthsWithCorrectDayCounts() async {
        let result = await marks()
        XCTAssertEqual(result.count, 12, "应构建 12 个月")
        XCTAssertEqual(result[1]?.dayCount, 31)
        XCTAssertEqual(result[2]?.dayCount, 28, "2026 不是闰年")
        XCTAssertEqual(result[4]?.dayCount, 30)
        XCTAssertEqual(result[12]?.dayCount, 31)
    }

    /// 首日星期必须是**该月 1 日**的星期（1=周日…7=周六）。
    /// 表头错位的老 bug 就出在这个字段的语义上，所以钉住它。
    func testFirstWeekdayIsTheWeekdayOfTheFirstDay() async {
        let result = await marks()
        // 2026-01-01 是周四（=5）；2026-10-01 也是周四
        XCTAssertEqual(result[1]?.firstWeekday, 5)
        XCTAssertEqual(result[10]?.firstWeekday, 5)
        // 2026-02-01 是周日（=1）
        XCTAssertEqual(result[2]?.firstWeekday, 1)
    }

    func testTodayDayOnlyForTheGivenNow() async {
        let result = await marks()
        XCTAssertEqual(result[10]?.todayDay, 3, "now = 2026-10-03 → 只有 10 月有 todayDay")
        for month in [1, 2, 9, 11, 12] {
            XCTAssertNil(result[month]?.todayDay, "\(month) 月不该有 todayDay")
        }
        // now 换一年 → 该年不应有任何 todayDay
        let other = await marks(year: 2027, now: DateComponents(calendar: Calendar(identifier: .gregorian),
                                                                year: 2026, month: 10, day: 3).date!)
        XCTAssertTrue(other.values.allSatisfy { $0.todayDay == nil },
                      "now 不在该年时，不应标今天")
    }

    /// 中秋（2026-09-25）与霜降（2026-10-23）必须落在对应月份的那一天
    func testFestivalAndSolarTermLandOnTheRightDays() async throws {
        let result = await marks()
        let midAutumn = try XCTUnwrap(result[9]?.festivalDays[25], "2026-09-25 应是中秋")
        XCTAssertFalse(midAutumn.isEmpty)
        XCTAssertEqual(result[10]?.termDays[23], "霜降", "2026-10-23 应是霜降")
    }
}
