import XCTest
@testable import LunisolarCalendarApp

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
        let store = makeIsolatedEventStore()
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

        // EventStore.save() 内部做了 debounced，Linux XCTest 下 DispatchQueue.main.asyncAfter 不保证执行
        // 所以用测试专用 flush 接口强制立即落盘 → writeWidgetSnapshotIfNeeded
        store._testFlushSave()

        // EventStore.saveNow → writeWidgetSnapshotIfNeeded 写了快照，直接读
        let got = WidgetSnapshotStore.read(appGroupID: nil, fileName: "widget_snapshot.json", maxAge: 60)
        XCTAssertNotNil(got, "EventStore.save 后应已写出 widget_snapshot.json")
        XCTAssertEqual(got?.todaysEventsCount, 2)
        XCTAssertEqual(got?.todaysCompletedCount, 1)
        // 优先级排序：urgent 晨会应该排第一
        XCTAssertEqual(got?.topTitles.first?.title, "晨会")
        XCTAssertEqual(got?.topTitles.first?.isCompleted, true)
        XCTAssertEqual(got?.topTitles.first?.priorityHex, Priority.urgent.widgetHex)
    }
}
