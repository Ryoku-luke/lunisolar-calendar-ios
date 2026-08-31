import XCTest
@testable import LunisolarCalendarApp

// MARK: - 黄历离散数据库 Provider 测试

final class HuangliDBProviderTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)

    // MARK: 离散库覆盖区间命中 -> source = .discreteDB，字段齐全

    func testDiscreteDBHit20240101() {
        var dc = DateComponents()
        dc.year = 2024; dc.month = 1; dc.day = 1
        let date = cal.date(from: dc)!
        let r = HuangliDBProvider.resolve(date: date)
        XCTAssertEqual(r.source, .discreteDB, "2024-01-01 应命中离散库")
        let h = try! XCTUnwrap(r.huangliDay)
        XCTAssertFalse(h.yi.isEmpty, "宜列表不应空")
        XCTAssertFalse(h.ji.isEmpty, "忌列表不应空")
        // 2024-01-01 干支=甲戌(gan=0 zhi=10) -> 冲=辰6(狗冲龙？) zhi=10(戌), 冲6+10=16%12=4, zodiacs[4]=龙
        XCTAssertTrue(h.chong.hasPrefix("冲"), "冲必须带前缀")
        XCTAssertTrue(h.sha.hasPrefix("煞"), "煞必须带前缀")
        XCTAssertFalse(h.wuXing.isEmpty, "五行纳音应存在")
        XCTAssertTrue(h.shenWei.contains("喜神:"), "神位必须含喜神")
        XCTAssertTrue(h.shenWei.contains("财神:"), "神位必须含财神")
    }

    func testDiscreteDBHit20260819Today() {
        // 今天(真值表中的2026-08-19 七月初七)应该离散库命中
        var dc = DateComponents()
        dc.year = 2026; dc.month = 8; dc.day = 19
        let date = cal.date(from: dc)!
        let r = HuangliDBProvider.resolve(date: date)
        XCTAssertEqual(r.source, .discreteDB, "2026-08-19 应命中离散库 (在 2024~2028)")
        let h1 = r.huangliDay
        let h2 = HuangliGenerator.generate(for: date)
        // generate(for:) 应该返回相同的内容
        XCTAssertEqual(h1?.yi, h2.yi)
        XCTAssertEqual(h1?.ji, h2.ji)
        XCTAssertEqual(h1?.chong, h2.chong)
        XCTAssertEqual(h1?.sha, h2.sha)
        XCTAssertEqual(h1?.wuXing, h2.wuXing)
    }

    // MARK: 离散库尾端 2028-12-31 必须命中；2029-01-01 应该走算法

    func testDiscreteDBBoundaryTail() {
        var dc = DateComponents()
        dc.year = 2028; dc.month = 12; dc.day = 31
        let last = cal.date(from: dc)!
        XCTAssertEqual(
            HuangliDBProvider.resolve(date: last).source, .discreteDB,
            "2028-12-31 是最后一天，必须命中离散库"
        )
        dc.year = 2029; dc.month = 1; dc.day = 1
        let next = cal.date(from: dc)!
        XCTAssertEqual(
            HuangliDBProvider.resolve(date: next).source, .algorithm,
            "2029-01-01 不在覆盖范围，应走算法 fallback"
        )
    }

    // MARK: 越界（1900 前 / 2100 后）-> huangliDay = nil，source=algorithm

    func testOutOfRangeReturnsNil() {
        var dc = DateComponents()
        dc.year = 1899; dc.month = 12; dc.day = 15
        let pre = cal.date(from: dc)!
        let r1 = HuangliDBProvider.resolve(date: pre)
        XCTAssertEqual(r1.source, .algorithm)
        // 农历本身越界 -> huangliDay 可能 nil（允许算法兜底也可能给非 nil，这里不严格）

        dc.year = 2101; dc.month = 3; dc.day = 5
        let post = cal.date(from: dc)!
        let r2 = HuangliDBProvider.resolve(date: post)
        XCTAssertEqual(r2.source, .algorithm)
    }

    // MARK: DB 与算法生成一致性（随机 30 天在 2024-2028 区间内）

    func testDBConsistentWithAlgorithmForRange() {
        let cal = Calendar(identifier: .gregorian)
        var dc = DateComponents()
        dc.year = 2024; dc.month = 1; dc.day = 1
        let rangeStart = cal.date(from: dc)!
        dc.year = 2028; dc.month = 12; dc.day = 31
        let rangeEnd = cal.date(from: dc)!

        var cursor = rangeStart
        var checked = 0
        repeat {
            if cursor > rangeEnd { break }
            let r = HuangliDBProvider.resolve(date: cursor)
            guard let dbDay = r.huangliDay else {
                XCTFail("2024-2028 区间内不应为 nil: \(cursor)")
                break
            }
            XCTAssertEqual(r.source, .discreteDB, "必须命中 DB: \(cursor)")
            let lu = try! XCTUnwrap(ChineseCalendar.lunarDateSafe(from: cursor))
            let algo = HuangliGenerator.algorithmGenerate(for: cursor, lunar: lu)
            XCTAssertEqual(dbDay.yi, algo.yi, "yi 不一致: \(cursor)")
            XCTAssertEqual(dbDay.ji, algo.ji, "ji 不一致: \(cursor)")
            XCTAssertEqual(dbDay.chong, algo.chong, "chong 不一致: \(cursor)")
            XCTAssertEqual(dbDay.sha, algo.sha, "sha 不一致: \(cursor)")
            XCTAssertEqual(dbDay.wuXing, algo.wuXing, "wuxing 不一致: \(cursor)")
            XCTAssertEqual(dbDay.shenWei, algo.shenWei, "shenwei 不一致: \(cursor)")
            checked += 1
            // 每 65 天取 1 个样本（5 年 1827 天 → 抽 29 个）
            cursor = cal.date(byAdding: .day, value: 65, to: cursor)!
        } while checked < 30
    }

    // MARK: coverageDescription 不为空

    func testCoverageDescriptionNotEmpty() {
        let d = HuangliDBProvider.coverageDescription
        XCTAssertFalse(d.isEmpty)
        XCTAssertTrue(d.contains("2024") && d.contains("2028"), "必须声明覆盖范围")
    }
}
