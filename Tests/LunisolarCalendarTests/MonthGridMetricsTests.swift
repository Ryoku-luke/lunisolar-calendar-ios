import XCTest
@testable import LunisolarCalendarApp

// MARK: - 月历网格尺寸计算（P4-1 抽出的纯函数）
//
// 这段原先埋在 500 行的视图里、无法单测；抽成纯函数后这里把它的**边界**钉住：
// 什么时候该返回 nil（交给调用方给最小可点高度）、上限、下限、以及 chrome 未上报的回退。

final class MonthGridMetricsTests: XCTestCase {

    private func height(rows: Int, isPad: Bool = true,
                        column: CGFloat = 600, chrome: CGFloat = 100) -> CGFloat? {
        MonthGridMetrics.elasticCellHeight(rows: rows, isIPadSplit: isPad,
                                           columnHeight: column, chromeHeight: chrome)
    }

    /// 非 iPad 分栏 → nil：iPhone 不限高，由 `.frame(minHeight:)` 给可点下限
    func testNilWhenNotIPadSplit() {
        XCTAssertNil(height(rows: 5, isPad: false))
    }

    /// 可视高度未测量 / 行数为 0 → nil（不能拿 0 去算出一个荒谬的行高）
    func testNilWhenNotMeasured() {
        XCTAssertNil(height(rows: 5, column: 0))
        XCTAssertNil(height(rows: 0))
    }

    /// 空间充裕 → 不超过上限 96（行高过大会让网格在大屏上散开）
    func testClampsToUpperBound() {
        XCTAssertEqual(height(rows: 5, column: 1200), 96)
    }

    /// 空间紧张 → 不低于最小可点高度（HIG：可点区域不能被压到点不着）
    func testClampsToMinimumTouchHeight() {
        XCTAssertEqual(height(rows: 8, column: 300, chrome: 170), AppTheme.Touch.minCellHeight)
    }

    /// chrome 未上报（0）→ 用 170 的回退值，仍然给出可用行高
    func testFallsBackWhenChromeNotReported() {
        let fallback = height(rows: 6, column: 800, chrome: 0)
        XCTAssertNotNil(fallback, "首次布局前偏好未上报，也要给出可用行高而不是 nil")
        XCTAssertGreaterThanOrEqual(fallback!, AppTheme.Touch.minCellHeight)
    }
}
