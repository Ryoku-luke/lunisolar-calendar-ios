import XCTest
@testable import LunisolarCalendarApp

// MARK: - EventStore 同步语义专项（2026-10-19 全量审查的后续）
//
// 这些用例钉的是**代码注释里写明的契约**（"应该怎样"），而不是"代码现在怎样"——
// 只有这样，将来若有人改动语义，测试才会红。
// 选的都是**纯内存可观察**的行为，不需要真实 iCloud。

@MainActor
final class EventStoreSyncSemanticsTests: XCTestCase {

    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let dir { try? FileManager.default.removeItem(at: dir) }
        super.tearDown()
    }

    private func makeStore() -> EventStore { EventStore(storageBaseDir: dir) }

    // MARK: applyRemote / applyRemoteDelete

    /// 远端记录必须**原样采用**远端的 updatedAt，不能在本机盖上"now"
    /// （注释里的原始动机：否则 UI 会把"一年前的远端编辑"显示成"刚刚更新"）。
    func testApplyRemoteKeepsRemoteUpdatedAtVerbatim() {
        let store = makeStore()
        let remoteTime = Date(timeIntervalSince1970: 1_700_000_000)
        var remote = CalendarEvent(title: "远端编辑", startDate: Date())
        remote.updatedAt = remoteTime

        store.applyRemote(remote)
        store._testFlushSave()

        let reloaded = EventStore(storageBaseDir: dir)
        let got = reloaded.events.first { $0.id == remote.id }
        XCTAssertEqual(got?.updatedAt.timeIntervalSince1970 ?? 0,
                       remoteTime.timeIntervalSince1970, accuracy: 0.001,
                       "applyRemote 不得把 updatedAt 改写成本机时间")
    }

    /// 远端墓碑删除：本地事件消失，且**必须落盘**（并非只改内存）
    func testApplyRemoteDeleteRemovesEventAndPersists() {
        let store = makeStore()
        let ev = CalendarEvent(title: "将被远端删除", startDate: Date())
        store.add(ev)
        store._testFlushSave()
        XCTAssertTrue(store.events.contains { $0.id == ev.id })

        store.applyRemoteDelete(id: ev.id)
        store._testFlushSave()

        XCTAssertFalse(store.events.contains { $0.id == ev.id }, "本地应删除")
        let reloaded = EventStore(storageBaseDir: dir)
        XCTAssertFalse(reloaded.events.contains { $0.id == ev.id }, "删除必须落盘，重启后不能复活")
    }

    // MARK: merge 的校验与三种策略

    /// 非法记录（空标题）必须被**计数并跳过**，绝不能进库
    func testMergeRejectsInvalidEvents() {
        let store = makeStore()
        let before = store.events.count
        let r = store.merge([
            CalendarEvent(title: "   \n  ", startDate: Date()),   // 只有空白 → 非法
        ], policy: .keepLatest)
        XCTAssertEqual(r.invalid, 1, "空标题记录应被计数为非法")
        XCTAssertEqual(store.events.count, before, "非法记录绝不能进库")
    }

    /// `CalendarEvent.init` 的 endDate 规则（我两次写错，最终以代码为准确立）：
    /// · **只在 `endDate <= startDate` 时**兜底：非全天 +3600 秒、全天 +86399 秒；
    /// · 合法但很短的事件（例如 60 秒的会）**原样保留**，不会被"修正"成 1 小时。
    func testEventInitEndDateRules() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        // ① 结束早于开始 → 兜底 1 小时
        let reversed = CalendarEvent(title: "结束早于开始", startDate: start,
                                     endDate: start.addingTimeInterval(-60))
        XCTAssertEqual(reversed.endDate.timeIntervalSince(start), 3600, accuracy: 1)
        // ② 全天事件 → 兜底到同一日历日内（86399 秒）
        let allDay = CalendarEvent(title: "全天", startDate: start, endDate: start, isAllDay: true)
        XCTAssertEqual(allDay.endDate.timeIntervalSince(start), 86399, accuracy: 1)
        // ③ 合法的短事件必须原样保留
        let short = CalendarEvent(title: "短会", startDate: start,
                                  endDate: start.addingTimeInterval(60))
        XCTAssertEqual(short.endDate.timeIntervalSince(start), 60, accuracy: 1,
                       "init 只在 end ≤ start 时兜底，不应改写合法的短会时长")
    }

    /// `.keepLocal`：已存在的同 id 记录保持本地版本
    func testMergeKeepLocalKeepsExisting() {
        let store = makeStore()
        let id = UUID()
        store.add(CalendarEvent(id: id, title: "本地版本", startDate: Date()))
        let incoming = CalendarEvent(id: id, title: "远程版本", startDate: Date())
        _ = store.merge([incoming], policy: .keepLocal)
        XCTAssertEqual(store.events.first { $0.id == id }?.title, "本地版本")
    }

    /// `.overwrite`：远端版本覆盖本地
    func testMergeOverwriteTakesIncoming() {
        let store = makeStore()
        let id = UUID()
        store.add(CalendarEvent(id: id, title: "本地版本", startDate: Date()))
        let incoming = CalendarEvent(id: id, title: "远程版本", startDate: Date())
        _ = store.merge([incoming], policy: .overwrite)
        XCTAssertEqual(store.events.first { $0.id == id }?.title, "远程版本")
    }

    /// `.keepLatest`：按 updatedAt 取新的那个 —— 两个方向都要成立（否则语义就变成"总是覆盖"）
    func testMergeKeepLatestPicksNewerInBothDirections() {
        let store = makeStore()
        let id = UUID()
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        var local = CalendarEvent(id: id, title: "本地较新", startDate: Date())
        local.updatedAt = old.addingTimeInterval(3600)
        store.add(local)

        var olderRemote = CalendarEvent(id: id, title: "远端较旧", startDate: Date())
        olderRemote.updatedAt = old
        _ = store.merge([olderRemote], policy: .keepLatest)
        XCTAssertEqual(store.events.first { $0.id == id }?.title, "本地较新",
                       "远端更旧时不该覆盖本地")

        var newerRemote = CalendarEvent(id: id, title: "远端较新", startDate: Date())
        newerRemote.updatedAt = old.addingTimeInterval(7200)
        _ = store.merge([newerRemote], policy: .keepLatest)
        XCTAssertEqual(store.events.first { $0.id == id }?.title, "远端较新",
                       "远端更新时必须覆盖本地")
    }
}
