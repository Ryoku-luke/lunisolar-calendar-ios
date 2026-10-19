import XCTest
@testable import LunisolarCalendarApp
#if canImport(SwiftUI)
import SwiftUI

// MARK: - 全局强调色跟随节日的**可证伪**契约
//
// 改造目标：普通日与改造前**完全一致**（品牌色），只有节日当天整体变色。
// 这两条断言正好把这两件事钉住 —— 任一条变红都说明"统一配色"被改坏了。

final class DayAccentTintTests: XCTestCase {

    private let cal = Calendar(identifier: .gregorian)

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    /// 普通日子：全局强调色**必须恰好等于**品牌色（品牌识别不受"节日配色"影响）
    func testOrdinaryDayFallsBackToBrandTint() {
        // 2026-10-15 既非节日也非节气
        XCTAssertEqual(DayAccent(date: day(2026, 10, 15)).controlTint, Color.appTint)
    }

    /// 节日当天：强调色**必须不等于**品牌色（否则"随节假日统一改变"等于没做）
    func testFestivalDayDoesNotUseBrandTint() {
        // 2026-10-01 国庆节
        XCTAssertNotEqual(DayAccent(date: day(2026, 10, 1)).controlTint, Color.appTint)
    }
}
#endif
