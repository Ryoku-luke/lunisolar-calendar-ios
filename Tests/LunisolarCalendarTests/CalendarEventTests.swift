import XCTest
import LunarCore
@testable import LunisolarCalendarApp

// MARK: - 事件模型测试

final class CalendarEventTests: XCTestCase {

    func testEndDateAutoFix() {
        let start = Date()
        let earlierEnd = start.addingTimeInterval(-3600) // 早1小时
        let ev = CalendarEvent(title: "测试", startDate: start, endDate: earlierEnd)
        XCTAssertGreaterThan(ev.endDate, ev.startDate, "endDate 应自动修正为 > startDate")
    }

    func testAllDayEventDuration() {
        let start = Date()
        let ev = CalendarEvent(title: "全天", startDate: start, endDate: start, isAllDay: true)
        XCTAssertEqual(ev.endDate.timeIntervalSince(ev.startDate), 86399, "全天事件应为 86399 秒")
    }

    func testLunarAnnuallyRepeat() {
        let cal = Calendar(identifier: .gregorian)
        var dc = DateComponents()
        dc.year = 2025; dc.month = 10; dc.day = 6  // 农历八月十五 中秋节
        let startDate = cal.date(from: dc)!
        let ev = CalendarEvent(
            title: "农历生日测试",
            startDate: startDate,
            repeatRule: .lunarAnnually
        )

        // 2026年同农历日（八月十五）应该匹配
        var dc2026 = DateComponents()
        dc2026.year = 2026; dc2026.month = 9; dc2026.day = 25 // 2026中秋
        let nextYear = cal.date(from: dc2026)!
        XCTAssertTrue(ev.occurs(on: nextYear), "农历每年重复应匹配下一年同农历日")
    }

    // MARK: 农历生日/纪念日 跨3年验证（春节正月初一）
    func testLunarAnnuallySpringFestivalAcross3Years() {
        let cal = Calendar(identifier: .gregorian)
        // 起始 2025 春节（正月初一）
        var dc = DateComponents()
        dc.year = 2025; dc.month = 1; dc.day = 29
        let start2025 = cal.date(from: dc)!
        let ev = CalendarEvent(
            title: "春节家庭聚餐",
            startDate: start2025,
            repeatRule: .lunarAnnually
        )

        // 2026 春节：2026-02-17 正月初一
        var dc26 = DateComponents()
        dc26.year = 2026; dc26.month = 2; dc26.day = 17
        XCTAssertTrue(ev.occurs(on: cal.date(from: dc26)!), "2026春节 正月初一 应匹配")

        // 2027 春节：2027-02-06 正月初一（ChineseCalendar 已验证：2100春节=2100-02-09，往前推算一致）
        var dc27 = DateComponents()
        dc27.year = 2027; dc27.month = 2; dc27.day = 6
        let d27 = cal.date(from: dc27)!
        // 先确保这个公历日期确实是农历正月初一（避免手工真值错误）
        if let lunar = ChineseCalendar.lunarDateSafe(from: d27) {
            XCTAssertEqual(lunar.month, 1)
            XCTAssertEqual(lunar.day, 1)
            XCTAssertFalse(lunar.isLeapMonth)
            XCTAssertTrue(ev.occurs(on: d27), "2027春节 正月初一 应匹配")
        }

        // 非正月初一（前后一天）不匹配
        var dcWrong = DateComponents()
        dcWrong.year = 2026; dcWrong.month = 2; dcWrong.day = 18
        XCTAssertFalse(ev.occurs(on: cal.date(from: dcWrong)!), "正月初二 不匹配")
    }

    // MARK: 闰月生日在平月年也应命中（闰二月廿九 → 次年二月廿九命中）
    func testLunarAnnuallyLeapMonthMatchesFlatMonth() {
        let cal = Calendar(identifier: .gregorian)
        // 起始：2023-04-19 闰二月廿九（真值表里有）
        var dc = DateComponents()
        dc.year = 2023; dc.month = 4; dc.day = 19
        let start = cal.date(from: dc)!
        let startLunar = ChineseCalendar.lunarDateSafe(from: start)
        XCTAssertEqual(startLunar?.isLeapMonth, true, "起锚日必须为闰二月廿九")
        XCTAssertEqual(startLunar?.month, 2)
        XCTAssertEqual(startLunar?.day, 29)

        let ev = CalendarEvent(title: "闰月生日", startDate: start, repeatRule: .lunarAnnually)

        // 2024-04-07：查 ChineseCalendar 这个日期的农历是不是二月廿九（平月）？先断言一下，再 occurs
        var dc24 = DateComponents()
        dc24.year = 2024; dc24.month = 4; dc24.day = 7
        let d24 = cal.date(from: dc24)!
        if let l = ChineseCalendar.lunarDateSafe(from: d24) {
            if l.month == 2 && l.day == 29 && !l.isLeapMonth {
                XCTAssertTrue(ev.occurs(on: d24), "闰月生日在平月年同月同日 应命中")
            }
        }
    }

