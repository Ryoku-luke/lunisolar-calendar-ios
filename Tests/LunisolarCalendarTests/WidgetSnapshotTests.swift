import XCTest
@testable import LunisolarCalendarApp

// MARK: - Widget 共享快照（主 App ⇄ Widget 跨进程数据桥）
//
// 快照从「只存今天」改为「今天起 windowDays 天的逐日窗口」：
// 小组件时间线一次生成 8 条 entry（黄历/农历逐日变化），必须每天都有真实统计，
// 否则过午夜切到「明天」那条 entry 时会显示 0/0 与「今日还没安排」，与数据矛盾。
// （WidgetKit 在 macOS 命令行不可用，这里只测 SnapshotStore 与 EventStore 的写入。）

final class WidgetSnapshotTests: XCTestCase {

    private let cal = Calendar(identifier: .gregorian)

    private func title(_ id: String, _ text: String, done: Bool = false) -> WidgetTodoTitle {
        WidgetTodoTitle(id: id, title: text, isCompleted: done, priorityHex: "#2563EB")
    }

    private func bucket(_ offset: Int, count: Int, completed: Int = 0,
                        titles: [WidgetTodoTitle] = []) -> WidgetDaySnapshot {
        let today = cal.startOfDay(for: Date())
        return WidgetDaySnapshot(
            day: cal.date(byAdding: .day, value: offset, to: today)!,
            eventsCount: count,
            completedCount: completed,
            topTitles: titles
        )
    }

    // MARK: 逐日窗口的读写

    func testWriteThenReadRoundTrip() {
        let today = cal.startOfDay(for: Date())
        let snap = WidgetSharedSnapshot(
            updatedAt: Date(),
            targetDay: today,
            days: [bucket(0, count: 8, completed: 3,
                          titles: [title("a", "读 Swift Concurrency", done: true), title("b", "提交代码")]),
                   bucket(1, count: 2)]
        )
        let customName = "widget_snapshot_\(UUID().uuidString).json"

        XCTAssertTrue(WidgetSnapshotStore.write(snap, appGroupID: nil, fileName: customName))

        let got = WidgetSnapshotStore.read(appGroupID: nil, fileName: customName)
        XCTAssertNotNil(got)
        XCTAssertEqual(got?.days.count, 2)
        XCTAssertEqual(got?.day(for: today)?.eventsCount, 8)
        XCTAssertEqual(got?.day(for: today)?.completedCount, 3)
        XCTAssertEqual(got?.day(for: today)?.topTitles.count, 2)
        XCTAssertEqual(got?.day(for: today)?.topTitles.first?.title, "读 Swift Concurrency")
        XCTAssertEqual(got?.day(for: today)?.topTitles.first?.priorityHex, "#2563EB")
    }

    /// 回归：明天那份必须能取到（旧实现里明天恒为 0/0，跨天后即穿帮）
    func testTomorrowBucketIsReadable() {
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        let snap = WidgetSharedSnapshot(updatedAt: Date(), targetDay: today,
                                        days: [bucket(0, count: 1), bucket(1, count: 6, completed: 2)])

        XCTAssertEqual(snap.day(for: tomorrow)?.eventsCount, 6)
        XCTAssertEqual(snap.day(for: tomorrow)?.completedCount, 2)
    }

    /// 窗口外（昨天）取不到桶——而不是像旧实现那样整份快照作废
    func testDayLookupOutsideWindowReturnsNil() {
        let today = cal.startOfDay(for: Date())
        let snap = WidgetSharedSnapshot(updatedAt: Date(), targetDay: today, days: [bucket(0, count: 5)])

        XCTAssertNil(snap.day(for: cal.date(byAdding: .day, value: -1, to: today)!))
        XCTAssertEqual(snap.day(for: today)?.eventsCount, 5)
    }

    /// 不存在的文件 → 读不到（不会崩）
    func testReadMissingReturnsNil() {
        let missing = "never_exist_\(UUID().uuidString).json"
        XCTAssertNil(WidgetSnapshotStore.read(appGroupID: nil, fileName: missing))
        XCTAssertNil(WidgetSnapshotStore.daySnapshot(for: Date(), appGroupID: nil, fileName: missing))
    }

