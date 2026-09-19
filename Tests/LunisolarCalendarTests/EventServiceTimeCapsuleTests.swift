import XCTest
@testable import LunisolarCalendarApp

// MARK: - EventService 时间胶囊映射（文档 #20 优先级表）

final class EventServiceTimeCapsuleTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(_ id: String, type: EventType, priority: Priority,
                       startOffset: TimeInterval, completed: Bool = false) -> CalendarEvent {
        let start = now.addingTimeInterval(startOffset)
        return CalendarEvent(
            title: "测试 \(id)",
            type: type,
            startDate: start,
            endDate: start.addingTimeInterval(3600),
            isAllDay: false,
            notes: nil,
            repeatRule: .never,
            priority: priority,
            reminderOffsetMinutes: nil
        ).withID(UUID(uuidString: id)!)
    }

    func testNoteAndNormalScheduleExcluded() {
        let note = event("10000000-0000-0000-0000-000000000001", type: .note, priority: .high, startOffset: 600)
        let normalSchedule = event("10000000-0000-0000-0000-000000000002", type: .schedule, priority: .normal, startOffset: 600)
        XCTAssertTrue(EventService.timeCapsuleCandidates(from: [note, normalSchedule]).isEmpty)
    }

    func testReminderPriorityMapping() {
        let urgent = event("20000000-0000-0000-0000-000000000001", type: .reminder, priority: .urgent, startOffset: 600)
        let normal = event("20000000-0000-0000-0000-000000000002", type: .reminder, priority: .normal, startOffset: 1200)
        let candidates = EventService.timeCapsuleCandidates(from: [urgent, normal])
        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(candidates.first { $0.eventID == urgent.id }?.priority, .urgent)
        XCTAssertEqual(candidates.first { $0.eventID == normal.id }?.priority, .normal)
    }

    func testHighPriorityScheduleBecomesImportantEvent() {
        let high = event("30000000-0000-0000-0000-000000000001", type: .schedule, priority: .high, startOffset: 600)
        let candidates = EventService.timeCapsuleCandidates(from: [high])
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.type, .event)
        XCTAssertEqual(candidates.first?.priority, .important)
    }

    func testCompletedEventExcluded() {
        let done = event("40000000-0000-0000-0000-000000000001", type: .reminder, priority: .urgent,
                         startOffset: 600, completed: true)
        XCTAssertTrue(EventService.timeCapsuleCandidates(from: [done]).isEmpty)
    }

    func testEndToEndSelection() {
        // 已完成 urgent 被排除 → 选中进行中的 important 提醒
        let doneUrgent = event("50000000-0000-0000-0000-000000000001", type: .reminder, priority: .urgent,
                               startOffset: 600, completed: true)
        let liveImportant = event("50000000-0000-0000-0000-000000000002", type: .reminder, priority: .important,
                                  startOffset: -600)
        let picked = EventService.timeCapsuleCandidates(from: [doneUrgent, liveImportant])
        XCTAssertEqual(picked.count, 1)
        XCTAssertEqual(picked.first?.eventID, liveImportant.id)
    }
}

// MARK: - 测试辅助：CalendarEvent 构造（id 注入）

private extension CalendarEvent {
    func withID(_ id: UUID) -> CalendarEvent {
        var copy = self
        copy.id = id
        return copy
    }
}