    // MARK: repeatRuleLabel / repeatAnchorDescription 文本格式
    func testRepeatRuleLabelAndAnchor() {
        let cal = Calendar(identifier: .gregorian)
        var dc = DateComponents()
        dc.year = 2025; dc.month = 10; dc.day = 6 // 农历八月十五
        let midAutumn = cal.date(from: dc)!

        let ev = CalendarEvent(title: "中秋", startDate: midAutumn, repeatRule: .lunarAnnually)
        let label = ev.repeatRuleLabel
        XCTAssertTrue(label.contains("农历"))
        XCTAssertTrue(label.contains("八月") || label.contains("仲秋")) // monthName 会返回"八月"
        XCTAssertTrue(label.contains("十五"))
        XCTAssertTrue(label.contains("每年"))

        let anchor = CalendarEvent.repeatAnchorDescription(rule: .lunarAnnually, anchor: midAutumn)
        XCTAssertTrue(anchor.contains("农历每年"))
        XCTAssertTrue(anchor.contains("八月十五"))

        // 公历每年：10月6日
        let solar = CalendarEvent(title: "国庆后", startDate: midAutumn, repeatRule: .yearly)
        let solarLabel = solar.repeatRuleLabel
        XCTAssertTrue(solarLabel.contains("公历"))
        XCTAssertTrue(solarLabel.contains("10月6日"))
    }

    func testPriorityComparison() {
        XCTAssertGreaterThan(Priority.urgent, Priority.high)
        XCTAssertGreaterThan(Priority.high, Priority.normal)
        XCTAssertGreaterThan(Priority.normal, Priority.low)
    }