    /// 旧格式文件（无 days 字段）解码失败 → nil，由调用方回退占位数据（不读出错误数据）
    func testLegacySnapshotFileDecodesToNil() throws {
        let customName = "widget_snapshot_legacy_\(UUID().uuidString).json"
        let legacy = """
        {"updatedAt":"2026-09-25T00:00:00Z","targetDay":"2026-09-25T00:00:00Z",\
        "todaysEventsCount":9,"todaysCompletedCount":4,"topTitles":[]}
        """
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(customName)
        try Data(legacy.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertNil(WidgetSnapshotStore.read(appGroupID: nil, fileName: customName),
                     "旧格式没有 days 字段，应解码失败并回退，而不是读出错误数据")
    }

    // MARK: EventStore 写入（窗口内每天都要真实）

    @MainActor
    func testEventStoreWritesWindowWithRealCounts() {
        let store = makeIsolatedEventStore()
        _ = store.clearAll(skipSync: true)

        let today = cal.startOfDay(for: Date())
        guard let t10 = cal.date(byAdding: .hour, value: 10, to: today),
              let t14 = cal.date(byAdding: .hour, value: 14, to: today),
              let tomorrow10 = cal.date(byAdding: .day, value: 1, to: t10) else {
            XCTFail("构造时间失败"); return
        }

        var done = CalendarEvent(id: UUID(), title: "晨会", startDate: t10, isAllDay: false, priority: .urgent)
        done.isCompleted = true
        store.add(done, skipSync: true)
        store.add(CalendarEvent(id: UUID(), title: "评审", startDate: t14, isAllDay: false, priority: .high),
                  skipSync: true)
        store.add(CalendarEvent(id: UUID(), title: "明日验收", startDate: tomorrow10, isAllDay: false, priority: .high),
                  skipSync: true)

        // 防抖在命令行测试下不保证执行，用测试专用接口强制立即落盘
        store._testFlushSave()

        let got = WidgetSnapshotStore.read(appGroupID: nil, fileName: "widget_snapshot.json")
        XCTAssertNotNil(got, "EventStore.save 后应已写出 widget_snapshot.json")
        XCTAssertEqual(got?.days.count, WidgetSnapshotStore.windowDays, "窗口应覆盖时间线用到的每一天")

        let todayBucket = got?.day(for: today)
        XCTAssertEqual(todayBucket?.eventsCount, 2)
        XCTAssertEqual(todayBucket?.completedCount, 1)
        XCTAssertEqual(todayBucket?.topTitles.first?.title, "晨会", "优先级排序：urgent 晨会排第一")
        XCTAssertEqual(todayBucket?.topTitles.first?.isCompleted, true)

        // 关键回归：明天那份不能是 0 —— 这正是跨天后小组件显示 0/0 的根因
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        XCTAssertEqual(got?.day(for: tomorrow)?.eventsCount, 1, "明日日程必须写进窗口")
        XCTAssertEqual(got?.day(for: tomorrow)?.topTitles.first?.title, "明日验收")
    }

    /// 窗口首日仍是今天 → 不该重写（避免每次回前台都触发 WidgetKit 重载）；跨天 → 重写
    @MainActor
    func testRefreshOnlyRewritesWhenDayChanged() {
        let store = makeIsolatedEventStore()
        let fileName = "widget_snapshot.json"
        let today = cal.startOfDay(for: Date())

        // 先放一份「首日 = 今天」的窗口
        let fresh = WidgetSharedSnapshot(updatedAt: Date(), targetDay: today, days: [bucket(0, count: 3)])
        XCTAssertTrue(WidgetSnapshotStore.write(fresh, appGroupID: nil, fileName: fileName))

        store.refreshWidgetSnapshotIfDayChanged()
        XCTAssertEqual(WidgetSnapshotStore.read(appGroupID: nil, fileName: fileName)?.days.count, 1,
                       "窗口已覆盖今天时不应重写（被重写会变成满窗口）")

        // 跨天：窗口首日成了昨天，应重写成以今天开头
        let stale = WidgetSharedSnapshot(
            updatedAt: Date().addingTimeInterval(-86400),
            targetDay: cal.date(byAdding: .day, value: -1, to: today)!,
            days: [bucket(-1, count: 9)]
        )
        XCTAssertTrue(WidgetSnapshotStore.write(stale, appGroupID: nil, fileName: fileName))

        store.refreshWidgetSnapshotIfDayChanged()
        let after = WidgetSnapshotStore.read(appGroupID: nil, fileName: fileName)
        XCTAssertNotNil(after?.day(for: today), "跨天后必须把窗口滑动到今天")
    }

    // MARK: Entry 的「未知」显示（App 超过窗口天数未运行时不谎报 0/0）

    private func entry(count: Int, completed: Int, hasData: Bool) -> LunisolarWidgetEntry {
        LunisolarWidgetEntry(
            date: Date(),
            huangli: nil,
            lunar: nil,
            festivals: [],
            primaryFestivalHex: "#C41A1A",
            todaysEventsCount: count,
            completedCount: completed,
            hasFestival: false,
            topTitles: [],
            hasTodoData: hasData
        )
    }

    func testUnknownCountsRenderAsDashes() {
        let unknown = entry(count: 0, completed: 0, hasData: false)
        XCTAssertEqual(unknown.percentText, "—%", "不知道就不能显示 0%")
        XCTAssertEqual(unknown.countText, "—/—", "不知道就不能显示 0/0")

        // 确实没有安排时，0% 与 0/0 是真话，应照常显示
        let knownZero = entry(count: 0, completed: 0, hasData: true)
        XCTAssertEqual(knownZero.percentText, "0%")
        XCTAssertEqual(knownZero.countText, "0/0")

        let knownPartial = entry(count: 4, completed: 3, hasData: true)
        XCTAssertEqual(knownPartial.percentText, "75%")
        XCTAssertEqual(knownPartial.countText, "3/4")
    }
}
