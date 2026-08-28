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
}
