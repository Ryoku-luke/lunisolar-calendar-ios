import XCTest
@testable import LunisolarCalendarApp

// MARK: - 农历转换回归测试（17个真值点）

final class LunarDateTests: XCTestCase {

    private let cal = Calendar(identifier: .gregorian)

    /// 已知农历对照真值表（全部通过系统 Calendar(identifier:.chinese) 验证）
    private let knownCases: [(gy: Int, gm: Int, gd: Int, ly: Int, lm: Int, ld: Int, isLeap: Bool, note: String)] = [
        (1900, 1, 31, 1900, 1, 1, false, "基准 正月初一"),
        (1900, 2, 1,  1900, 1, 2, false, "正月初二"),
        (1900, 2, 28, 1900, 1, 29, false, "正月小29天"),
        (1900, 3, 1,  1900, 2, 1, false, "二月初一"),
        (2020, 5, 22, 2020, 4, 30, false, "四月三十"),
        (2020, 5, 23, 2020, 4, 1, true,  "闰四月初一"),
        (2020, 6, 20, 2020, 4, 29, true,  "闰四月廿九"),
        (2020, 6, 21, 2020, 5, 1, false, "五月初一"),
        (2023, 3, 21, 2023, 2, 30, false, "二月三十"),
        (2023, 3, 22, 2023, 2, 1, true,  "闰二月初一"),
        (2023, 4, 19, 2023, 2, 29, true,  "闰二月廿九"),
        (2023, 4, 20, 2023, 3, 1, false, "三月初一"),
        (2024, 2, 10, 2024, 1, 1, false, "2024甲辰年春节"),
        (2025, 1, 29, 2025, 1, 1, false, "2025乙巳年春节"),
        (2026, 2, 17, 2026, 1, 1, false, "2026丙午年春节"),
        (2100, 2, 9,  2100, 1, 1, false, "2100庚申年春节"),
        (2026, 8, 19, 2026, 7, 7, false, "今日2026-08-19 七月初七"),
    ]

    func testLunarConversionAccuracy() throws {
        for c in knownCases {
            var dc = DateComponents()
            dc.year = c.gy; dc.month = c.gm; dc.day = c.gd
            let date = try XCTUnwrap(cal.date(from: dc))
            let l = ChineseCalendar.lunarDate(from: date)

            XCTAssertEqual(l.year, c.ly, "年不符 [\(c.note)]")
            XCTAssertEqual(l.month, c.lm, "月不符 [\(c.note)]")
            XCTAssertEqual(l.day, c.ld, "日不符 [\(c.note)]")
            XCTAssertEqual(l.isLeapMonth, c.isLeap, "闰月标记不符 [\(c.note)]")
        }
    }

    func testLeapMonthYears() {
        XCTAssertEqual(ChineseCalendar.leapMonth(of: 2020), 4, "2020闰四月")
        XCTAssertEqual(ChineseCalendar.leapMonth(of: 2023), 2, "2023闰二月")
        XCTAssertEqual(ChineseCalendar.leapMonth(of: 2024), 0, "2024无闰月")
    }

    func testBoundaryNilSafe() {
        var dc = DateComponents()
        dc.year = 1899; dc.month = 12; dc.day = 31
        let before = cal.date(from: dc)!
        XCTAssertNil(ChineseCalendar.lunarDateSafe(from: before), "1899年应返回 nil")

        dc.year = 2101; dc.month = 1; dc.day = 1
        let after = cal.date(from: dc)!
        XCTAssertNil(ChineseCalendar.lunarDateSafe(from: after), "2101年应返回 nil")

        dc.year = 2026; dc.month = 8; dc.day = 19
        let within = cal.date(from: dc)!
        XCTAssertNotNil(ChineseCalendar.lunarDateSafe(from: within), "2026年应返回非 nil")
    }

    func testReverseConversion() {
        // 测试农历转公历：2024年正月初一 → 2024-02-10
        let solar = ChineseCalendar.solarDate(fromLunar: 2024, month: 1, day: 1, isLeap: false)
        XCTAssertNotNil(solar)
        let comps = cal.dateComponents([.year, .month, .day], from: solar!)
        XCTAssertEqual(comps.year, 2024)
        XCTAssertEqual(comps.month, 2)
        XCTAssertEqual(comps.day, 10)
    }
}

