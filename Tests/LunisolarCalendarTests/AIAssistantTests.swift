import XCTest
import LunarCore
@testable import LunisolarCalendarApp

// MARK: - AI 助手链路测试（docs #35 / #36 / #47）
//
// 覆盖 Parser → Validator → AIAssistantService 三层：
// - 解析：日期/时间/标题/重复规则的识别与结构化错误；
// - 校验：标题、日期范围、一次性日程落在过去；
// - 执行：唯一写入路径是 EventService（AI 不得直连 EventStore）。

@MainActor
final class AIAssistantTests: XCTestCase {

    private let cal = Calendar(identifier: .gregorian)

    /// 固定"现在"= 2026-09-24 08:00（本地时区），避免测试随真实时间漂移
    private var now: Date {
        var dc = DateComponents()
        dc.year = 2026; dc.month = 9; dc.day = 24; dc.hour = 8; dc.minute = 0
        return cal.date(from: dc)!
    }

    private func draft(_ input: String, file: StaticString = #filePath, line: UInt = #line) -> AICreateEventDraft? {
        switch AICommandParser.parse(input, baseDate: now) {
        case .success(.createEvent(let d)):
            return d
        case .failure(let error):
            XCTFail("解析失败：\(error.message)", file: file, line: line)
            return nil
        }
    }

    private func parseError(_ input: String, file: StaticString = #filePath, line: UInt = #line) -> AICommandError? {
        switch AICommandParser.parse(input, baseDate: now) {
        case .success:
            XCTFail("预期解析失败，实际成功：\(input)", file: file, line: line)
            return nil
        case .failure(let error):
            return error
        }
    }

    // MARK: - 1. 解析

    func testParseTomorrowAfternoonReminder() throws {
        let d = try XCTUnwrap(draft("明天下午3点提醒我开会"))
        XCTAssertEqual(d.title, "开会")
        XCTAssertEqual(d.repeatRule, .never)
        let c = cal.dateComponents([.month, .day, .hour, .minute], from: d.startDate)
        XCTAssertEqual([c.month, c.day, c.hour, c.minute], [9, 25, 15, 0], "明天下午3点 → 09-25 15:00")
    }

    func testParseDayAfterTomorrowExplicitTime() throws {
        let d = try XCTUnwrap(draft("后天 14:30 见客户"))
        XCTAssertEqual(d.title, "见客户")
        let c = cal.dateComponents([.month, .day, .hour, .minute], from: d.startDate)
        XCTAssertEqual([c.month, c.day, c.hour, c.minute], [9, 26, 14, 30])
    }

