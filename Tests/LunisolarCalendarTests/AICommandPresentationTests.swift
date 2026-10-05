import XCTest
@testable import LunisolarCalendarApp

// MARK: - AI 指令的展示/判定逻辑（P4-2 ③ 搬出视图后补的第一批单测）
//
// 为什么值得单测：这两个函数决定的不是"好不好看"，而是**哪些指令会被当成破坏性操作**
// （删除 / 修改要用确认卡挡住，创建不该被挡）。此前它们埋在 400+ 行的视图里，
// 只有缓慢的 UI 流程（Flow3 系 ~90s）间接覆盖 —— 这里把它们钉死。

final class AICommandPresentationTests: XCTestCase {

    private let day = Date(timeIntervalSince1970: 1_759_600_000)   // 固定时刻，避免依赖"今天"

    private func criteria(keyword: String = "例会") -> AIEventCriteria {
        AIEventCriteria(day: day, timeHint: DateComponents(hour: 15, minute: 0), keyword: keyword)
    }

    private func createDraft() -> AICreateEventDraft {
        AICreateEventDraft(title: "写周报", startDate: day, repeatRule: .never)
    }

    // MARK: 判定：哪些指令是破坏性的

    func testDeleteEventIsDestructive() {
        let c = criteria()
        let command = AIStructuredCommand.deleteEvent(AIDeleteEventDraft(criteria: c))
        XCTAssertEqual(AICommandPresentation.destructiveCriteria(of: command), c,
                       "删除指令必须被判为破坏性，否则会绕过确认卡直接删")
    }

    func testUpdateEventIsDestructive() {
        let c = criteria(keyword: "评审")
        let command = AIStructuredCommand.updateEvent(
            AIUpdateEventDraft(criteria: c, newStartDate: day.addingTimeInterval(3600)))
        XCTAssertEqual(AICommandPresentation.destructiveCriteria(of: command), c,
                       "修改指令必须被判为破坏性——改错时间是用户最容易被 AI 误导的操作")
    }

    /// **安全底线**：创建指令绝不能被判成破坏性（否则每次建日程都要多一次确认）
    func testCreateEventIsNotDestructive() {
        let command = AIStructuredCommand.createEvent(createDraft())
        XCTAssertNil(AICommandPresentation.destructiveCriteria(of: command))
    }

    // MARK: 文案：确认卡标题

    func testDeleteLabelIsNotEmpty() {
        let label = AICommandPresentation.destructiveLabel(
            for: .deleteEvent(AIDeleteEventDraft(criteria: criteria())))
        XCTAssertFalse(label.isEmpty, "删除确认卡必须有标题")
    }

    /// 修改的确认卡必须**说清改到什么时候**（只写"确认修改"用户无法判断）
    func testUpdateLabelMentionsTheNewTime() {
        let newStart = day.addingTimeInterval(3600)
        let label = AICommandPresentation.destructiveLabel(
            for: .updateEvent(AIUpdateEventDraft(criteria: criteria(), newStartDate: newStart)))
        let expected = newStart.formatted(date: .abbreviated, time: .shortened)
        XCTAssertTrue(label.contains(expected),
                      "修改确认卡标题应包含新时间（实际：\(label)，期望包含：\(expected)）")
    }

    func testNonDestructiveLabelsAreEmpty() {
        XCTAssertEqual(AICommandPresentation.destructiveLabel(
            for: .createEvent(createDraft())), "",
                       "非破坏性指令不该有确认卡标题")
    }
}
