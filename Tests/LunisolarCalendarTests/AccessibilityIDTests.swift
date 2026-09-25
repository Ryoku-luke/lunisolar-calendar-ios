import XCTest
@testable import LunisolarCalendarApp

// MARK: - 无障碍标识目录测试
// 保证关键交互元素的稳定 accessibilityIdentifier：非空、无重复、命名规范（小写点分）。
// 纯逻辑测试，Linux / iOS 均可运行；UI 层通过 SwiftUI modifier 引用这些标识。

final class AccessibilityIDTests: XCTestCase {

    func testAllIDsAreNonEmptyAndUnique() {
        let ids = AccessibilityID.all
        XCTAssertFalse(ids.isEmpty, "标识目录不允许为空")
        XCTAssertEqual(Set(ids).count, ids.count, "标识不允许重复: \(ids)")
        for id in ids {
            XCTAssertFalse(id.isEmpty, "标识不允许为空串")
        }
    }

    func testAllIDsFollowNamingConvention() {
        // 规范：小写字母开头，点分段，段内仅小写字母/数字
        let pattern = #"^[a-z][a-z0-9]*(\.[a-z][a-z0-9]*)+$"#
        for id in AccessibilityID.all {
            XCTAssertNotNil(
                id.range(of: pattern, options: .regularExpression),
                "命名不规范（应为 模块.元素.动作 小写点分）: \(id)"
            )
        }
    }

    func testKeyElementsCovered() {
        // 核心新建/保存路径必须都在目录中，防止后续重构漏配
        let ids = AccessibilityID.all
        XCTAssertTrue(ids.contains(AccessibilityID.monthNewEvent))
        XCTAssertTrue(ids.contains(AccessibilityID.dayDetailNewEvent))
        XCTAssertTrue(ids.contains(AccessibilityID.editSave))
        XCTAssertTrue(ids.contains(AccessibilityID.editDelete))
    }

    /// 动态标识（月历日期格）无法进 `all`，单独锁定格式：
    /// 一旦有人改成连字符或纯数字分段，UI 测试的选择器会静默失配，这里先拦住。
    func testMonthDayFormatIsStable() {
        let id = AccessibilityID.monthDay(year: 2026, month: 9, day: 6)
        XCTAssertEqual(id, "calendar.month.day.y2026m09d06")

        let pattern = #"^[a-z][a-z0-9]*(\.[a-z][a-z0-9]*)+$"#
        XCTAssertNotNil(id.range(of: pattern, options: .regularExpression),
                        "动态标识也必须满足命名规范: \(id)")

        // 补零必须稳定：1 月 1 日不能与 10 月 1 日撞成同一个标识
        XCTAssertEqual(AccessibilityID.monthDay(year: 2026, month: 1, day: 1),
                       "calendar.month.day.y2026m01d01")
        XCTAssertNotEqual(AccessibilityID.monthDay(year: 2026, month: 1, day: 1),
                          AccessibilityID.monthDay(year: 2026, month: 10, day: 1))
    }
}
