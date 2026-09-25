import XCTest
import LunarCore
@testable import LunisolarCalendarApp

// MARK: - 同步脏标记管理（A 档回归）
//
// 两条真实缺陷：
// 1. 开关关闭时 push() 伪造成功（failedRecordIDs 为空）→ 调用方把刚写入的 dirty/deleted
//    标记全部清掉，这些改动此后再也不会被推送，重开同步后还可能被云端 LWW 覆盖（静默丢数据）。
// 2. 推送在途（CloudKit 往返）期间用户又改了别的事件 → 旧实现对"活的"集合做
//    formIntersection(failed)，把不在 failed 里的新标记一并清掉，且不自愈。

final class SyncDirtyFlagTests: XCTestCase {

    private func event(_ title: String) -> CalendarEvent {
        CalendarEvent(title: title, startDate: Date().addingTimeInterval(3600))
    }

    @MainActor
    private func dirtyIDs(_ store: EventStore) -> Set<String> {
        let (dirty, _) = store.consumeDirtyEvents()
        return Set(dirty.map(\.id.uuidString))
    }

    @MainActor
    private func deletedIDs(_ store: EventStore) -> Set<String> {
        let (_, deleted) = store.consumeDirtyEvents()
        return deleted
    }

    // MARK: 移除规则（A ②）

    /// 推送在途期间新增的脏标记必须保留（旧实现会被 formIntersection 误清）
    @MainActor
    func testConcurrentlyAddedFlagSurvivesAfterPush() {
        let store = makeIsolatedEventStore()
        let a = event("A"), b = event("B"), c = event("C")
        for e in [a, b, c] { store.add(e, skipSync: true) }

        // 模拟：调用方在 await 之前取到的快照是 {A, B}，推送期间 C 又被改了
        let pushedSnapshot: Set<String> = [a.id.uuidString, b.id.uuidString]
        store.removePushedFlags(pushedIDs: pushedSnapshot, failedIDs: [])

        XCTAssertEqual(dirtyIDs(store), [c.id.uuidString],
                       "在途期间新增的 C 必须仍在脏集合里，否则这次改动永远不会被推送")
    }

    /// 逐记录失败的部分必须留在脏集合里（成功的那部分移除）
    @MainActor
    func testPartiallyFailedFlagsAreKept() {
        let store = makeIsolatedEventStore()
        let ok = event("成功"), bad = event("失败")
        store.add(ok, skipSync: true)
        store.add(bad, skipSync: true)

        store.removePushedFlags(pushedIDs: [ok.id.uuidString, bad.id.uuidString],
                                failedIDs: [bad.id.uuidString])

        XCTAssertEqual(dirtyIDs(store), [bad.id.uuidString], "只有失败的那条需要重推")
    }

    /// 删除标记走同一套规则
    @MainActor
    func testDeletedFlagsFollowSameRule() {
        let store = makeIsolatedEventStore()
        let gone = event("被删"), addedLater = event("在途新增")
        store.add(gone, skipSync: true)
        store.delete(gone, skipSync: true)

        // 快照只含 gone；同时再改一条（模拟在途写入）
        store.add(addedLater, skipSync: true)
        store.removePushedFlags(pushedIDs: [gone.id.uuidString], failedIDs: [])

        XCTAssertTrue(deletedIDs(store).isEmpty, "已成功推送的删除标记应移除")
        XCTAssertEqual(dirtyIDs(store), [addedLater.id.uuidString])
    }

    // MARK: 开关关闭时的推送契约（A ①）

    /// 开关关闭时 push 必须报告"一条都没推上去"，否则调用方会把标记清干净
    @MainActor
    func testPushWhileDisabledReportsNothingPushed() async throws {
        let store = makeIsolatedEventStore()
        let coordinator = EventSyncCoordinator(eventStore: store, provider: MockCloudKitProvider())
        coordinator.isEnabled = false

        let ev = event("关掉同步期间的编辑")
        let result = try await coordinator.push(events: [ev], deletedIDs: [])

        XCTAssertEqual(result.pushed, 0, "开关关闭时不应报告已推送")
        XCTAssertTrue(result.failedRecordIDs.contains(ev.id.uuidString),
                      "必须把入参标成未推送，否则调用方会清掉 dirty 标记（改动永久丢失）")
    }

    // MARK: 写入时间戳下限（B 档）

    /// 水位线高于本机时钟时，新记录的时间戳必须严格大于水位线
    func testEventRecordAppliesTimestampFloor() throws {
        var stale = CalendarEvent(title: "本机时钟落后", startDate: Date())
        stale.updatedAt = Date(timeIntervalSince1970: 1_600_000_000)   // 本机记录时间很旧
        let floor: Int64 = Int64(Date().timeIntervalSince1970 * 1000) + 60_000   // 水位线在未来

        let rec = try SyncRecord.eventRecord(for: stale, version: 1,
                                             originDevice: "test-device",
                                             timestampFloorMs: floor)

        XCTAssertEqual(rec.updatedAtMs, floor + 1,
                       "时间戳应被抬到水位线之上，否则其他设备按 sinceMs 过滤后永远拉不到")
    }

    /// 水位线为 0（从未拉取过）时不干预本机时钟
    func testEventRecordKeepsClockWhenNoFloor() throws {
        let ev = CalendarEvent(title: "正常时钟", startDate: Date())

        let rec = try SyncRecord.eventRecord(for: ev, version: 1,
                                             originDevice: "test-device",
                                             timestampFloorMs: 0)

        XCTAssertEqual(rec.updatedAtMs, Int64(ev.updatedAt.timeIntervalSince1970 * 1000))
    }
}
