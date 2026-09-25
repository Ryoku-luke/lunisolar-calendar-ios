import XCTest
import LunarCore
@testable import LunisolarCalendarApp

// MARK: - 完成态写入语义测试
//
// 背景：「全部日程」多选后的操作条写着「完成 N 项」，实现却循环调用
// `EventService.setCompleted`（切换语义）→ 选中集合里混有已完成项时，
// 点「完成」会把已完成的改回未完成，与文案相反。
//
// 现在两种语义分开：`setCompleted` = 切换（完成圈 / 标记完成-取消完成），
// `markCompleted` = 幂等置为已完成（批量操作）。

@MainActor
final class EventServiceCompletionTests: XCTestCase {

    private func event(completed: Bool = false) -> CalendarEvent {
        var ev = CalendarEvent(title: "完成态测试", startDate: Date().addingTimeInterval(3600))
        ev.isCompleted = completed
        return ev
    }

    private func isCompleted(_ id: UUID, in store: EventStore) -> Bool {
        store.events.first { $0.id == id }?.isCompleted ?? false
    }

    // MARK: markCompleted：幂等「置为已完成」

    func testMarkCompletedCompletesAnIncompleteEvent() {
        let store = makeIsolatedEventStore()
        let service = EventService(store: store)
        let ev = event()
        store.add(ev, skipSync: true)

        service.markCompleted(ev)

        XCTAssertTrue(isCompleted(ev.id, in: store))
    }

    /// 回归：已完成的条目必须保持完成（批量操作的核心诉求）
    func testMarkCompletedLeavesCompletedEventAlone() {
        let store = makeIsolatedEventStore()
        let service = EventService(store: store)
        let ev = event(completed: true)
        store.add(ev, skipSync: true)

        service.markCompleted(ev)

        XCTAssertTrue(isCompleted(ev.id, in: store),
                      "已完成的条目不得被批量「完成」反转成未完成")
    }

    /// 批量场景复现：混合选中集合，逐个 markCompleted 后应全部为已完成
    func testBulkMarkCompletedEndsUpAllCompleted() {
        let store = makeIsolatedEventStore()
        let service = EventService(store: store)
        let done = event(completed: true)
        let todo = event()
        store.add(done, skipSync: true)
        store.add(todo, skipSync: true)

        for ev in [done, todo] { service.markCompleted(ev) }

        XCTAssertTrue(isCompleted(done.id, in: store))
        XCTAssertTrue(isCompleted(todo.id, in: store))
    }

    // MARK: setCompleted：仍是切换语义

    func testSetCompletedStillToggles() {
        let store = makeIsolatedEventStore()
        let service = EventService(store: store)
        let ev = event()
        store.add(ev, skipSync: true)

        service.setCompleted(ev)
        XCTAssertTrue(isCompleted(ev.id, in: store), "第一次切换 → 已完成")

        service.setCompleted(store.events.first { $0.id == ev.id }!)
        XCTAssertFalse(isCompleted(ev.id, in: store), "再次切换 → 回到未完成")
    }
}
