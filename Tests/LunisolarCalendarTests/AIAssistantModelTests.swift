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

// MARK: - confirmDestructive：破坏性操作的确认执行（安全相关断言）

@MainActor
final class AIAssistantModelDestructiveTests: XCTestCase {

    /// 用引用盒记录"执行层到底收到了什么"（闭包是 escaping，不能用捕获的可变局部变量）
    private final class Box { var commands: [AIStructuredCommand] = [] }

    private let criteria = AIEventCriteria(
        day: Date(timeIntervalSince1970: 1_759_600_000),
        timeHint: DateComponents(hour: 15, minute: 0), keyword: "例会")

    private func deleteCommand() -> AIStructuredCommand {
        .deleteEvent(AIDeleteEventDraft(criteria: criteria))
    }

    /// **安全底线**：确认后命令必须真的送到执行层。
    /// 若哪天重构让这条路径漏掉执行，用户会以为删了、其实没删 —— 这比崩溃更难发现。
    func testConfirmationActuallyReachesTheExecutor() {
        let box = Box()
        let m = AIAssistantModel(execute: { cmd in
            box.commands.append(cmd); return .success(.deletedEvent(UUID()))
        }, eventByID: { _ in nil })
        m.pendingCommand = deleteCommand()
        m.confirmDestructive()

        XCTAssertEqual(box.commands.count, 1, "确认后必须调用执行层，且只调一次")
        XCTAssertEqual(box.commands.first, deleteCommand(), "送进执行层的必须是待确认的那条命令")
        XCTAssertNil(m.pendingCommand, "成功后待确认命令应清掉")
        XCTAssertNil(m.destructiveTarget, "成功后破坏性目标应清掉")
        XCTAssertFalse(m.completedMessage?.isEmpty ?? true, "成功后应给出回执（删了哪条）")
        XCTAssertNil(m.inlineError)
    }

    /// 没有待确认命令时**不得**执行任何东西（防止误触/重复点击造成意外删除）
    func testNoPendingCommandMeansNoExecution() {
        let box = Box()
        let m = AIAssistantModel(execute: { cmd in
            box.commands.append(cmd); return .success(.deletedEvent(UUID()))
        }, eventByID: { _ in nil })
        XCTAssertNil(m.pendingCommand)
        m.confirmDestructive()
        XCTAssertTrue(box.commands.isEmpty, "没有待确认命令时绝不能执行")
    }

    /// 执行失败 → 走行内错误，且**不**给出成功回执
    func testFailureShowsInlineErrorAndNoReceipt() {
        let m = AIAssistantModel(
            execute: { _ in .failure(AICommandError(kind: .notFound, message: "测试用失败")) },
            eventByID: { _ in nil })
        m.pendingCommand = deleteCommand()
        m.confirmDestructive()
        XCTAssertEqual(m.inlineError, "测试用失败")
        XCTAssertNil(m.completedMessage, "失败时不能出现成功回执")
    }
}

// MARK: - parse：解析入口（安全相关：未确认前绝不写数据）

@MainActor
final class AIAssistantModelParseTests: XCTestCase {

    private final class Box { var commands: [AIStructuredCommand] = [] }

    private func model(_ box: Box,
                       execute: @escaping (AIStructuredCommand) -> Result<AIExecutionOutcome, AICommandError>
                           = { _ in .success(.queried([])) }) -> AIAssistantModel {
        AIAssistantModel(execute: { cmd in box.commands.append(cmd); return execute(cmd) },
                         eventByID: { _ in nil },
                         resolveTarget: { _ in .failure(AICommandError(kind: .notFound, message: "不需要")) })
    }

    /// 解析失败（听不懂的话）→ 只给行内错误，**绝不**落到执行层
    func testUnparsableInputNeverReachesTheExecutor() {
        let box = Box()
        let m = model(box)
        m.input = "asdfghjkl 这不是一句话"
        m.parse()
        XCTAssertNotNil(m.inlineError, "听不懂时应有行内错误提示")
        XCTAssertTrue(box.commands.isEmpty, "解析失败绝不能调用执行层")
        XCTAssertNil(m.draft)
        XCTAssertNil(m.queryResults)
    }

    /// 创建类指令 → 只出**预览卡**，**不执行**（用户点确认前不能写数据）
    func testCreateCommandOnlyShowsPreviewAndDoesNotExecute() {
        let box = Box()
        let m = model(box)
        m.input = "明天下午3点提醒我开会"
        m.parse()
        XCTAssertNotNil(m.draft, "创建类指令应出预览卡")
        XCTAssertTrue(box.commands.isEmpty,
                      "创建必须等用户确认，解析阶段绝不能写数据（否则会出现未确认就建好的日程）")
    }

    /// 新一轮解析要清掉上一轮的残留（预览/结果/红字/待确认），否则旧内容会挂在新输入旁边
    func testParseClearsPreviousRoundState() {
        let box = Box()
        let m = model(box)
        m.draft = AICreateEventDraft(title: "旧的", startDate: Date(), repeatRule: .never)
        m.inlineError = "旧的红字"
        m.completedMessage = "旧的成功"
        m.pendingCommand = .deleteEvent(AIDeleteEventDraft(criteria: AIEventCriteria(
            day: Date(), timeHint: nil, keyword: "")))
        m.input = "asdfghjkl 这不是一句话"
        m.parse()
        XCTAssertNil(m.draft, "上一轮预览必须清掉")
        XCTAssertNil(m.completedMessage, "上一轮成功文案必须清掉")
        XCTAssertNotEqual(m.inlineError, "旧的红字", "上一轮红字必须清掉")
        XCTAssertNil(m.pendingCommand, "上一轮待确认命令必须清掉")
        XCTAssertFalse(m.inputFocused, "解析时应收起键盘，否则结果区被键盘挡住")
    }
}
