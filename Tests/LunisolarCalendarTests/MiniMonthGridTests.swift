import XCTest
@testable import LunisolarCalendarApp

// MARK: - 年视图迷你月卡网格（回归：表头与日期列曾经整体错位）
//
// 旧实现里表头按「该月 1 日的星期」旋转整行，日期格却固定从周日起始：
// 以 2026-10 为例（10/1 是周四），第 0 列表头写「四」，10/1 却落在第 4 列
// （表头写「一」），12 张月卡全部对不上；同时整年视图都没读「每周起始日」。
//
// 现在表头列位与前导空格都由 MiniMonthGrid 统一算出，本文件用「每个日期的真实星期」
// 逐年逐日反查，把这条不变式钉住。

final class MiniMonthGridTests: XCTestCase {

    private let cal = Calendar(identifier: .gregorian)

    private func firstDay(ofMonth month: Int, in year: Int) -> Date {
        var dc = DateComponents()
        dc.year = year; dc.month = month; dc.day = 1
        return cal.date(from: dc)!
    }

    // MARK: 核心不变式

    /// 网格里任一日期上方表头写的星期，必须等于该日期的真实星期。
    /// 2026 全年 365 天 × 两种每周起始日，逐个核对。
    func testHeaderColumnMatchesRealWeekdayForEveryDayOf2026() throws {
        for weekStart in [1, 2] {
            for month in 1...12 {
                let first = firstDay(ofMonth: month, in: 2026)
                let firstWeekday = cal.component(.weekday, from: first)
                let dayCount = try XCTUnwrap(cal.range(of: .day, in: .month, for: first)?.count)
                let lead = MiniMonthGrid.leadingBlanks(firstDayWeekday: firstWeekday, weekStart: weekStart)

                for day in 1...dayCount {
                    let column = (lead + day - 1) % 7
                    let headerWeekday = MiniMonthGrid.weekday(atColumn: column, weekStart: weekStart)
                    var dc = DateComponents()
                    dc.year = 2026; dc.month = month; dc.day = day
                    let date = try XCTUnwrap(cal.date(from: dc))
                    XCTAssertEqual(
                        headerWeekday, cal.component(.weekday, from: date),
                        "2026-\(month)-\(day)：第 \(column) 列表头写的是 \(headerWeekday)，"
                        + "真实星期是 \(cal.component(.weekday, from: date))（weekStart=\(weekStart)）"
                    )
                }
            }
        }
    }

    // MARK: 具体错位案例（2026-10-01 周四）

    func testOctober2026FirstRowStartsOnSundayOrMonday() {
        let firstWeekday = cal.component(.weekday, from: firstDay(ofMonth: 10, in: 2026))
        XCTAssertEqual(firstWeekday, 5, "2026-10-01 是周四")

        // 周日起始：前面空 4 格（日一二三），10/1 落在第 4 列
        XCTAssertEqual(MiniMonthGrid.leadingBlanks(firstDayWeekday: 5, weekStart: 1), 4)
        XCTAssertEqual(MiniMonthGrid.weekday(atColumn: 0, weekStart: 1), 1, "第 0 列是周日")
        XCTAssertEqual(MiniMonthGrid.weekday(atColumn: 4, weekStart: 1), 5, "第 4 列是周四")

        // 周一起始：前面空 3 格（一二三），10/1 落在第 3 列
        XCTAssertEqual(MiniMonthGrid.leadingBlanks(firstDayWeekday: 5, weekStart: 2), 3)
        XCTAssertEqual(MiniMonthGrid.weekday(atColumn: 0, weekStart: 2), 2, "第 0 列是周一")
        XCTAssertEqual(MiniMonthGrid.weekday(atColumn: 3, weekStart: 2), 5, "第 3 列是周四")
    }

    // MARK: 表头列序

    func testWeekdayColumnOrderFollowsWeekStart() {
        XCTAssertEqual((0..<7).map { MiniMonthGrid.weekday(atColumn: $0, weekStart: 1) },
                       [1, 2, 3, 4, 5, 6, 7], "周日起始：日一二三四五六")
        XCTAssertEqual((0..<7).map { MiniMonthGrid.weekday(atColumn: $0, weekStart: 2) },
                       [2, 3, 4, 5, 6, 7, 1], "周一起始：一二三四五六日")
    }

    // MARK: 格数

    /// 不少于 5 行且为整行 —— 12 张月卡等高
    func testCellCountIsAtLeastFiveRowsAndWholeRows() {
        for weekStart in [1, 2] {
            for month in 1...12 {
                let first = firstDay(ofMonth: month, in: 2026)
                let firstWeekday = cal.component(.weekday, from: first)
                let dayCount = cal.range(of: .day, in: .month, for: first)!.count

                let cells = MiniMonthGrid.cellCount(firstDayWeekday: firstWeekday,
                                                    dayCount: dayCount, weekStart: weekStart)
                XCTAssertGreaterThanOrEqual(cells, 35, "\(month) 月不足 5 行会让月卡矮一截")
                XCTAssertEqual(cells % 7, 0, "\(month) 月格数应为整行")
                XCTAssertGreaterThanOrEqual(cells,
                                            MiniMonthGrid.leadingBlanks(firstDayWeekday: firstWeekday,
                                                                        weekStart: weekStart) + dayCount,
                                            "\(month) 月格数必须容得下全部日期")
            }
        }
    }

    /// 2026-02（1 日是周日、28 天）恰好 4 行 → 必须补到 5 行
    func testFebruary2026PadsToFiveRows() {
        let firstWeekday = cal.component(.weekday, from: firstDay(ofMonth: 2, in: 2026))
        XCTAssertEqual(firstWeekday, 1, "2026-02-01 是周日")
        XCTAssertEqual(MiniMonthGrid.leadingBlanks(firstDayWeekday: 1, weekStart: 1), 0)
        XCTAssertEqual(MiniMonthGrid.cellCount(firstDayWeekday: 1, dayCount: 28, weekStart: 1), 35)
    }
}
