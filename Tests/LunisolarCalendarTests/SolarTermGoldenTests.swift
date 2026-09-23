import XCTest
@testable import LunisolarCalendarApp

// MARK: - 节气时刻 Golden Tests（数据覆盖 2024–2032）

/// 文档 #40：所有节气逻辑必须有测试。
/// 抽样断言与新华社/央视发布值一致的节气交节时刻（Asia/Shanghai），
/// 验证 2024–2032 全量节气表数据正确性。
final class SolarTermGoldenTests: XCTestCase {

    private func assertTerm(_ year: Int, _ index: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int,
                            file: StaticString = #filePath, line: UInt = #line) {
        guard let date = SolarTermProvider.termDate(year: year, index: index) else {
            XCTFail("缺数据 year=\(year) index=\(index)", file: file, line: line)
            return
        }
        var dc = Calendar(identifier: .gregorian)
        dc.timeZone = QingheCalendarContext.chinaTimeZone
        let comps = dc.dateComponents([.month, .day, .hour, .minute], from: date)
        XCTAssertEqual(comps.month, m, "\(year) index \(index) 月份不符", file: file, line: line)
        XCTAssertEqual(comps.day, d, "\(year) index \(index) 日不符", file: file, line: line)
        XCTAssertEqual(comps.hour, h, "\(year) index \(index) 时不符", file: file, line: line)
        XCTAssertEqual(comps.minute, min, "\(year) index \(index) 分不符", file: file, line: line)
    }

    // MARK: - 立春（index 2，干支换年锚点）

    /// 2024 立春 02-04 16:27（新华社）
    func testLichun2024() { assertTerm(2024, 2, 2, 4, 16, 27) }
    /// 2025 立春 02-03 22:10（紫金山）
    func testLichun2025() { assertTerm(2025, 2, 2, 3, 22, 10) }
    /// 2026 立春 02-04 04:02（swe，紫金山发布 04:01:51）
    func testLichun2026() { assertTerm(2026, 2, 2, 4, 4, 2) }
    /// 2028 立春 02-04 15:31（bmcx 15:30:53）
    func testLichun2028() { assertTerm(2028, 2, 2, 4, 15, 31) }
    /// 2029 立春 02-03 21:20（swe，原近似窗口已消除）
    func testLichun2029() { assertTerm(2029, 2, 2, 3, 21, 20) }
    /// 2032 立春 02-04 14:48（swe）
    func testLichun2032() { assertTerm(2032, 2, 2, 4, 14, 48) }

    // MARK: - 其他节气抽样（与权威发布值一致）

    /// 2024 小寒 01-06 04:49（新华社）
    func testXiaohan2024() { assertTerm(2024, 0, 1, 6, 4, 49) }
    /// 2024 冬至 12-21 17:20（新华社/权威）
    func testDongzhi2024() { assertTerm(2024, 23, 12, 21, 17, 20) }
    /// 2025 小满 05-21 02:54（央视 2:55）—— 修正现有 03:54 抄录错误
    func testXiaoman2025() { assertTerm(2025, 9, 5, 21, 2, 54) }
    /// 2025 夏至 06-21 10:42（紫金山）
    func testXiazhi2025() { assertTerm(2025, 11, 6, 21, 10, 42) }
    /// 2026 小雪 11-22 15:23（紫金山查询站/香港天文台）—— 修正现有 09:46 错误
    func testXiaoxue2026() { assertTerm(2026, 21, 11, 22, 15, 23) }
    /// 2026 冬至 12-22 04:50（香港天文台）
    func testDongzhi2026() { assertTerm(2026, 23, 12, 22, 4, 50) }
    /// 2027 立冬 11-07 23:38（swe/香港天文台 PDF 23:38? 以 swe 为准）
    func testLidong2027() { assertTerm(2027, 20, 11, 7, 23, 38) }
    /// 2030 春分 03-20 21:52（swe）
    func testChunfen2030() { assertTerm(2030, 5, 3, 20, 21, 52) }

    // MARK: - 数据结构自洽性

    /// 2024–2032 每年 24 个节气齐全且按时间升序
    func testAllYearsHave24TermsInOrder() {
        let names = SolarTermProvider.termNames
        XCTAssertEqual(names.count, 24)
        for year in 2024...2032 {
            let terms = SolarTermProvider.terms(in: year)
            XCTAssertEqual(terms.count, 24, "\(year) 应含 24 节气")
            // 时间升序且名字齐全
            let termNames = terms.map { $0.name }
            XCTAssertEqual(termNames, names, "\(year) 节气名顺序应为小寒→冬至")
            for i in 1..<terms.count {
                XCTAssertLessThan(terms[i - 1].date, terms[i].date, "\(year) 第 \(i) 个节气时间未升序")
            }
        }
    }
    func testNextTermDoesNotReturnPassedTermOnSameDay() {
        let term = SolarTermProvider.termDate(year: 2026, index: 16)! // 白露
        let after = term.addingTimeInterval(3 * 3600)
        let next = SolarTermProvider.nextTerm(from: after)
        XCTAssertNotNil(next)
        XCTAssertGreaterThan(next!.date, after)
        XCTAssertNotEqual(next!.name, "白露")
    }

    func testTermAroundFindsRecentlyPassedTerm() {
        let term = SolarTermProvider.termDate(year: 2026, index: 17)! // 秋分
        let after = term.addingTimeInterval(90 * 60)
        let found = SolarTermProvider.termAround(after, window: 2 * 3600)
        XCTAssertEqual(found?.date, term)
        XCTAssertEqual(found?.name, "秋分")
    }

}
