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

    // MARK: 「稍后提醒」ID 必须同源
    //
    // rescheduleAllReminders 会 cancelAll() 清空所有 pending，再靠解析 ID 把「稍后提醒」
    // 保回来（否则用户点了稍后提醒、10 分钟内回到前台就永远收不到）。

    func testSnoozeIdentifierRoundTrip() {
        let raw = UUID().uuidString
        let identifier = NotificationManager.snoozeIdentifier(eventID: raw, at: 1_800_000_000)
        XCTAssertTrue(identifier.hasPrefix(NotificationManager.snoozeIdentifierPrefix))
        XCTAssertEqual(NotificationManager.snoozeEventID(from: identifier), UUID(uuidString: raw),
                       "构造与解析必须成对，否则重排时认不出这条 snooze")
    }

    /// 常规事件组的 ID 不得被误判为 snooze（否则重排时会保留本不该保留的通知）
    func testRegularIdentifiersAreNotMistakenForSnooze() {
        let base = UUID().uuidString
        for id in [base, "\(base)-lunar", "\(base)-wd-2"] {
            XCTAssertNil(NotificationManager.snoozeEventID(from: id))
        }
    }

    func testMalformedSnoozeIdentifierReturnsNil() {
        XCTAssertNil(NotificationManager.snoozeEventID(from: "snooze-"))
        XCTAssertNil(NotificationManager.snoozeEventID(from: "snooze-not-a-uuid-12"))
    }

    /// 重排时只保回「事件仍存在」的 snooze（事件已删除不该继续提醒）
    func testSnoozesPreservedOnlyForExistingEvents() {
        let alive = UUID().uuidString
        let deleted = UUID().uuidString
        let aliveSnooze = NotificationManager.snoozeIdentifier(eventID: alive, at: 1)
        let deletedSnooze = NotificationManager.snoozeIdentifier(eventID: deleted, at: 2)

        let keep = NotificationManager.snoozeIdentifiersToPreserve(
            from: [aliveSnooze, deletedSnooze, alive, "\(alive)-lunar", "\(alive)-wd-2"],
            existingEventIDs: [alive]
        )

        XCTAssertEqual(keep, [aliveSnooze], "只应保回仍存在事件的那条 snooze，常规分组 ID 不得被保留")
    }

    /// pending 里没有任何 snooze 时，保回集合为空（不影响正常重排）
    func testNoSnoozeToPreserveWhenOnlyRegularIds() {
        let base = UUID().uuidString
        let keep = NotificationManager.snoozeIdentifiersToPreserve(
            from: [base, "\(base)-lunar"],
            existingEventIDs: [base]
        )
        XCTAssertTrue(keep.isEmpty)
    }
}
