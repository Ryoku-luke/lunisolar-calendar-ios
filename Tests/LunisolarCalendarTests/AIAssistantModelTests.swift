import XCTest
@testable import LunisolarCalendarApp

// MARK: - AIAssistantModel 的第一批单测（P4-2 ③ 的目的：AI 逻辑脱离 UI 也能测）
//
// 模型已标 @MainActor（showSuccess 里用 Task{@MainActor} 回写状态），故测试类同样隔离。
// 这里只断言**不依赖外部服务**的部分：目标日推导与"是否重复日程"判定。

@MainActor
final class AIAssistantModelTests: XCTestCase {

    private let day = Date(timeIntervalSince1970: 1_759_600_000)   // 固定时刻，不依赖"今天"

    private func criteria(keyword: String = "例会") -> AIEventCriteria {
        AIEventCriteria(day: day, timeHint: DateComponents(hour: 15, minute: 0), keyword: keyword)
    }

    /// 删除指令 → 目标日取自它自己的 criteria
    func testCriteriaDayFollowsDeleteCommand() {
        let model = AIAssistantModel()
        let c = criteria()
        model.pendingCommand = .deleteEvent(AIDeleteEventDraft(criteria: c))
        XCTAssertEqual(model.criteriaDay, c.day)
    }

    /// 修改指令 → 同样取自 criteria（注意：不是 newStartDate —— 目标是"要改的那条"）
    func testCriteriaDayFollowsUpdateCommand() {
        let model = AIAssistantModel()
        let c = criteria(keyword: "评审")
        model.pendingCommand = .updateEvent(
            AIUpdateEventDraft(criteria: c, newStartDate: day.addingTimeInterval(7200)))
        XCTAssertEqual(model.criteriaDay, c.day,
                       "目标日应是被修改日程所在日，而不是改到的新时间")
    }

    /// 非破坏性指令 → 没有目标日（安全底线：创建指令不能被当成破坏性操作处理）
    func testCriteriaDayIsNilForNonDestructiveCommand() {
        let model = AIAssistantModel()
        model.pendingCommand = .createEvent(
            AICreateEventDraft(title: "写周报", startDate: day, repeatRule: .never))
        XCTAssertNil(model.criteriaDay)
    }

    /// 没有选中目标时，不应被判为"重复日程"（避免对空目标做整条规则的破坏性提示）
    func testWasRepeatingTargetIsFalseWithoutTarget() {
        let model = AIAssistantModel()
        XCTAssertNil(model.destructiveTarget)
        XCTAssertFalse(model.wasRepeatingTarget)
    }
}

// MARK: - create：注入替身单测（P4-2 ③-2c-2 的目的：破坏性/落点行为脱离 UI 也能测）

@MainActor
final class AIAssistantModelCreateTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_759_600_000)

    private func model(createdID: UUID = UUID(),
                       lookup: CalendarEvent? = nil) -> AIAssistantModel {
        AIAssistantModel(
            execute: { _ in .success(.createdEvent(createdID)) },
            eventByID: { _ in lookup })
    }

    private func draft(startDate: Date) -> AICreateEventDraft {
        AICreateEventDraft(title: "写周报", startDate: startDate, repeatRule: .never)
    }

    /// 落点是"别的日子" → 文案必须带上具体日期，并把该日期交给「去看看」按钮
    func testCreateOnAnotherDayReportsTheDateAndOffersJump() {
        let m = model()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        m.draft = draft(startDate: tomorrow)
        m.create(m.draft!)
        XCTAssertEqual(m.completedOffDay, tomorrow,
                       "跨日创建必须把目标日交给「去看看」，否则按钮不出现（真机反馈过的坑）")
        XCTAssertFalse(m.completedMessage?.isEmpty ?? true, "跨日创建必须说明是哪一天")
        XCTAssertNil(m.draft, "创建完成后草稿应清掉")
        XCTAssertTrue(m.inputFocused, "创建后应把焦点还给输入框")
    }

    /// 落点是今天 → 普通成功文案，且**不**给跳转日（否则会多出一个「去看看」）
    func testCreateOnSameDayDoesNotOfferJump() {
        let m = model()
        m.draft = draft(startDate: Date())
        m.create(m.draft!)
        XCTAssertNil(m.completedOffDay, "当天创建不该出现跳转按钮")
        XCTAssertFalse(m.completedMessage?.isEmpty ?? true)
        XCTAssertEqual(m.input, "", "创建后输入框应清空")
    }

    /// 执行失败 → 走行内错误，而不是成功文案
    func testCreateFailureShowsInlineError() {
        let m = AIAssistantModel(
            execute: { _ in .failure(AICommandError(kind: .notFound, message: "测试用错误")) },
            eventByID: { _ in nil })
        m.draft = draft(startDate: now)
        m.create(m.draft!)
        XCTAssertEqual(m.inlineError, "测试用错误")
        XCTAssertNil(m.completedMessage)
    }
}
