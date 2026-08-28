import XCTest
@testable import LunisolarCalendarApp

// MARK: - EventStore 测试

@MainActor
final class EventStoreTests: XCTestCase {

    func testCRUD() async {
        let store = makeIsolatedEventStore()
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
        let store = makeIsolatedEventStore()
        let ev = CalendarEvent(title: "通知测试", startDate: Date().addingTimeInterval(3600))
        store.add(ev)

        XCTAssertFalse(ev.isNotified, "初始应为 false")
        store.markNotified(ev)
        let updated = store.events(on: Date()).first(where: { $0.id == ev.id })
        XCTAssertTrue(updated?.isNotified ?? false, "标记后应为 true")

        store.delete(ev)
    }

    func testSearch() async {
        let store = makeIsolatedEventStore()
        let ev = CalendarEvent(title: "可搜索的会议", startDate: Date(), location: "会议室A")
        store.add(ev)

        let results = store.search(query: "会议")
        XCTAssertTrue(results.contains { $0.id == ev.id }, "搜索应匹配标题")

        store.delete(ev)
    }

    // MARK: 农历重复事件能跨春节出现在月视图查询
    func testLunarBirthdayAppearsOnSpringFestival2026() async {
        let store = makeIsolatedEventStore()
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
        let store = makeIsolatedEventStore()
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
        let store = makeIsolatedEventStore()
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
        let store = makeIsolatedEventStore()
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
