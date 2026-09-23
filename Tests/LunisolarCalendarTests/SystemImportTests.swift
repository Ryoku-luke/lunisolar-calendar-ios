import XCTest
@testable import LunisolarCalendarApp

// MARK: - 系统导入桥（SystemImportBridge）单元测试

final class SystemImportTests: XCTestCase {

    // DTO → CalendarEvent 字段全保留
    func testMapperPreservesAllFields() {
        let cal = Calendar(identifier: .gregorian)
        let s = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 10))!
        let dto = SystemImportEvent(
            sourceID: "ek:abc-123",
            title: "项目周会",
            startDate: s,
            endDate: s.addingTimeInterval(3600),
            isAllDay: false,
            location: "会议室 A",
            notes: "带周报",
            repeatRule: .weekly,
            eventType: .schedule,
            priority: .normal
        )
        let ev = SystemImportMapper.toCalendarEvent(dto)
        XCTAssertEqual(ev.title, "项目周会")
        XCTAssertEqual(ev.type, .schedule)
        XCTAssertEqual(ev.startDate, s)
        XCTAssertEqual(ev.endDate, s.addingTimeInterval(3600))
        XCTAssertEqual(ev.isAllDay, false)
        XCTAssertEqual(ev.location, "会议室 A")
        XCTAssertEqual(ev.notes, "带周报")
        XCTAssertEqual(ev.repeatRule, .weekly)
        XCTAssertEqual(ev.priority, .normal)
        XCTAssertEqual(ev.isNotified, false, "系统导入默认不开启通知")
    }

    // 确定性 UUID：同一 sourceID 多次映射 → 同一 UUID（防重复导入产生副本）
    func testDeterministicUUIDStableAcrossCalls() {
        let dto = SystemImportEvent(
            sourceID: "ek:event-xyz",
            title: "测试",
            startDate: Date()
        )
        let uuid1 = SystemImportMapper.toCalendarEvent(dto).id
        let uuid2 = SystemImportMapper.toCalendarEvent(dto).id
        XCTAssertEqual(uuid1, uuid2, "同一 sourceID 必须产生同一 UUID")
    }

    // 不同 sourceID → 不同 UUID
    func testDifferentSourceIDsDifferentUUIDs() {
        let a = SystemImportEvent(sourceID: "ek:1", title: "A", startDate: Date())
        let b = SystemImportEvent(sourceID: "ek:2", title: "B", startDate: Date())
        XCTAssertNotEqual(
            SystemImportMapper.toCalendarEvent(a).id,
            SystemImportMapper.toCalendarEvent(b).id
        )
    }

    // Stub Provider 正常授权 + 有数据 → 拿回来
    func testStubProviderFetchEvents() async {
        let dtos = [
            SystemImportEvent(sourceID: "ek:1", title: "日历事件1", startDate: Date(),
                              repeatRule: .daily, eventType: .schedule),
            SystemImportEvent(sourceID: "ek:2", title: "日历事件2", startDate: Date().addingTimeInterval(3600),
                              repeatRule: .never, eventType: .schedule)
        ]
        let provider = StubSystemImportProvider(source: .systemCalendar, events: dtos, authorized: true)
        let ok = try? await provider.requestAuthorization()
        XCTAssertTrue(ok ?? false)
        let list = try? await provider.fetchEvents()
        XCTAssertEqual(list?.count, 2)
    }

    // 未授权 → fetchEvents 抛 unauthorized
    func testStubProviderUnauthorized() async {
        let provider = StubSystemImportProvider(source: .contacts, events: [], authorized: false)
        do {
            _ = try await provider.fetchEvents()
            XCTFail("未授权时应抛 unauthorized")
        } catch let e as SystemImportError {
            if case .unauthorized = e { /* ok */ } else { XCTFail("期望 unauthorized，实际 \(e)") }
        } catch {
            XCTFail("期望 SystemImportError，实际 \(error)")
        }
    }

    // Aggregator：多 Provider 合并 + 失败不阻塞
    func testAggregatorCombinesAndCollectsFailures() async {
        let okProvider = StubSystemImportProvider(
            source: .systemCalendar,
            events: [SystemImportEvent(sourceID: "ek:1", title: "日历", startDate: Date())],
            authorized: true
        )
        let failProvider = StubSystemImportProvider(
            source: .contacts,
            events: [],
            authorized: false
        )
        let (events, failures) = await SystemImportAggregator.gather(providers: [okProvider, failProvider])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(failures.count, 1)
        if case .unauthorized(let s) = failures.first {
            XCTAssertEqual(s, .contacts)
        } else {
            XCTFail("期望 unauthorized(.contacts)")
        }
    }

    // 联系人生日 DTO（yearly + reminder + high）→ CalendarEvent 字段正确
    func testContactBirthdayDTOMapsToYearlyReminder() {
        let cal = Calendar(identifier: .gregorian)
        let s = cal.date(from: DateComponents(year: 1990, month: 3, day: 15, hour: 9))!
        let dto = SystemImportEvent(
            sourceID: "contact-birthday:id-001",
            title: "张三 生日",
            startDate: s,
            isAllDay: false,
            notes: "从联系人导入",
            repeatRule: .yearly,
            eventType: .reminder,
            priority: .high
        )
        let ev = SystemImportMapper.toCalendarEvent(dto)
        XCTAssertEqual(ev.type, .reminder)
        XCTAssertEqual(ev.repeatRule, .yearly)
        XCTAssertEqual(ev.priority, .high)
        XCTAssertEqual(ev.title, "张三 生日")
    }

    // 联系人生日按农历每年：DTO repeatRule=lunarAnnually → 事件正确
    func testContactBirthdayLunarAnnuallyToggle() {
        let dto = SystemImportEvent(
            sourceID: "contact-birthday:id-002",
            title: "李四 生日",
            startDate: Date(),
            repeatRule: .lunarAnnually,
            eventType: .reminder,
            priority: .high
        )
        let ev = SystemImportMapper.toCalendarEvent(dto)
        XCTAssertEqual(ev.repeatRule, .lunarAnnually)
    }

    // 端到端：Stub Provider → Aggregator → EventStore.merge → 无重复
    @MainActor
    func testEndToEndImportNoDuplicatesOnReimport() async {
        let store = makeIsolatedEventStore()
        _ = store.clearAll(skipSync: true)

        let dtos = [
            SystemImportEvent(sourceID: "ek:stable-1", title: "稳定事件A",
                              startDate: Date(), repeatRule: .never, eventType: .schedule),
            SystemImportEvent(sourceID: "ek:stable-2", title: "稳定事件B",
                              startDate: Date().addingTimeInterval(7200), repeatRule: .never,
                              eventType: .schedule, priority: .high)
        ]
        let provider = StubSystemImportProvider(source: .systemCalendar, events: dtos, authorized: true)

        // 第一次导入：2 条新增
        let (events1, _) = await SystemImportAggregator.gather(providers: [provider])
        let r1 = store.merge(events1, policy: .keepLatest, skipSync: true)
        XCTAssertEqual(r1.added, 2)
        XCTAssertEqual(store.events.count, 2)

        // 第二次完全相同数据导入：0 新增（确定性 UUID → 同 id → keepLatest 视为更新不追加副本）
        let (events2, _) = await SystemImportAggregator.gather(providers: [provider])
        let r2 = store.merge(events2, policy: .keepLatest, skipSync: true)
        XCTAssertEqual(r2.added, 0, "重复导入不应产生副本")
        XCTAssertEqual(r2.updated, 2, "同 id 的应走更新分支")
        XCTAssertEqual(store.events.count, 2)
    }
}
