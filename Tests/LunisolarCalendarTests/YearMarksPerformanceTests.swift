import XCTest
@testable import LunisolarCalendarApp
import LunarCore

// MARK: - 年视图数据构建的性能基线（执行计划 P3-5）
//
// 量的是 `YearOverviewView.buildMarks()` 的两块真实成本：365 天 × (节气查询 + 节日查询)。
//
// ⚠️ 写这类微基准踩过的坑（都体现在下面的写法里）：
// 1. **不要把冷热混在一次测量里**：初版有一条"不清缓存"的用例，首轮流冷（66ms）、
//    其余流热（1ms）→ 双峰分布、相对标准差 161%，而 `measure` 对相对标准差有容差
//    （默认 10%），会**偶发判红**（实测遇到过一次：某时区 421 条里挂 1 条，重跑又绿）。
//    现在冷/热分开量。
// 2. **工作量要放大到毫秒级以上**：1–3ms 的微基准噪声占比过大；每次采样跑多遍压噪声。
// 3. 结论只认量出来的数：改前 365 天全扫 **216ms**（节气 79 + 节日 141）。

final class YearMarksPerformanceTests: XCTestCase {

    private let cal = Calendar(identifier: .gregorian)

    /// 2026 年 365 天（与年视图看到的范围一致）
    private var days2026: [Date] {
        var dc = DateComponents(); dc.year = 2026; dc.month = 1; dc.day = 1
        guard let start = cal.date(from: dc) else { return [] }
        return (0..<365).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    /// 节气查询：O(log n) 二分、无缓存 → 确定性最好的一条
    /// （每次采样 200 遍，把 1–3ms 级放大到几百毫秒以压低相对标准差——抖动 >10% 会偶发判红）
    func testSolarTermScan() {
        let days = days2026
        XCTAssertEqual(days.count, 365)
        measure {
            for _ in 0..<200 {
                for date in days { _ = SolarTermProvider.termOn(date) }
            }
        }
    }

    /// 节日查询 · **冷**：每次采样先清缓存，量的是"真算"的成本（大头是农历转换）
    func testFestivalScanCold() {
        let days = days2026
        measure {
            for _ in 0..<10 {
                FestivalManager.resetCacheForTesting()
                for date in days { _ = FestivalManager.festivals(on: date).first }
            }
        }
    }

    /// 节日查询 · **热**：缓存已填——真实使用中的常见情形
    /// （月历网格每格每次渲染都会问一次，年视图一次问 365 天）
    func testFestivalScanWarm() {
        let days = days2026
        FestivalManager.resetCacheForTesting()
        for date in days { _ = FestivalManager.festivals(on: date) }   // 预热

        measure {
            for _ in 0..<200 {
                for date in days { _ = FestivalManager.festivals(on: date).first }
            }
        }
    }
}