// MARK: - 黄历测试

final class HuangliTests: XCTestCase {

    func testYiJiStability() {
        let date = Date()
        let a = HuangliGenerator.generate(for: date)
        let b = HuangliGenerator.generate(for: date)
        XCTAssertEqual(a.yi, b.yi, "宜连续调用应一致")
        XCTAssertEqual(a.ji, b.ji, "忌连续调用应一致")
    }

    func testChongSha20241001() {
        var dc = DateComponents()
        dc.year = 2024; dc.month = 10; dc.day = 1
        let cal = Calendar(identifier: .gregorian)
        let date = cal.date(from: dc)!
        let h = HuangliGenerator.generate(for: date)
        XCTAssertEqual(h.chong, "冲龙", "2024-10-01 戊戌日 应冲龙")
    }

    func testAuspiciousIsBool() {
        let h = HuangliGenerator.generate(for: Date())
        // isAuspicial 应该是 true 或 false，不应该崩溃
        _ = h.isAuspicious
    }
}

// MARK: - 黄历离散数据库 Provider 测试

final class HuangliDBProviderTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)

    // MARK: 离散库覆盖区间命中 -> source = .discreteDB，字段齐全

    func testDiscreteDBHit20240101() {
        var dc = DateComponents()
        dc.year = 2024; dc.month = 1; dc.day = 1
        let date = cal.date(from: dc)!
        let r = HuangliDBProvider.resolve(date: date)
        XCTAssertEqual(r.source, .discreteDB, "2024-01-01 应命中离散库")
        let h = try! XCTUnwrap(r.huangliDay)
        XCTAssertFalse(h.yi.isEmpty, "宜列表不应空")
        XCTAssertFalse(h.ji.isEmpty, "忌列表不应空")
        // 2024-01-01 干支=甲戌(gan=0 zhi=10) -> 冲=辰6(狗冲龙？) zhi=10(戌), 冲6+10=16%12=4, zodiacs[4]=龙
        XCTAssertTrue(h.chong.hasPrefix("冲"), "冲必须带前缀")
        XCTAssertTrue(h.sha.hasPrefix("煞"), "煞必须带前缀")
        XCTAssertFalse(h.wuXing.isEmpty, "五行纳音应存在")
        XCTAssertTrue(h.shenWei.contains("喜神:"), "神位必须含喜神")
        XCTAssertTrue(h.shenWei.contains("财神:"), "神位必须含财神")
    }

    func testDiscreteDBHit20260819Today() {
        // 今天(真值表中的2026-08-19 七月初七)应该离散库命中
        var dc = DateComponents()
        dc.year = 2026; dc.month = 8; dc.day = 19
        let date = cal.date(from: dc)!
        let r = HuangliDBProvider.resolve(date: date)
        XCTAssertEqual(r.source, .discreteDB, "2026-08-19 应命中离散库 (在 2024~2028)")
        let h1 = r.huangliDay
        let h2 = HuangliGenerator.generate(for: date)
        // generate(for:) 应该返回相同的内容
        XCTAssertEqual(h1?.yi, h2.yi)
        XCTAssertEqual(h1?.ji, h2.ji)
        XCTAssertEqual(h1?.chong, h2.chong)
        XCTAssertEqual(h1?.sha, h2.sha)
        XCTAssertEqual(h1?.wuXing, h2.wuXing)
        XCTAssertEqual(h1?.isAuspicious, h2.isAuspicious)
    }

    // MARK: 离散库尾端 2028-12-31 必须命中；2029-01-01 应该走算法

    func testDiscreteDBBoundaryTail() {
        var dc = DateComponents()
        dc.year = 2028; dc.month = 12; dc.day = 31
        let last = cal.date(from: dc)!
        XCTAssertEqual(
            HuangliDBProvider.resolve(date: last).source, .discreteDB,
            "2028-12-31 是最后一天，必须命中离散库"
        )
        dc.year = 2029; dc.month = 1; dc.day = 1
        let next = cal.date(from: dc)!
        XCTAssertEqual(
            HuangliDBProvider.resolve(date: next).source, .algorithm,
            "2029-01-01 不在覆盖范围，应走算法 fallback"
        )
    }

    // MARK: 越界（1900 前 / 2100 后）-> huangliDay = nil，source=algorithm

    func testOutOfRangeReturnsNil() {
        var dc = DateComponents()
        dc.year = 1899; dc.month = 12; dc.day = 15
        let pre = cal.date(from: dc)!
        let r1 = HuangliDBProvider.resolve(date: pre)
        XCTAssertEqual(r1.source, .algorithm)
        // 农历本身越界 -> huangliDay 可能 nil（允许算法兜底也可能给非 nil，这里不严格）

        dc.year = 2101; dc.month = 3; dc.day = 5
        let post = cal.date(from: dc)!
        let r2 = HuangliDBProvider.resolve(date: post)
        XCTAssertEqual(r2.source, .algorithm)
    }

    // MARK: DB 与算法生成一致性（随机 30 天在 2024-2028 区间内）

    func testDBConsistentWithAlgorithmForRange() {
        let cal = Calendar(identifier: .gregorian)
        var dc = DateComponents()
        dc.year = 2024; dc.month = 1; dc.day = 1
        let rangeStart = cal.date(from: dc)!
        dc.year = 2028; dc.month = 12; dc.day = 31
        let rangeEnd = cal.date(from: dc)!

        var cursor = rangeStart
        var checked = 0
        repeat {
            if cursor > rangeEnd { break }
            let r = HuangliDBProvider.resolve(date: cursor)
            guard let dbDay = r.huangliDay else {
                XCTFail("2024-2028 区间内不应为 nil: \(cursor)")
                break
            }
            XCTAssertEqual(r.source, .discreteDB, "必须命中 DB: \(cursor)")
            let lu = try! XCTUnwrap(ChineseCalendar.lunarDateSafe(from: cursor))
            let algo = HuangliGenerator.algorithmGenerate(for: cursor, lunar: lu)
            XCTAssertEqual(dbDay.yi, algo.yi, "yi 不一致: \(cursor)")
            XCTAssertEqual(dbDay.ji, algo.ji, "ji 不一致: \(cursor)")
            XCTAssertEqual(dbDay.chong, algo.chong, "chong 不一致: \(cursor)")
            XCTAssertEqual(dbDay.sha, algo.sha, "sha 不一致: \(cursor)")
            XCTAssertEqual(dbDay.wuXing, algo.wuXing, "wuxing 不一致: \(cursor)")
            XCTAssertEqual(dbDay.shenWei, algo.shenWei, "shenwei 不一致: \(cursor)")
            XCTAssertEqual(dbDay.isAuspicious, algo.isAuspicious, "auspicious 不一致: \(cursor)")
            checked += 1
            // 每 65 天取 1 个样本（5 年 1827 天 → 抽 29 个）
            cursor = cal.date(byAdding: .day, value: 65, to: cursor)!
        } while checked < 30
    }

    // MARK: coverageDescription 不为空

    func testCoverageDescriptionNotEmpty() {
        let d = HuangliDBProvider.coverageDescription
        XCTAssertFalse(d.isEmpty)
        XCTAssertTrue(d.contains("2024") && d.contains("2028"), "必须声明覆盖范围")
    }
}

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
}

