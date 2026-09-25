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

    // MARK: 3. 年份不再被静默忽略

    func testExplicitYearIsHonoured() throws {
        // 旧实现只取「M月D日」、年份沿用 base → 「2027年10月1日」被建成 2026-10-01，
        // 且标题里还残留「2027年」
        guard case .createEvent(let d)? = command("2027年10月1日 出国") else {
            return XCTFail("应解析为创建意图")
        }
        XCTAssertEqual(cal.component(.year, from: d.startDate), 2027)
        XCTAssertEqual(cal.component(.month, from: d.startDate), 10)
        XCTAssertEqual(cal.component(.day, from: d.startDate), 1)
        XCTAssertEqual(d.title, "出国", "年份也应从标题里剔除")
    }

    func testExplicitFutureYearIsNotRejectedAsPast() throws {
        guard case .createEvent(let d)? = command("2027年1月1日 元旦") else {
            return XCTFail("应解析为创建意图（2027 年仍在未来）")
        }
        XCTAssertEqual(cal.component(.year, from: d.startDate), 2027)
    }

    func testMonthDayWithoutYearStillUsesCurrentYear() throws {
        guard case .createEvent(let d)? = command("10月1日 出游") else {
            return XCTFail("应解析为创建意图")
        }
        XCTAssertEqual(cal.component(.year, from: d.startDate), 2026, "未写年份时沿用当前年")
    }

    // MARK: 4. 「下周三」的方向词

    /// now = 2026-09-24（周四）：最近的下一个周三是 09-30，
    /// 「下周三」应为再往后一周的 10-07（+13 天），且「下」要从标题里剔除
    func testNextWeekDirectionWordShiftsAndIsConsumed() throws {
        guard case .createEvent(let d)? = command("下周三 9点 开会") else {
            return XCTFail("应解析为创建意图")
        }
        XCTAssertEqual(dayOffset(d.startDate), 13, "下周三 = 最近周三再 +7 天")
        XCTAssertEqual(d.title, "开会", "方向词「下」不得残留")
        XCTAssertEqual(cal.component(.weekday, from: d.startDate), 4, "应落在周三")
    }

    func testThisWeekDirectionWordDoesNotShift() throws {
        guard case .createEvent(let d)? = command("本周三 9点 开会") else {
            return XCTFail("应解析为创建意图")
        }
        XCTAssertEqual(dayOffset(d.startDate), 6, "「本」不额外偏移")
        XCTAssertEqual(d.title, "开会")
    }

    // MARK: 5. 只有时段词、没有具体时刻时的定位关键词

    func testLoneTimeModifierIsStrippedFromKeyword() throws {
        // 旧实现 keyword = "下午的会议" → 永远匹配不到任何标题
        guard case .deleteEvent(let d)? = command("取消今天下午的会议") else {
            return XCTFail("应解析为删除意图")
        }
        XCTAssertEqual(d.criteria.keyword, "会议", "孤立时段修饰语应被剔除")
        XCTAssertEqual(dayOffset(d.criteria.day), 0)
    }

    /// 时段词是标题一部分时不得误伤（「下午茶」不是「下午的」）
    func testTitleContainingTimeWordIsNotDamaged() throws {
        guard case .deleteEvent(let d)? = command("删掉明天的下午茶") else {
            return XCTFail("应解析为删除意图")
        }
        XCTAssertEqual(d.criteria.keyword, "下午茶")
    }

    // MARK: 6. 「删了…」不再被降级成创建

    func testDeletePhrasingWithLeIsRecognised() throws {
        // 旧实现的删除标记只有 删掉/删除/取消 → 「删了明天的会议」落到创建分支，
        // 生成一条标题为「删了的会议」的垃圾日程
        guard case .deleteEvent(let d)? = command("删了明天的会议") else {
            return XCTFail("「删了」应识别为删除意图")
        }
        XCTAssertEqual(d.criteria.keyword, "会议")
        XCTAssertEqual(dayOffset(d.criteria.day), 1)
    }

    func testRemovePhrasingWithDiaoIsRecognised() throws {
        guard case .deleteEvent(let d)? = command("去掉明天的会议") else {
            return XCTFail("「去掉」应识别为删除意图")
        }
        XCTAssertEqual(d.criteria.keyword, "会议")
    }
}