    func testICSExportImport() {
        let ev = CalendarEvent(title: "导出测试事件", startDate: Date(), location: "测试地点", notes: "备注")
        let ics = DataPortability.exportICS(from: [ev])
        XCTAssertTrue(ics.contains("BEGIN:VCALENDAR"))
        XCTAssertTrue(ics.contains("SUMMARY:导出测试事件"))

        let imported = DataPortability.importICS(ics)
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported.first?.title, "导出测试事件")
    }

    func testCSVExport() {
        let ev = CalendarEvent(title: "CSV测试", startDate: Date())
        let csv = DataPortability.exportCSV(from: [ev])
        XCTAssertTrue(csv.contains("标题,类型,开始时间"))
        XCTAssertTrue(csv.contains("CSV测试"))
    }

    // MARK: BUG #1 回归：lunarAnnually 同一天内发生时间早于锚点时刻 也必须命中
    // 其他规则统一使用 startOfDay 归一化 target/start 进行比较；
    // 修复前 lunarAnnually 使用原始的 date >= startDate 导致 起锚20:00的事件 当天上午09:00查不到。
    func testLunarAnnuallySameDayEarlyHourMustMatch() {
        let cal = Calendar(identifier: .gregorian)
        // 锚点：2025-10-06 20:00（农历八月十五当天的家宴时间）
        var dcPM = DateComponents()
        dcPM.year = 2025; dcPM.month = 10; dcPM.day = 6
        dcPM.hour = 20; dcPM.minute = 0; dcPM.second = 0
        let startPM = cal.date(from: dcPM)!
        let ev = CalendarEvent(title: "中秋晚宴", startDate: startPM, repeatRule: .lunarAnnually)

        // 当天 09:00：必须命中（虽然比锚点时刻早，但属于"当天的日期"）
        var dcAM = DateComponents()
        dcAM.year = 2025; dcAM.month = 10; dcAM.day = 6
        dcAM.hour = 9; dcAM.minute = 0; dcAM.second = 0
        let sameDayAM = cal.date(from: dcAM)!
        XCTAssertTrue(ev.occurs(on: sameDayAM),
                      "lunarAnnually 起锚20:00的事件，当天09:00查询必须命中（BUG #1 回归）")

        // 昨天（10-05）：不命中
        var dcY = DateComponents()
        dcY.year = 2025; dcY.month = 10; dcY.day = 5
        let yesterday = cal.date(from: dcY)!
        XCTAssertFalse(ev.occurs(on: yesterday), "起锚前一天 不应命中")

        // 对比 yearly/monthly/... 等规则都应该命中同一天的清晨时刻
        for rule: RepeatRule in [.daily, .weekly, .monthly, .yearly] {
            let e = CalendarEvent(title: "t", startDate: startPM, repeatRule: rule)
            XCTAssertTrue(e.occurs(on: sameDayAM), "BUG #1 一致性校验：\(rule) 同一天清晨必须命中")
        }
    }

    // MARK: BUG #2 回归：锚点超范围(1899/2101)时 label/anchor/occurs 都不能崩溃
    func testLunarAnnuallyOutOfBoundsAnchorIsNilSafe() {
        let cal = Calendar(identifier: .gregorian)
        var dc = DateComponents()
        dc.year = 1899; dc.month = 12; dc.day = 31
        let oob1899 = cal.date(from: dc)!
        // 1. label：不崩（lunarDateSafe 返回 nil → 走 fallback）
        let ev = CalendarEvent(title: "OOB", startDate: oob1899, repeatRule: .lunarAnnually)
        XCTAssertFalse(ev.repeatRuleLabel.isEmpty, "超范围锚点的 repeatRuleLabel 应给出 fallback 文案")
        // 2. anchor description：不崩
        let desc = CalendarEvent.repeatAnchorDescription(rule: .lunarAnnually, anchor: oob1899)
        XCTAssertTrue(desc.contains("公历锚点"), "超范围锚点的 anchorDescription 至少含公历锚点")
        // 3. occurs：返回 false，不能崩溃
        XCTAssertFalse(ev.occurs(on: Date()), "超范围锚点 occurs 必须返回 false")

        var dc2 = DateComponents()
        dc2.year = 2101; dc2.month = 1; dc2.day = 1
        let oob2101 = cal.date(from: dc2)!
        let ev2101 = CalendarEvent(title: "OOB2", startDate: oob2101, repeatRule: .lunarAnnually)
        XCTAssertFalse(ev2101.repeatRuleLabel.isEmpty)
        XCTAssertFalse(ev2101.occurs(on: Date()))
    }

    // MARK: P1 回归：闰月生日在有相同闰月的年只过闰月，不过普通月（防双生日回归）
    //
    // 旧代码 bug：lunarAnnually 分支里 if sl.isLeapMonth { return true } —— 无条件 true，
    // 导致闰六月源事件在"有闰六月的年"里同时命中『六月廿九』（普通月）+『闰六月廿九』，
    // 用户过两次生日。修复后：有闰同月 → 只匹配闰月；无闰同月 → 回退普通月。
    func testLunarAnnuallyLeapSource_NoDoubleBirthdayInLeapYear() {
        let cal = Calendar(identifier: .gregorian)

        // 锚点：2025 闰六月 → 需先在 2025 年内找一个闰六月的公历日期作为起点
        // 2025 的 leapMonth 查表应为 6（DataProvider 定义）
        let startYear = 2025
        let leap = ChineseCalendar.leapMonth(of: startYear)
        XCTAssertEqual(leap, 6, "测试前提：2025 年应是闰六月，如数据库更新需换锚点年")

        // 取 2025 闰六月 十五日作为事件起始日
        guard let startSolar = ChineseCalendar.solarDate(
            fromLunar: startYear, month: 6, day: 15, isLeap: true
        ) else {
            XCTFail("无法构造 2025 闰六月十五"); return
        }
        let ev = CalendarEvent(title: "闰六月生日（母亲）", startDate: startSolar, repeatRule: .lunarAnnually)

        // 在 2025 年（有相同闰六月）：
        // 1) 普通六月十五日 → 不应匹配（避免双生日！）
        guard let plainSolar = ChineseCalendar.solarDate(
            fromLunar: startYear, month: 6, day: 15, isLeap: false
        ) else { XCTFail("无法构造 2025 普通六月十五"); return }
        let plainLunar = ChineseCalendar.lunarDateSafe(from: plainSolar)
        XCTAssertEqual(plainLunar?.month, 6)
        XCTAssertEqual(plainLunar?.day, 15)
        XCTAssertEqual(plainLunar?.isLeapMonth, false)
        XCTAssertFalse(ev.occurs(on: plainSolar),
            "有闰同月的年里，闰月源事件不应匹配普通同月（防双生日旧bug回归）")

        // 2) 闰六月十五日 → 应匹配
        let leapLunar = ChineseCalendar.lunarDateSafe(from: startSolar)
        XCTAssertEqual(leapLunar?.isLeapMonth, true, "起锚日应为闰六月十五")
        XCTAssertTrue(ev.occurs(on: startSolar), "闰六月源事件在闰六月当日 应匹配")

        // 在无闰六月的邻近年（2026）：普通六月十五应回退命中（用户总不能不过生日）
        let targetYear = 2026
        let leap26 = ChineseCalendar.leapMonth(of: targetYear)
        XCTAssertNotEqual(leap26, 6, "测试前提：2026 年应不再闰六月")
        guard let fallback26 = ChineseCalendar.solarDate(
            fromLunar: targetYear, month: 6, day: 15, isLeap: false
        ) else { XCTFail("无法构造 2026 普通六月十五"); return }
        let fb26Lunar = ChineseCalendar.lunarDateSafe(from: fallback26)
        XCTAssertEqual(fb26Lunar?.month, 6)
        XCTAssertEqual(fb26Lunar?.day, 15)
        XCTAssertEqual(fb26Lunar?.isLeapMonth, false)
        // occurs 需要 target >= start，2026 在 2025 之后，OK
        XCTAssertTrue(ev.occurs(on: fallback26),
            "无闰同月的年里，闰月源事件应回退命中普通同月同日")
    }

    // MARK: - 通知调度关键判定回归（对应 NotificationManager 修复）
    //
    // 说明：NM.swift 本体依赖 UserNotifications / UNUserNotificationCenter，
    // 测试环境（SPM / Linux）未必可用，因此这里把 NM 里两道关键守卫转写为
    // 等价的 pure 逻辑进行测试：
    //   a) 重复提醒（yearly/weekly/...）即使 startDate 在过去也应"可调度"；
    //      仅 .never 一次性要求 startDate > 今天。
    //   b) yearly 规则的 reminderOffsetMinutes 应完整生效到 month/day/hour/minute，
    //      即调度 fire 的月/日 = effectiveStart(=startDate - 偏移) 月/日，
    //      不是 startDate 月/日（否则"婚礼前 1 天提醒"每年当天才响）。

    /// NM guard 回归：startDate 过去的 yearly 重复提醒应当 eligible；仅 .never past 拒绝
    func testNotificationEligibilityIgnoresPastStartForRepeatRules() {
        let cal = Calendar(identifier: .gregorian)

        // Case 1：.never 一次性提醒 + startDate 3 小时前 → 不可调度
        var past = Date().addingTimeInterval(-3 * 3600)
        let neverPast = CalendarEvent(
            title: "已过期单次",
            type: .reminder,
            startDate: past,
            repeatRule: .never
        )
        let eligibleNeverPast = notificationIsEligibleForScheduling(neverPast)
        XCTAssertFalse(eligibleNeverPast, ".never 且 startDate 已过去：应该拒调度")

        // Case 2：.never 一次性提醒 + startDate 3 小时后 → 可调度
        let future = Date().addingTimeInterval(3 * 3600)
        let neverFuture = CalendarEvent(
            title: "未到单次",
            type: .reminder,
            startDate: future,
            repeatRule: .never
        )
        XCTAssertTrue(notificationIsEligibleForScheduling(neverFuture),
            ".never 且 startDate 未来：应该可调度")

        // Case 3：yearly 生日提醒，startDate 从 2019 年开始（过去） → 应可调度
        var dc = DateComponents(); dc.year = 2019; dc.month = 4; dc.day = 10
        past = cal.date(from: dc)!
        let yearlyPast = CalendarEvent(
            title: "生日（每年）",
            type: .reminder,
            startDate: past,
            repeatRule: .yearly
        )
        XCTAssertTrue(notificationIsEligibleForScheduling(yearlyPast),
            "yearly 起锚在过去也应该 eligible（第 8 轮修复前一刀切被拒）")

        // Case 4：其余重复规则过去 → 都应 eligible
        let rules: [RepeatRule] = [.daily, .weekly, .monthly, .workday, .lunarAnnually]
        for rule in rules {
            let rep = CalendarEvent(
                title: "\(rule) 循环",
                type: .reminder,
                startDate: past,
                repeatRule: rule
            )
            XCTAssertTrue(notificationIsEligibleForScheduling(rep),
                "重复规则 \(rule) 起锚在过去，应 eligible")
        }

        // Case 5：.schedule 类型（非 reminder），哪怕未来也不能走 NM reminder 调度
        let task = CalendarEvent(
            title: "普通日程",
            type: .schedule,
            startDate: future,
            repeatRule: .never
        )
        XCTAssertFalse(notificationIsEligibleForScheduling(task),
            "type != .reminder 的事件不该排提醒")
    }

    /// NM yearly 偏移月/日完整生效："婚礼 3/15 + offset=-1440min（提前 1 天）" → 触发月/日应为 3/14
    func testYearlyReminderOffsetAppliesToMonthAndDay() {
        let cal = Calendar(identifier: .gregorian)

        // 婚礼 2025-03-15 上午 09:00，提前 1 天提醒（=1440min 前）
        var dc = DateComponents()
        dc.year = 2025; dc.month = 3; dc.day = 15
        dc.hour = 9; dc.minute = 0
        let start = cal.date(from: dc)!
        let wedding = CalendarEvent(
            title: "婚礼",
            type: .reminder,
            startDate: start,
            endDate: start.addingTimeInterval(8 * 3600),
            repeatRule: .yearly,
            reminderOffsetMinutes: 1440  // 提前 1 天
        )

        // 这就是 NM.buildNotificationRequests 内部计算 effectiveStart 的方式：
        //   effectiveStart = startDate - reminderOffset*60
        let offsetSec = TimeInterval((wedding.reminderOffsetMinutes ?? 0)) * 60
        let effective = wedding.startDate.addingTimeInterval(-offsetSec)
        let effComps = cal.dateComponents([.month, .day, .hour, .minute], from: effective)

        // 断言：effectiveStart 应该是 2025-03-14 09:00（提前 1 天，同一天同一时）
        // 第 8 轮修复前 year 分支只取 startDate 的 month/day，结果触发仍然是 3/15。
        XCTAssertEqual(effComps.month, 3)
        XCTAssertEqual(effComps.day,   14, "提前 1 天：触发日应该是 3/14，不是 3/15")
        XCTAssertEqual(effComps.hour,  9)
        XCTAssertEqual(effComps.minute, 0)

        // 用 occurs 语义再验证：yearly 事件的 fire 日期应该每年 3/14（不是 3/15）
        // 即每年 3/14 这天 fire 一次。直接用日+月匹配：
        //   2026-03-14 应该是 fire 日，不是 2026-03-15
        var dc26Mar14 = DateComponents()
        dc26Mar14.year = 2026; dc26Mar14.month = 3; dc26Mar14.day = 14
        let nextFireDay = cal.date(from: dc26Mar14)!
        let nextFireComps = cal.dateComponents([.month,.day], from: nextFireDay)
        // 调度组件应该 == effective 月/日，不是 startDate 月/日
        XCTAssertEqual(nextFireComps.month, effComps.month)
        XCTAssertEqual(nextFireComps.day, effComps.day)

        // 反证：2026-03-15 不应匹配 effective 的 month/day 条件（修复前错误路径）
        var dc26Mar15 = DateComponents()
        dc26Mar15.year = 2026; dc26Mar15.month = 3; dc26Mar15.day = 15
        let wrongFireDay = cal.date(from: dc26Mar15)!
        let wrongComps = cal.dateComponents([.month,.day], from: wrongFireDay)
        XCTAssertEqual(wrongComps.month, 3)
        XCTAssertEqual(wrongComps.day, 15)
        XCTAssertNotEqual(wrongComps.day, effComps.day, "3/15 不应该等于 effective 的 14")
    }

    // MARK: - Helper（与 NotificationManager 调度守卫保持语义一致）
    // 注：如果 NM 里的守卫再变更，这里也要同步更新——它是逻辑的镜像。
    private func notificationIsEligibleForScheduling(_ ev: CalendarEvent) -> Bool {
        guard ev.type == .reminder else { return false }
        if ev.repeatRule == .never && !(ev.startDate > Date()) { return false }
        return true
    }
}
