import XCTest
@testable import LunisolarCalendarApp
import LunarCore

// MARK: - 年视图数据构建的性能基线（执行计划 P3-5）
//
// 计划里写的是「主线程算 365 天 + 每日新建 DateFormatter」——**前半句对、后半句不对**：
// 读代码可见 `buildMarks()` 只建了一个 DateFormatter（`en_US_POSIX` + `yyyyMMdd` 做分桶键），
// 事件也只 filter 一遍。真正的成本是 **365 天 × (节气查询 + 节日查询)**，而且它在
// `onAppear` 里同步跑在主线程上 —— 年视图弹出时的那一下卡顿就来自这里。
//
// 所以基线专门量这一段（与 `buildMarks()` 内层循环同构），用来判断"要不要为此改代码"，
// 以及改完是否真的更快。用 `measure` 而不是断言阈值：阈值型的性能测试会随机变红。

final class YearMarksPerformanceTests: XCTestCase {

    /// 与 `YearOverviewView.buildMarks()` 内层循环同构：365 天，每天查节气 + 节日
    func testYearScanBaseline() {
        let cal = Calendar(identifier: .gregorian)
        var dc = DateComponents(); dc.year = 2026; dc.month = 1; dc.day = 1
        guard let start = cal.date(from: dc) else { return XCTFail("构造不出 2026-01-01") }

        measure {
            for offset in 0..<365 {
                guard let date = cal.date(byAdding: .day, value: offset, to: start) else { continue }
                _ = SolarTermProvider.termOn(date)
                _ = FestivalManager.festivals(on: date).first
            }
        }
    }

    /// 拆开量，看两半各自占多少——优化时才知道该动哪边
    func testSolarTermScanBaseline() {
        let cal = Calendar(identifier: .gregorian)
        var dc = DateComponents(); dc.year = 2026; dc.month = 1; dc.day = 1
        guard let start = cal.date(from: dc) else { return XCTFail("构造不出 2026-01-01") }

        measure {
            for offset in 0..<365 {
                guard let date = cal.date(byAdding: .day, value: offset, to: start) else { continue }
                _ = SolarTermProvider.termOn(date)
            }
        }
    }

    func testFestivalScanBaseline() {
        let cal = Calendar(identifier: .gregorian)
        var dc = DateComponents(); dc.year = 2026; dc.month = 1; dc.day = 1
        guard let start = cal.date(from: dc) else { return XCTFail("构造不出 2026-01-01") }

        measure {
            for offset in 0..<365 {
                guard let date = cal.date(byAdding: .day, value: offset, to: start) else { continue }
                _ = FestivalManager.festivals(on: date).first
            }
        }
    }
}
