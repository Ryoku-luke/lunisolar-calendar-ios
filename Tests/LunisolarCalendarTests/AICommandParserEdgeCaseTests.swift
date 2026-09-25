import XCTest
import LunarCore
@testable import LunisolarCalendarApp

// MARK: - AI 解析边界回归
//
// 两处真机暴露过的问题：
// 1. 修改意图的日期词被消费两次 —— 整句日期检测（按「后天 > 明天 > 今天」优先级抓词，
//    不看位置）会把「改到」之后的**新日期**当成定位日：
//    「把今天的会改到明天」→ 定位日取成明天、关键词里残留「今天的」→ 必然 notFound；
//    「把3点的会改到明天」→ 定位到明天 3 点，若那天恰有同名日程就会改错；
//    「改到今天」更是完全不生效（旧 parseShortDayWord 只认明天/后天）。
// 2. 「凌晨/晚上 12 点」被算成正午 12:00（applyTimeWord 在 hour == 12 时原样返回）。

final class AICommandParserEdgeCaseTests: XCTestCase {

    private let cal = Calendar(identifier: .gregorian)

    /// 固定「现在」= 2026-09-24 08:00，避免测试随真实时间漂移
    private var now: Date {
        var dc = DateComponents()
        dc.year = 2026; dc.month = 9; dc.day = 24; dc.hour = 8; dc.minute = 0
        return cal.date(from: dc)!
    }

    private func command(_ input: String, file: StaticString = #filePath, line: UInt = #line) -> AIStructuredCommand? {
        switch AICommandParser.parse(input, baseDate: now) {
        case .success(let c):
            return c
        case .failure(let e):
            XCTFail("解析失败：\(e.message)", file: file, line: line)
            return nil
        }
    }

    /// 相对「今天」的天数偏移（0 = 今天）
    private func dayOffset(_ d: Date) -> Int {
        cal.dateComponents([.day],
                           from: cal.startOfDay(for: now),
                           to: cal.startOfDay(for: d)).day ?? -999
    }

    // MARK: 1. 修改意图：定位日与新日期分别取自「改到」两侧

    func testCriteriaDayComesFromHeadAndNewDayFromTail() throws {
        guard case .updateEvent(let d)? = command("把今天的会改到明天") else {
            return XCTFail("应解析为修改意图")
        }
        XCTAssertEqual(dayOffset(d.criteria.day), 0, "定位日应为「今天」")
        XCTAssertEqual(d.criteria.keyword, "会", "关键词里不得残留日期词")
        XCTAssertEqual(dayOffset(d.newStartDate), 1, "新日期应为「明天」")
    }

    func testClockOnlyInHeadKeepsCriteriaDay() throws {
        guard case .updateEvent(let d)? = command("把3点的会改到明天") else {
            return XCTFail("应解析为修改意图")
        }
        XCTAssertEqual(dayOffset(d.criteria.day), 0, "head 无日期词 → 定位日回落今天")
        XCTAssertEqual(d.criteria.timeHint?.hour, 3, "定位时刻取 head 的 3 点")
        XCTAssertEqual(dayOffset(d.newStartDate), 1)
        XCTAssertEqual(cal.component(.hour, from: d.newStartDate), 3, "新时间沿用定位时刻")
    }

    func testUpdateToTodayIsNotIgnored() throws {
        guard case .updateEvent(let d)? = command("把后天的会改到今天") else {
            return XCTFail("应解析为修改意图")
        }
        XCTAssertEqual(dayOffset(d.criteria.day), 2, "定位日应为「后天」")
        XCTAssertEqual(dayOffset(d.newStartDate), 0, "「改到今天」必须真的落到今天")
    }

    func testTailClockOverridesHeadClock() throws {
        guard case .updateEvent(let d)? = command("把明天3点的会改到后天5点") else {
            return XCTFail("应解析为修改意图")
        }
        XCTAssertEqual(dayOffset(d.criteria.day), 1, "定位日应为「明天」")
        XCTAssertEqual(d.criteria.timeHint?.hour, 3, "定位时刻应为 3 点")
        XCTAssertEqual(dayOffset(d.newStartDate), 2, "新日期应为「后天」")
        XCTAssertEqual(cal.component(.hour, from: d.newStartDate), 5, "新时刻应取 tail 的 5 点")
    }

    /// 删除意图不受影响（它只有一处日期语境）
    func testDeleteCriteriaStillUsesSentenceDate() throws {
        guard case .deleteEvent(let d)? = command("删掉明天的例会") else {
            return XCTFail("应解析为删除意图")
        }
        XCTAssertEqual(dayOffset(d.criteria.day), 1)
        XCTAssertEqual(d.criteria.keyword, "例会")
    }

    // MARK: 2. 12 点的时段词换算

    func testEarlyMorningTwelveIsMidnightNotNoon() throws {
        guard case .createEvent(let d)? = command("明天凌晨12点睡觉") else {
            return XCTFail("应解析为创建意图")
        }
        XCTAssertEqual(dayOffset(d.startDate), 1)
        XCTAssertEqual(cal.component(.hour, from: d.startDate), 0, "凌晨12点应为 00:00")
    }

    func testLateNightTwelveRollsToNextMidnight() throws {
        guard case .createEvent(let d)? = command("今天晚上12点睡觉") else {
            return XCTFail("应解析为创建意图")
        }
        XCTAssertEqual(dayOffset(d.startDate), 1, "24 点应规整为次日 00:00")
        XCTAssertEqual(cal.component(.hour, from: d.startDate), 0)
    }

    func testNoonTwelveStillNoon() throws {
        guard case .createEvent(let d)? = command("今天中午12点吃饭") else {
            return XCTFail("应解析为创建意图")
        }
        XCTAssertEqual(dayOffset(d.startDate), 0)
        XCTAssertEqual(cal.component(.hour, from: d.startDate), 12, "中午12点保持 12:00")
    }

    func testAfternoonTwelveIsUnchanged() throws {
        guard case .createEvent(let d)? = command("明天下午3点开会") else {
            return XCTFail("应解析为创建意图")
        }
        XCTAssertEqual(dayOffset(d.startDate), 1)
        XCTAssertEqual(cal.component(.hour, from: d.startDate), 15, "下午3点 = 15:00（回归）")
    }
}
