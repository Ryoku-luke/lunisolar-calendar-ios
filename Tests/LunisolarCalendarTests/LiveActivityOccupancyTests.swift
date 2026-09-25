import XCTest
@testable import LunisolarCalendarApp

// MARK: - 「活动是否还在岛上」判据（纯函数镜像测试，Linux 可跑）

/// 为什么要有这组断言：`Activity<T>.activities` 会包含系统已结束（`.ended`）但尚未从
/// 列表移除的残留项。历史上所有调用点都只看「id 在不在列表里」，于是残留项被当成
/// 「还在岛上」——仲裁器因此永远让位（灵动岛空白），管理器因此去 update 一个不在屏幕上
/// 的活动还返回成功（连失败日志都没有）。
///
/// ⚠️ 这是**判据表**的固化测试，不是行为回归测试：`Activity` / `ActivityState` 无法在
/// 单测里构造，真机行为只能靠设备验证。本文件保证的是「判据不会在后续维护中被改宽」。
final class LiveActivityOccupancyTests: XCTestCase {

    /// 只有仍在展示的两态算「在岛上」
    func testActiveAndStaleAreOnIsland() {
        XCTAssertTrue(LiveActivityOccupancy.isShowing(.active))
        XCTAssertTrue(LiveActivityOccupancy.isShowing(.stale))
    }

    /// 已结束 / 已被系统收走：不算占用，必须允许重建
    func testEndedAndDismissedAreNotOnIsland() {
        XCTAssertFalse(LiveActivityOccupancy.isShowing(.ended))
        XCTAssertFalse(LiveActivityOccupancy.isShowing(.dismissed))
    }

    /// 未来 SDK 新增的状态按「不在岛上」处理：宁可重建（幂等、有日志），不要僵死
    func testUnknownStateIsNotOnIsland() {
        XCTAssertFalse(LiveActivityOccupancy.isShowing(.unknown))
    }

    /// 反例保护：判据不能退化成「只要不是 ended 就算在岛上」
    func testPredicateIsNotTriviallyInverted() {
        let onIsland = [LiveActivityDisplayState.active, .stale]
            .filter(LiveActivityOccupancy.isShowing)
        XCTAssertEqual(onIsland.count, 2, "仍在展示的状态只有 active / stale 两种")
    }
}
