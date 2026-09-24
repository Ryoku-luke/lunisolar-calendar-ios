import XCTest
@testable import LunisolarCalendarApp

// MARK: - NotificationManager 补充测试（P1-4b：灵动岛「稍后提醒」入口）

@MainActor
final class NotificationManagerTests: XCTestCase {

    /// 「稍后提醒」在未知事件 ID / 非 App 宿主（命令行测试进程）下必须安全返回 false：
    /// - 未知事件：找不到 EventStore 中的事件 → 直接 false；
    /// - 非 App 宿主：currentCenterIfAvailable 为 nil（不访问 UNUserNotificationCenter），
    ///   否则会在 swift test 进程里因 bundleProxy 缺失而崩溃。
    func testSnoozeReminderIsSafeForUnknownEvent() async {
        let result = await NotificationManager.shared.snoozeReminder(
            eventID: UUID().uuidString,
            after: 60
        )
        XCTAssertFalse(result, "未知事件不应挂载成功")
    }

    /// 非法 ID 字符串同样安全（解析失败 → false，不抛错、不崩溃）
    func testSnoozeReminderIsSafeForMalformedID() async {
        let result = await NotificationManager.shared.snoozeReminder(eventID: "not-a-uuid", after: 60)
        XCTAssertFalse(result)
    }
}
