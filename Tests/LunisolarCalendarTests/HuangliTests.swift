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
}