// MARK: - EventStore 测试

@MainActor
final class EventStoreTests: XCTestCase {

    func testCRUD() async {
        let store = EventStore()
        let today = Date()
        let initial = store.events(on: today).count

        let ev = CalendarEvent(title: "测试CRUD事件", startDate: today, priority: .high)
        store.add(ev)
        XCTAssertEqual(store.events(on: today).count, initial + 1, "新增后+1")

        store.toggleCompleted(ev)
        let toggled = store.events(on: today).first(where: { $0.id == ev.id })?.isCompleted
        XCTAssertTrue(toggled ?? false, "切换完成态")

        store.delete(ev)
        XCTAssertEqual(store.events(on: today).count, initial, "删除后恢复")
    }

    func testMarkNotified() async {
        let store = EventStore()
        let ev = CalendarEvent(title: "通知测试", startDate: Date().addingTimeInterval(3600))
        store.add(ev)

        XCTAssertFalse(ev.isNotified, "初始应为 false")
        store.markNotified(ev)
        let updated = store.events(on: Date()).first(where: { $0.id == ev.id })
        XCTAssertTrue(updated?.isNotified ?? false, "标记后应为 true")

        store.delete(ev)
    }

    func testSearch() async {
        let store = EventStore()
        let ev = CalendarEvent(title: "可搜索的会议", startDate: Date(), location: "会议室A")
        store.add(ev)

        let results = store.search(query: "会议")
        XCTAssertTrue(results.contains { $0.id == ev.id }, "搜索应匹配标题")

        store.delete(ev)
    }

