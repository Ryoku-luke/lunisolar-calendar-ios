import XCTest
import LunarCore
@testable import LunisolarCalendarApp

// MARK: - 提醒口径一致性测试
//
// 背景：`reminderOffsetMinutes` 的调度实现一直支持全部重复规则，但
// `NotificationManager` 有两处各自按 `type == .reminder` 过滤，而编辑页对「日程」
// 同样提供提醒选择 → 「界面显示已设提醒、到点永远不响」；
// AI 创建的事件因默认 `.schedule` 且不带偏移，也从不会响。
//
// 本文件锁定统一后的判定：**类型与提前量共同决定**，且创建路径真的落到该类型上。

@MainActor
final class ReminderPolicyTests: XCTestCase {

    private let cal = Calendar(identifier: .gregorian)

    private var now: Date {
        var dc = DateComponents()
        dc.year = 2026; dc.month = 9; dc.day = 24; dc.hour = 8; dc.minute = 0
        return cal.date(from: dc)!
    }

    private func event(_ type: EventType, offset: Int?, title: String = "测试") -> CalendarEvent {
        CalendarEvent(title: title, type: type,
                      startDate: now.addingTimeInterval(3600),
                      reminderOffsetMinutes: offset)
    }

    private func createDraft(_ input: String) -> AICreateEventDraft? {
        if case .success(.createEvent(let d)) = AICommandParser.parse(input, baseDate: now) { return d }
        return nil
    }

    // MARK: 判定矩阵

    func testNoteNeverNotifies() {
        XCTAssertFalse(NotificationManager.shouldScheduleNotification(for: event(.note, offset: nil)))
        XCTAssertFalse(NotificationManager.shouldScheduleNotification(for: event(.note, offset: 10)),
                       "记事不参与提醒：即便残留了偏移也不得响")
    }

    func testScheduleNotifiesOnlyWithExplicitOffset() {
        XCTAssertFalse(NotificationManager.shouldScheduleNotification(for: event(.schedule, offset: nil)),
                       "日程默认不打扰")
        XCTAssertTrue(NotificationManager.shouldScheduleNotification(for: event(.schedule, offset: 10)),
                      "日程显式设了提前量就必须响（此前这条永远不响）")
        XCTAssertTrue(NotificationManager.shouldScheduleNotification(for: event(.schedule, offset: 0)),
                      "0 = 准时，也算显式设置")
    }

    func testReminderNotifiesEvenWithoutOffset() {
        XCTAssertTrue(NotificationManager.shouldScheduleNotification(for: event(.reminder, offset: nil)),
                      "提醒类型本身即「到点要响」，无提前量则准时响")
        XCTAssertTrue(NotificationManager.shouldScheduleNotification(for: event(.reminder, offset: 0)))
    }

    // MARK: AI 创建路径：说了「提醒我」必须真的会响

    func testAIDraftUsesReminderTypeForReminderPhrases() throws {
        for input in ["明天下午3点提醒我开会", "明天下午3点提醒开会", "明天下午3点记得开会"] {
            let draft = try XCTUnwrap(createDraft(input), "应解析为创建意图：\(input)")
            XCTAssertEqual(draft.type, .reminder, "「\(input)」应建成提醒类型")
            XCTAssertEqual(draft.title, "开会", "提醒词应从标题中剔除")
        }
    }

    func testAIDraftStaysScheduleWithoutReminderPhrase() throws {
        let draft = try XCTUnwrap(createDraft("明天下午3点开会"))
        XCTAssertEqual(draft.type, .schedule, "没说要提醒就不该主动打扰")
    }

    /// 端到端：解析 → 执行 → 落库的事件类型与提醒判定必须一致
    func testAIExecutionPersistsEventThatWillNotify() throws {
        let store = makeIsolatedEventStore()
        let service = AIAssistantService(eventService: EventService(store: store))
        let command = try XCTUnwrap({
            if case .success(let c) = AICommandParser.parse("明天下午3点提醒我开会", baseDate: now) {
                return c
            }
            return nil
        }())

        guard case .success(.createdEvent(let id)) = service.execute(command, now: now) else {
            return XCTFail("执行应成功创建")
        }

        let created = try XCTUnwrap(store.events.first { $0.id == id })
        XCTAssertEqual(created.type, .reminder)
        XCTAssertTrue(NotificationManager.shouldScheduleNotification(for: created),
                      "AI 创建的提醒必须会响（此前默认 .schedule 且无偏移 → 永不响）")
    }
}
