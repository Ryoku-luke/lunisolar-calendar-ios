import XCTest
@testable import LunisolarCalendarApp

// MARK: - 干支年边界 Golden Tests

/// 文档 #5 / #38：干支年按立春换年柱，必须覆盖精确交节时刻前后。
/// 2026 立春 = 2026-02-04 04:02 Asia/Shanghai（Swiss Ephemeris，与紫金山发布 04:01:51 秒级一致，分钟取整差 1 分钟）。
final class YearBoundaryProviderTests: XCTestCase {

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int,
                      tz: String = "Asia/Shanghai") -> Date {
        var dc = DateComponents()
        dc.year = y; dc.month = m; dc.day = d; dc.hour = h; dc.minute = min
        dc.timeZone = TimeZone(identifier: tz)
        return Calendar(identifier: .gregorian).date(from: dc)!
    }

    // MARK: - 2026 立春精确边界（文档 #38 强制案例）

    /// 立春前 2 分钟：2026-02-04 03:59 → 2025 年柱（乙巳）
    func testLichun2026BeforeBoundaryIsPreviousYear() {
        XCTAssertEqual(YearBoundaryProvider.effectiveGanZhiYear(for: date(2026, 2, 4, 3, 59)), 2025)
        XCTAssertEqual(YearBoundaryProvider.ganZhiString(for: date(2026, 2, 4, 3, 59)), "乙巳")
    }

    /// 立春后 1 分钟：2026-02-04 04:03 → 2026 年柱（丙午）
    func testLichun2026AfterBoundaryIsCurrentYear() {
        XCTAssertEqual(YearBoundaryProvider.effectiveGanZhiYear(for: date(2026, 2, 4, 4, 3)), 2026)
        XCTAssertEqual(YearBoundaryProvider.ganZhiString(for: date(2026, 2, 4, 4, 3)), "丙午")
    }

    // MARK: - 跨年区间

    /// 1 月必然在立春前 → 上一年柱
    func testEarlyJanuaryUsesPreviousYearGanZhi() {
        XCTAssertEqual(YearBoundaryProvider.ganZhiString(for: date(2026, 1, 15, 10, 0)), "乙巳")
    }

    /// 年末在立春后 → 当年柱
    func testLateYearUsesCurrentYearGanZhi() {
        XCTAssertEqual(YearBoundaryProvider.ganZhiString(for: date(2026, 12, 31, 10, 0)), "丙午")
    }

    // MARK: - 2025 立春（22:10 边界）

    func testLichun2025ExactBoundary() {
        XCTAssertEqual(YearBoundaryProvider.ganZhiString(for: date(2025, 2, 3, 22, 9)), "甲辰")
        XCTAssertEqual(YearBoundaryProvider.ganZhiString(for: date(2025, 2, 3, 22, 10)), "乙巳")
    }

    // MARK: - 2029 立春精确边界（数据覆盖已补齐 2024–2032）

    /// 2029 立春 = 2029-02-03 21:20（swe）；21:19 → 2028、21:21 → 2029
    func testLichun2029ExactBoundary() {
        XCTAssertEqual(YearBoundaryProvider.effectiveGanZhiYear(for: date(2029, 2, 3, 21, 19)), 2028)
        XCTAssertEqual(YearBoundaryProvider.effectiveGanZhiYear(for: date(2029, 2, 3, 21, 21)), 2029)
    }

    // MARK: - 已知干支锚点（Golden）

    func testKnownGanZhiAnchor() {
        // 春节 2026-02-17：立春已过 → 丙午
        XCTAssertEqual(YearBoundaryProvider.ganZhiString(for: date(2026, 2, 17, 10, 0)), "丙午")
        // 立春后、春节前 2026-02-10：年柱已换丙午（农历年号仍乙巳，口径不同）
        XCTAssertEqual(YearBoundaryProvider.ganZhiString(for: date(2026, 2, 10, 10, 0)), "丙午")
        // 2024 立春精确边界：2024-02-04 16:27（swe，与新华社发布一致）
        XCTAssertEqual(YearBoundaryProvider.ganZhiString(for: date(2024, 2, 3, 23, 59)), "癸卯")
        XCTAssertEqual(YearBoundaryProvider.ganZhiString(for: date(2024, 2, 4, 16, 26)), "癸卯")
        XCTAssertEqual(YearBoundaryProvider.ganZhiString(for: date(2024, 2, 4, 16, 28)), "甲辰")
    }
}