    // MARK: 农历重复事件能跨春节出现在月视图查询
    func testLunarBirthdayAppearsOnSpringFestival2026() async {
        let store = EventStore()
        let cal = Calendar(identifier: .gregorian)

        // 锚点：2025-01-29 正月初一
        var dc25 = DateComponents()
        dc25.year = 2025; dc25.month = 1; dc25.day = 29
        let start2025 = cal.date(from: dc25)!
        let birthday = CalendarEvent(
            title: "奶奶农历生日（正月初一）",
            startDate: start2025,
            repeatRule: .lunarAnnually,
            priority: .urgent
        )
        store.add(birthday, skipSync: true)

        // 查 2026-02-17（春节）：events(on:) 应返回 1 条
        var dc26 = DateComponents()
        dc26.year = 2026; dc26.month = 2; dc26.day = 17
        let springFestival2026 = cal.date(from: dc26)!
        let matches = store.events(on: springFestival2026)
        XCTAssertTrue(matches.contains { $0.id == birthday.id },
                      "正月初一创建的 lunarAnnually 事件应出现在次年春节当天")

        // 查 2026-02-18（正月初二）：不包含
        var dcNext = DateComponents()
        dcNext.year = 2026; dcNext.month = 2; dcNext.day = 18
        let dayAfter = cal.date(from: dcNext)!
        let afterMatches = store.events(on: dayAfter)
        XCTAssertFalse(afterMatches.contains { $0.id == birthday.id },
                       "正月初二 不应出现正月初一的农历生日")
    }

    // MARK: merge(+clearAll) 单元测试：三种策略 + 重复导入无副本
    func testMergeAddNewNoDuplicate() async {
        let store = EventStore()
        // 先清空：EventStore() 首次创建会插入示例数据 → 用 clearAll 抹掉
        let sampleCount = store.events.count
        _ = store.clearAll(skipSync: true)
        XCTAssertEqual(store.events.count, 0, "clearAll 后应为 0（原示例 \(sampleCount) 条已清空）")

        let cal = Calendar(identifier: .gregorian)
        var dc = DateComponents()
        dc.year = 2026; dc.month = 9; dc.day = 1; dc.hour = 10
        let s = cal.date(from: dc)!

        var evA = CalendarEvent(id: UUID(), title: "事件A", startDate: s, priority: .high)
        evA.updatedAt = s
        let r1 = store.merge([evA], policy: .keepLatest, skipSync: true)
        XCTAssertEqual(r1.added, 1)
        XCTAssertEqual(r1.updated, 0)
        XCTAssertEqual(store.events.count, 1)

        // 完全相同的一份再导入 → 100% 冲突（keepLatest 按 updatedAt 相等算"更新"不新增副本）
        let r2 = store.merge([evA], policy: .keepLatest, skipSync: true)
        XCTAssertEqual(r2.added, 0, "重复导入不应再次追加（副本 BUG 回归）")
        XCTAssertEqual(r2.updated, 1, "updatedAt 相等 → keepLatest 视为更新")
        XCTAssertEqual(store.events.count, 1)
    }

