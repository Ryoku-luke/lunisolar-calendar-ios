import XCTest
@testable import LunisolarCalendarApp

// MARK: - 标题保真：解析器不得改写/吞掉标题里的内容
//
// 起因（2026-10-07）：UI 用例 testFlow3c 用标题 "AI日程-<时间戳>" 创建日程，回日历按该标题找不到。
// 手动路径（标题「测试」，不含数字）正常 → 说明问题可能与**标题里的长数字串**有关：
// 解析器会扫描数字做日期/时刻识别，若把标题里的数字也吃掉，标题就不再等于用户说的那句。
// 这个单测把输入法因素排除掉，直接钉住"标题保真"。

final class AICommandParserTitleTests: XCTestCase {

    private func createDraft(from text: String) throws -> AICreateEventDraft {
        switch AICommandParser.parse(text) {
        case .success(.createEvent(let d)): return d
        case .success(let other): XCTFail("应解析为创建指令，实际 \(other)"); throw XCTSkip("见上")
        case .failure(let e): XCTFail("解析失败：\(e.message)"); throw XCTSkip("见上")
        }
    }

    /// 标题里的**长数字串**（时间戳）必须原样保留 —— UI 用例正是按它回查的
    func testTitleKeepsLongDigitRun() throws {
        let text = "今天16点50分提醒我AI日程-1791359398"
        let d = try createDraft(from: text)
        XCTAssertEqual(d.title, "AI日程-1791359398",
                       "标题必须保真；若这里失败，说明解析器把标题里的数字当成了日期/时刻信息")
    }

    /// 对照：标题不含数字时应当正常（手动路径正是这种）
    func testPlainTitleIsPreserved() throws {
        let d = try createDraft(from: "今天17点提醒我测试")
        XCTAssertEqual(d.title, "测试")
    }

    /// 再对照：短数字标题（例如「会议2」）也不该被吃掉
    func testShortDigitInTitleIsPreserved() throws {
        let d = try createDraft(from: "明天下午3点提醒我会议2")
        XCTAssertEqual(d.title, "会议2")
    }
}
