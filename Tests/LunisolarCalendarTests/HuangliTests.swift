import XCTest
import LunarCore
@testable import LunisolarCalendarApp

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

    // MARK: - 喜神 / 财神方位必须按**日干**取（回归：曾误按日支）

    private let gregorian = Calendar(identifier: .gregorian)

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        gregorian.date(from: DateComponents(year: y, month: m, day: d))!
    }

    /// 权威基准（2024-01-01 甲子日）：
    /// 周新春易学网 https://3g.d5168.com/caishenwei/2024-1-1 与
    /// 今日黄历 https://www.jrhuangli.com/2024-1-1.html 均给出「喜神:东北 财神:东北」。
    /// 旧实现（按日支）在这天算成「财神:西南」。
    func testShenWeiMatchesAuthoritativeAlmanac20240101() {
        let h = HuangliGenerator.generate(for: date(2024, 1, 1))
        XCTAssertEqual(h.xiShenDirection, "东北", "甲日喜神应在东北")
        XCTAssertEqual(h.caiShenDirection, "东北", "甲日财神应在东北（旧实现错为西南）")
    }

    /// 核心不变量：**同一日干必同方位**。
    /// 旧实现按日支轮转，同一个日干会出现 6 种不同方位——这条断言就是那个 bug 的探测器。
    func testSameDayStemAlwaysSameDirection() {
        // 六十甲子中每个天干各出现 6 次
        var byStem: [Int: Set<String>] = [:]
        // 1900-01-01 = 甲戌（天干 index 0）
        let base = date(1900, 1, 1)
        for offset in 0..<60 {
            let d = gregorian.date(byAdding: .day, value: offset, to: base)!
            let stem = offset % 10
            let shenWei = HuangliGenerator.algorithmGenerate(
                for: d,
                lunar: ChineseCalendar.lunarDateSafe(from: d) ?? .unsupported
            ).shenWei
            byStem[stem, default: []].insert(shenWei)
        }
        for stem in 0..<10 {
            let samples = byStem[stem] ?? []
            XCTAssertEqual(samples.count, 1,
                           "天干 index \(stem) 出现了 \(samples.count) 种方位，必须唯一：\(samples.sorted())")
        }
    }

    /// 两套口诀的完整取值域：各恰好 5 个方位。
    /// 旧实现取值域退化为 喜神 4 个 / 财神 7 个（含「正西/正东/东南」等不属于财神口诀的方位）。
    func testShenWeiValueDomains() {
        let expectedXi: Set<String> = ["东北", "西北", "西南", "正南", "东南"]
        let expectedCai: Set<String> = ["东北", "西南", "正北", "正东", "正南"]

        var xi: Set<String> = []
        var cai: Set<String> = []
        let base = date(1900, 1, 1)
        for offset in 0..<60 {
            let d = gregorian.date(byAdding: .day, value: offset, to: base)!
            let h = HuangliGenerator.algorithmGenerate(
                for: d,
                lunar: ChineseCalendar.lunarDateSafe(from: d) ?? .unsupported
            )
            xi.insert(h.xiShenDirection)
            cai.insert(h.caiShenDirection)
        }
        XCTAssertEqual(xi, expectedXi, "喜神方位取值域应为《喜神方位歌》的 5 个方位")
        XCTAssertEqual(cai, expectedCai, "财神方位取值域应为《财神方位歌》的 5 个方位")
    }

    /// 逐日干对照两套口诀（甲…癸）
    func testShenWeiPerDayStemMapping() {
        // 《喜神方位歌》：甲己在艮(东北) 乙庚乾(西北) 丙辛坤(西南) 丁壬离(正南) 戊癸巽(东南)
        let expectedXi = ["东北", "西北", "西南", "正南", "东南"]
        // 《财神方位歌》：甲乙东北 丙丁西南 戊己正北 庚辛正东 壬癸正南
        let expectedCai = ["东北", "西南", "正北", "正东", "正南"]

        // 取连续 10 天覆盖全部天干（起始天干为甲）
        let base = date(1900, 1, 1)
        for stem in 0..<10 {
            let d = gregorian.date(byAdding: .day, value: stem, to: base)!
            let h = HuangliGenerator.algorithmGenerate(
                for: d,
                lunar: ChineseCalendar.lunarDateSafe(from: d) ?? .unsupported
            )
            XCTAssertEqual(h.xiShenDirection, expectedXi[stem % 5],
                           "天干 index \(stem) 喜神方位不符口诀")
            XCTAssertEqual(h.caiShenDirection, expectedCai[stem / 2],
                           "天干 index \(stem) 财神方位不符口诀")
        }
    }
}