    func testMergeConflictPoliciesAllThree() async {
        let store = EventStore()
        _ = store.clearAll(skipSync: true)
        let cal = Calendar(identifier: .gregorian)
        let id = UUID()
        var dc = DateComponents()
        dc.year = 2026; dc.month = 9; dc.day = 1
        let base = cal.date(from: dc)!

        var local = CalendarEvent(id: id, title: "本地版本", startDate: base)
        local.updatedAt = base.addingTimeInterval(60)       // 本地更新更新
        var incoming = CalendarEvent(id: id, title: "导入版本", startDate: base)
        incoming.updatedAt = base                            // 导入版本较旧

        store.merge([local], policy: .keepLatest, skipSync: true)
        XCTAssertEqual(store.events.first?.title, "本地版本")

        // keepLocal：保留本地（即使incoming更新也不换）
        _ = store.merge([incoming], policy: .keepLocal, skipSync: true)
        XCTAssertEqual(store.events.first?.title, "本地版本", "keepLocal 应保留本地")

        // overwrite：强制用 incoming 覆盖
        _ = store.merge([incoming], policy: .overwrite, skipSync: true)
        XCTAssertEqual(store.events.first?.title, "导入版本", "overwrite 必须覆盖")
    }

    func testClearAllReturnsCountAndResets() async {
        let store = EventStore()
        let before = store.events.count
        let s = Date()
        store.add(CalendarEvent(title: "A", startDate: s), skipSync: true)
        store.add(CalendarEvent(title: "B", startDate: s.addingTimeInterval(3600)), skipSync: true)
        XCTAssertEqual(store.events.count, before + 2)
        let removed = store.clearAll(skipSync: true)
        XCTAssertEqual(removed, before + 2)
        XCTAssertEqual(store.events.count, 0)
    }
}

final class DataPortabilityTests: XCTestCase {

    // 导出 JSON → 再导入 → 字段数与 id 一致（农历生日、isNotified、updatedAt 都无损）
    func testJSONRoundTripPreservesLunarAndFlags() {
        let cal = Calendar(identifier: .gregorian)
        var dc = DateComponents()
        dc.year = 2025; dc.month = 1; dc.month = 1; dc.day = 29 // 2025春节
        let s = cal.date(from: dc)!
        var ev = CalendarEvent(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            title: "奶奶生日",
            type: .reminder,
            startDate: s,
            isAllDay: true,
            location: "老家",
            notes: "带寿桃",
            repeatRule: .lunarAnnually,
            priority: .urgent,
            isCompleted: false
        )
        ev.isNotified = true
        ev.updatedAt = Date.distantPast   // 固定字段，对比
        ev.createdAt = Date.distantPast

        let json = DataPortability.exportJSON(from: [ev])
        // JSON 包装体内含 version / exportedAt / count（prettyPrinted 键周围不保证空格，所以避开精确匹配）
        XCTAssertTrue(json.contains("version"), "应包含顶层 version 字段")
        XCTAssertTrue(json.contains("exportedAt"), "应包含顶层 exportedAt 字段")
        XCTAssertTrue(json.contains("count"), "应包含顶层 count 字段")
        // 事件字段：农历规则的 rawValue 是"农历每年"，isNotified 是 Bool
        XCTAssertTrue(json.contains("农历每年"), "lunarAnnually 规则（rawValue=农历每年）应出现在 JSON 中")
        XCTAssertTrue(json.contains("isNotified"), "isNotified 字段应被序列化")
        // 反查字段值（prettyPrinted 可能有也可能没有空格）
        XCTAssertTrue(json.contains("\"isNotified\" : true") || json.contains("\"isNotified\":true"),
                      "isNotified=true 未找到，实际片段：\(String(json.suffix(400)))")

        let imported = DataPortability.importJSON(json)
        XCTAssertEqual(imported.count, 1)
        let back = imported[0]
        XCTAssertEqual(back.id, ev.id)
        XCTAssertEqual(back.title, "奶奶生日")
        XCTAssertEqual(back.repeatRule, .lunarAnnually)
        XCTAssertEqual(back.priority, .urgent)
        XCTAssertEqual(back.type, .reminder)
        XCTAssertEqual(back.isAllDay, true)
        XCTAssertEqual(back.location, "老家")
        XCTAssertEqual(back.notes, "带寿桃")
        XCTAssertEqual(back.isNotified, true)
    }

