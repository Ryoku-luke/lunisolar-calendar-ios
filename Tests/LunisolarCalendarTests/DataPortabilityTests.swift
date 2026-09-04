import XCTest
@testable import LunisolarCalendarApp

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
        let store = makeIsolatedEventStore()
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

    // MARK: P3 回归：ICS PRIORITY 对称映射
    //
    // 旧实现 exportICS 把 .normal/.low 都写成 9，而 importICS 把 7-9 都解析成 .low，
    // round-trip 后 .normal 会被降级为 .low（数据损失）。新映射必须严格对称：
    //   urgent→1  high→3  normal→5  low→7

    func testICSPriorityRoundTripSymmetric() {
        let cal = Calendar(identifier: .gregorian)
        var dc = DateComponents()
        dc.year = 2026; dc.month = 9; dc.day = 1; dc.hour = 10
        let start = cal.date(from: dc)!

        for prio in Priority.allCases {
            var ev = CalendarEvent(
                id: UUID(),
                title: "优先级测试-\(prio.uiLabel)",
                type: .schedule,
                startDate: start,
                endDate: start.addingTimeInterval(3600),
                priority: prio
            )
            let ics = DataPortability.exportICS(from: [ev])
            let parsed = DataPortability.importICS(ics)
            XCTAssertEqual(parsed.count, 1)
            XCTAssertEqual(parsed[0].priority, prio,
                           "ICS round-trip 优先级不对称：\(prio) → \(parsed[0].priority)")
        }
    }

    // MARK: P3 回归：ICS TEXT 转义对 \r\n / \r 的处理
    //
    // 旧 escapeICS 只转 \n，标题/备注里带 \r\n 或单独 \r 时：
    //   - \r\n 会被转成 \r\n（\r 原样），折叠行解析后可能出现残余 \r；
    //   - round-trip 后字符串出现多余换行或不可见 \r。
    // RFC 5545 §3.3.11 要求所有行尾归一为字面 \n。

    func testICSTextEscapeNormalizesCRLFAndCR() {
        let cal = Calendar(identifier: .gregorian)
        var dc = DateComponents()
        dc.year = 2026; dc.month = 9; dc.day = 1; dc.hour = 10
        let start = cal.date(from: dc)!

        // 标题含 \r\n，备注含单独 \r
        var ev = CalendarEvent(
            id: UUID(),
            title: "第一行\r\n第二行",
            type: .note,
            startDate: start,
            endDate: start.addingTimeInterval(3600),
            notes: "备注A\r备注B\r\n备注C"
        )
        let ics = DataPortability.exportICS(from: [ev])
        // 注意：ICS 行分隔符本身是 \r\n（RFC 5545），所以整个 ics 字符串含 \r 是正常的。
        // 真正的不变量是：SUMMARY/DESCRIPTION 的值中不能含未转义的 \r。
        // 这里通过 round-trip 后解析结果不含 \r 来间接保证 escapeICS 已归一化行尾。

        let parsed = DataPortability.importICS(ics)
        XCTAssertEqual(parsed.count, 1)
        // round-trip 后标题与备注中不应残留 \r
        XCTAssertFalse(parsed[0].title.contains("\r"),
                       "标题 round-trip 后不应含残留 \\r，实际：\(parsed[0].title)")
        XCTAssertFalse((parsed[0].notes ?? "").contains("\r"),
                       "备注 round-trip 后不应含残留 \\r")
        // \r\n 应还原为单个 \n
        XCTAssertEqual(parsed[0].title, "第一行\n第二行")
    }
}