    func testParseMonthDay() throws {
        let d = try XCTUnwrap(draft("9月25日 10:00 体检"))
        XCTAssertEqual(d.title, "体检")
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: d.startDate)
        XCTAssertEqual([c.year, c.month, c.day, c.hour, c.minute], [2026, 9, 25, 10, 0])
    }

    func testParseDailyRepeat() throws {
        let d = try XCTUnwrap(draft("每天晚上7点吃药"))
        XCTAssertEqual(d.title, "吃药")
        XCTAssertEqual(d.repeatRule, .daily)
        XCTAssertEqual(cal.component(.hour, from: d.startDate), 19)
    }

    func testParseWeeklyRepeat() throws {
        let d = try XCTUnwrap(draft("每周一 9点 例会"))
        XCTAssertEqual(d.title, "例会")
        XCTAssertEqual(d.repeatRule, .weekly)
        // 周一 = weekday 2
        XCTAssertEqual(cal.component(.weekday, from: d.startDate), 2)
    }

    /// 英文/日文日期词归一化（P1-6b 候选：英文时段词如 "3pm" 尚无「点/时」锚点，暂只保证日期归一化）
    func testNormalizeEnglishAndJapaneseDateWords() {
        XCTAssertTrue(AICommandParser.normalize("tomorrow meeting").contains("明天"))
        XCTAssertTrue(AICommandParser.normalize("today standup").contains("今天"))
        XCTAssertTrue(AICommandParser.normalize("day after tomorrow review").contains("后天"))
        XCTAssertTrue(AICommandParser.normalize("明後日 会議").contains("后天"))
        XCTAssertTrue(AICommandParser.normalize("明日 会議").contains("明天"))
    }

    func testParseErrorForEmptyInput() {
        XCTAssertEqual(parseError("   ")?.kind, .emptyInput)
    }

    func testParseErrorForMissingTitle() {
        // 只有日期+时间、没有标题 → 明确报错，绝不静默创建
        XCTAssertEqual(parseError("明天下午3点")?.kind, .missingTitle)
        XCTAssertEqual(parseError("后天 14:30 提醒我")?.kind, .missingTitle)
    }

    // MARK: - 2. 校验

    func testValidateRejectsPastOneOffEvent() {
        let past = AICreateEventDraft(
            title: "复盘会",
            startDate: cal.date(byAdding: .hour, value: -1, to: now)!,
            repeatRule: .never
        )
        let result = AICommandValidator.validate(.createEvent(past), now: now)
        guard case .failure(let error) = result else {
            return XCTFail("一次性日程落在过去应被拒绝")
        }
        XCTAssertEqual(error.kind, .inThePast)
    }

    func testValidateAllowsPastStartForRepeatingEvent() {
        // 重复日程允许过去起点（列表中会按重复规则继续出现）
        let past = AICreateEventDraft(
            title: "每周复盘",
            startDate: cal.date(byAdding: .day, value: -7, to: now)!,
            repeatRule: .weekly
        )
        guard case .success = AICommandValidator.validate(.createEvent(past), now: now) else {
            return XCTFail("重复日程的过去起点应被允许")
        }
    }

    func testValidateRejectsOutOfSupportedYearRange() {
        var dc = DateComponents()
        dc.year = 2199; dc.month = 1; dc.day = 1; dc.hour = 10
        let future = AICreateEventDraft(title: "很久以后", startDate: cal.date(from: dc)!, repeatRule: .never)
        guard case .failure(let error) = AICommandValidator.validate(.createEvent(future), now: now) else {
            return XCTFail("超出 1900–2100 应被拒绝")
        }
        XCTAssertEqual(error.kind, .outOfRange)
    }

    func testValidateTrimsAndClampsTitle() {
        let padded = AICreateEventDraft(
            title: "   开会   ",
            startDate: cal.date(byAdding: .day, value: 1, to: now)!,
            repeatRule: .never
        )
        guard case .success(.createEvent(let ok)) = AICommandValidator.validate(.createEvent(padded), now: now) else {
            return XCTFail("应通过校验")
        }
        XCTAssertEqual(ok.title, "开会")

        let long = AICreateEventDraft(
            title: String(repeating: "长", count: AICommandValidator.maxTitleLength + 20),
            startDate: cal.date(byAdding: .day, value: 1, to: now)!,
            repeatRule: .never
        )
        guard case .success(.createEvent(let clamped)) = AICommandValidator.validate(.createEvent(long), now: now) else {
            return XCTFail("超长标题应被截断而非拒绝")
        }
        XCTAssertEqual(clamped.title.count, AICommandValidator.maxTitleLength)
    }

    // MARK: - 3. 执行（唯一写入路径 = EventService；测试注入隔离 store，不碰真实 Documents）
    //
    // 注：EventStore 首次启动会 insertSampleData() 预置 4 条示例事件（App 里"总事件数 4"即此），
    // 因此这里的断言用"增量"而不是绝对条数。

    func testHandleCreatesEventThroughInjectedEventService() throws {
        let store = makeIsolatedEventStore()
        let before = store.events.count
        let service = AIAssistantService(eventService: EventService(store: store))

        guard case .success(let id) = service.handle("明天下午3点提醒我开会", now: now) else {
            return XCTFail("应创建成功")
        }
        let created = try XCTUnwrap(store.eventBy(idString: id.uuidString))
        XCTAssertEqual(created.title, "开会")
        XCTAssertEqual(store.events.count, before + 1, "应恰好新增 1 条")
        var dc = DateComponents()
        dc.year = 2026; dc.month = 9; dc.day = 25; dc.hour = 15; dc.minute = 0
        XCTAssertEqual(created.startDate, cal.date(from: dc)!, "明天下午3点 → 2026-09-25 15:00")
    }

    func testExecuteRejectsInvalidCommandWithoutWriting() {
        let store = makeIsolatedEventStore()
        let before = store.events.count
        let service = AIAssistantService(eventService: EventService(store: store))

        let past = AICreateEventDraft(
            title: "昨天的会",
            startDate: cal.date(byAdding: .day, value: -1, to: now)!,
            repeatRule: .never
        )
        guard case .failure(let error) = service.execute(.createEvent(past), now: now) else {
            return XCTFail("过去的一次性日程应被拒绝")
        }
        XCTAssertEqual(error.kind, .inThePast)
        XCTAssertEqual(store.events.count, before, "校验失败时不得写入任何数据")
    }

    func testParseFailureNeverReachesDataLayer() {
        let store = makeIsolatedEventStore()
        let before = store.events.count
        let service = AIAssistantService(eventService: EventService(store: store))

        guard case .failure = service.handle("明天下午3点", now: now) else {
            return XCTFail("缺标题应解析失败")
        }
        XCTAssertEqual(store.events.count, before)
    }
}