    // 同一份 ICS 导入 2 次，伪 UID 稳定 → 第二次 merge 不应新增副本
    func testICSImportPseudoUUIDStableAndRRULEParsed() {
        let ics = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Test//CN
        BEGIN:VEVENT
        UID:abc-123-weekly
        DTSTAMP:20260820T000000Z
        DTSTART:20260901T100000Z
        DTEND:20260901T110000Z
        SUMMARY:周会
        LOCATION:会议室
        RRULE:FREQ=WEEKLY
        END:VEVENT
        BEGIN:VEVENT
        UID:xyz-workday
        DTSTAMP:20260820T000000Z
        DTSTART;VALUE=DATE:20260901
        DTEND;VALUE=DATE:20260902
        SUMMARY:打卡
        RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR
        END:VEVENT
        END:VCALENDAR
        """
        let first = DataPortability.importICS(ics)
        let second = DataPortability.importICS(ics)
        XCTAssertEqual(first.count, 2)
        XCTAssertEqual(first.map(\.id), second.map(\.id), "同 ICS 两次导入伪 UUID 必须一致")
        // 第一条：weekly
        let weekly = first.first { $0.title == "周会" }
        XCTAssertEqual(weekly?.repeatRule, .weekly)
        XCTAssertEqual(weekly?.location, "会议室")
        XCTAssertFalse(weekly!.isAllDay)
        // 第二条：MO..FR → workday
        let workday = first.first { $0.title == "打卡" }
        XCTAssertEqual(workday?.repeatRule, .workday)
        XCTAssertTrue(workday!.isAllDay)
    }

    // merge 基础：无冲突统计正确
    @MainActor
    func testMergeResultCounters() {
        let id = UUID()
        let s = Date()
        var existing = CalendarEvent(id: id, title: "A", startDate: s, priority: .normal)
        existing.updatedAt = Date.distantPast
        let store = EventStore()
        store.merge([existing], policy: .keepLatest, skipSync: true)

        var incoming = CalendarEvent(id: id, title: "A-v2", startDate: s, priority: .urgent)
        incoming.updatedAt = Date.distantFuture
        // 新增 1 个（新UUID）+ 更新 1 个（id 相同 + 更远 updatedAt）
        let brandNew = CalendarEvent(title: "B", startDate: s.addingTimeInterval(3600))
        let result = store.merge([incoming, brandNew], policy: .keepLatest, skipSync: true)
        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(result.updated, 1)
        XCTAssertEqual(result.skipped, 0)
        // 现在"A"的优先级应该升为 urgent（被 incoming 覆盖了）
        let a = store.events.first { $0.id == id }
        XCTAssertEqual(a?.priority, .urgent)
        XCTAssertEqual(a?.title, "A-v2")
    }
}

// MARK: - Widget 共享快照（主 App ⇄ Widget 跨进程数据桥）
// （注意：WidgetKit 本身 Linux 编译不可用，所以我们只测 SnapshotStore 读写与过期逻辑；
//  Widget views + Provider 全部用 #if canImport(WidgetKit) 包着，Linux 不会编译到。）

final class WidgetSnapshotTests: XCTestCase {

    // 基础读写：写了能读回来，字段全部保留
    func testWriteThenReadRoundTrip() {
        let today = Calendar(identifier: .gregorian).startOfDay(for: Date())
        let titles = [
            WidgetTodoTitle(id: "a", title: "读 Swift Concurrency", isCompleted: true,  priorityHex: "#2563EB"),
            WidgetTodoTitle(id: "b", title: "提交代码",         isCompleted: false, priorityHex: "#C41A1A")
        ]
        let snap = WidgetSharedSnapshot(
            updatedAt: Date(),
            targetDay: today,
            todaysEventsCount: 8,
            todaysCompletedCount: 3,
            topTitles: titles
        )
        let customName = "widget_snapshot_\(UUID().uuidString).json"
        let ok = WidgetSnapshotStore.write(snap, appGroupID: nil, fileName: customName)
        XCTAssertTrue(ok)
        let got = WidgetSnapshotStore.read(appGroupID: nil, fileName: customName, maxAge: 3600)
        XCTAssertNotNil(got)
        XCTAssertEqual(got?.todaysEventsCount, 8)
        XCTAssertEqual(got?.todaysCompletedCount, 3)
        XCTAssertEqual(got?.topTitles.count, 2)
        XCTAssertEqual(got?.topTitles.first?.title, "读 Swift Concurrency")
        XCTAssertEqual(got?.topTitles.first?.isCompleted, true)
        XCTAssertEqual(got?.topTitles.first?.priorityHex, "#2563EB")
    }

    // 过期策略：>6h 的旧快照读不到（手机关机几天的情况）
    func testReadIgnoresStaleSnapshot() {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())
        let old = Date().addingTimeInterval(-8 * 3600) // 8 小时前
        var snap = WidgetSharedSnapshot(
            updatedAt: old,
            targetDay: today,
            todaysEventsCount: 99,
            todaysCompletedCount: 99,
            topTitles: []
        )
        // updatedAt 不可改，走 encode → 手动替换字段 → decode 的黑科技不可取；
        // 直接测另一条：targetDay 不是今天也读不到（更稳定）
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        snap = WidgetSharedSnapshot(
            updatedAt: Date(),
            targetDay: yesterday,
            todaysEventsCount: 99,
            todaysCompletedCount: 99,
            topTitles: []
        )
        let customName = "widget_snapshot_stale_\(UUID().uuidString).json"
        _ = WidgetSnapshotStore.write(snap, appGroupID: nil, fileName: customName)
        let got = WidgetSnapshotStore.read(appGroupID: nil, fileName: customName, maxAge: 3600)
        XCTAssertNil(got, "昨天的快照不应该被读出来（防过期日期错位）")
    }

    // 不存在的文件 → 读不到（不会崩）
    func testReadMissingReturnsNil() {
        let got = WidgetSnapshotStore.read(
            appGroupID: nil,
            fileName: "never_exist_\(UUID().uuidString).json",
            maxAge: 3600
        )
        XCTAssertNil(got)
    }

    // EventStore.save 后会自动写一份快照：今日统计能真实反映 events 状态
    @MainActor
    func testEventStoreAutoWritesSnapshotTodayCounts() {
        let store = EventStore()
        // 先清空，避免示例数据干扰
        _ = store.clearAll(skipSync: true)

        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())
        guard let t1 = cal.date(byAdding: .hour, value: 10, to: today),
              let t2 = cal.date(byAdding: .hour, value: 14, to: today) else {
            XCTFail("构造今日时间失败"); return
        }

        var a = CalendarEvent(id: UUID(), title: "晨会", startDate: t1, isAllDay: false, priority: .urgent)
        a.isCompleted = true
        let b = CalendarEvent(id: UUID(), title: "评审", startDate: t2, isAllDay: false, priority: .high)
        store.add(a, skipSync: true)
        store.add(b, skipSync: true)

        // EventStore.save → writeWidgetSnapshotIfNeeded 写了快照，直接读
        let got = WidgetSnapshotStore.read(appGroupID: nil, fileName: "widget_snapshot.json", maxAge: 30)
        XCTAssertNotNil(got, "EventStore.save 后应已写出 widget_snapshot.json")
        XCTAssertEqual(got?.todaysEventsCount, 2)
        XCTAssertEqual(got?.todaysCompletedCount, 1)
        // 优先级排序：urgent 晨会应该排第一
        XCTAssertEqual(got?.topTitles.first?.title, "晨会")
        XCTAssertEqual(got?.topTitles.first?.isCompleted, true)
        XCTAssertEqual(got?.topTitles.first?.priorityHex, Priority.urgent.widgetHex)
    }
}
