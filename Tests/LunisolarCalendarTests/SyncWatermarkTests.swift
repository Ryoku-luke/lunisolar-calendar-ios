import XCTest
@testable import LunisolarCalendarApp

// MARK: - 增量同步水位线：被拒绝的记录不得被迈过（P1-1 配套修复）
//
// 背景：`pullAndMerge` 曾经用 `remote.map(\.updatedAtMs).max()` 推进增量水位线，
// 这会连**被拒绝**的记录一起迈过。而下轮 pull 的谓词是 `updatedAtMs > sinceMs`，
// 于是一条"因等版本被拒"的记录**再也不会被拉回来** → 永久不可合并 → 设备间永久分叉。
//
// 修复：只有**真正处理掉**（采纳 / 按墓碑删除）的记录才允许推进水位线。
//
// 本测试是那个 bug 的隔离探测器：修复前 `stillPullable == false`。

@MainActor
final class SyncWatermarkTests: XCTestCase {

    private func makeDevice() async -> (store: EventStore, provider: MockCloudKitProvider,
                                       coordinator: EventSyncCoordinator) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lunisolar-wm-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = EventStore(storageBaseDir: dir)
        for e in store.events { store.delete(e, skipSync: true) }
        store.clearDirtyFlags()

        let suite = "test.lunisolar.wm.\(UUID().uuidString)"
        let td = UserDefaults(suiteName: suite) ?? .standard
        td.removePersistentDomain(forName: suite)

        let provider = MockCloudKitProvider(deviceID: "dev-W", sharedStore: MockCloudKitStore())
        provider.simulatedLatencyMs = 0
        provider.isOnline = true
        provider.iCloudAvailable = true

        let coordinator = EventSyncCoordinator(eventStore: store, provider: provider, defaults: td)
        coordinator.resetSyncMetadata()
        coordinator.isEnabled = true
        store.syncCoordinator = coordinator
        return (store, provider, coordinator)
    }

    /// 被拒绝的远端记录必须仍可被下轮 pull 拉到；否则它永远无法被合并。
    func testRejectedRemoteRecordRemainsPullable() async throws {
        let (store, provider, coordinator) = await makeDevice()
        let id = UUID()

        var ev = CalendarEvent(id: id, title: "本地版", startDate: Date())
        ev.updatedAt = Date()
        store.add(ev, skipSync: true)
        store.clearDirtyFlags()

        // 让本地 versionMap 追到 2（模拟"本地已把 v2 推上去"）
        _ = try await coordinator.push(events: [ev])   // versionMap → 1
        _ = try await coordinator.push(events: [ev])   // versionMap → 2
        let serverRec = await provider.serverGet(id: id.uuidString)
        let localVersion = try XCTUnwrap(serverRec?.version)
        XCTAssertEqual(localVersion, 2)

        // 云端出现一条**等版本但内容不同**的记录（另一台设备的分叉写入）
        var other = ev
        other.title = "对方版"
        other.updatedAt = Date().addingTimeInterval(30)
        let encoded = try SyncRecord.eventRecord(for: other, version: localVersion,
                                                originDevice: "dev-OTHER")
        await provider.injectServerRecord(encoded)

        // 第一轮 pull：等版本 → 被拒（本地 versionMap 已是 2）
        let r1 = try await coordinator.pullAndMerge()
        XCTAssertEqual(r1.pulled, 0, "等版本记录应被拒绝合并（严格 > 规则）")

        // 核心断言：水位线**不得**越过这条被拒记录
        let pullable = try await provider.pull(sinceMs: coordinator.lastSyncMs)
        XCTAssertTrue(pullable.contains { $0.id == id.uuidString },
                      "被拒绝的记录必须仍然可拉（否则永久不可合并 → 设备永久分叉）")
    }

    /// 对照组：**被采纳**的记录当然要推进水位线，否则会重复拉取。
    func testAcceptedRemoteRecordAdvancesWatermark() async throws {
        let (store, provider, coordinator) = await makeDevice()
        let id = UUID()

        var remote = CalendarEvent(id: id, title: "云端新增", startDate: Date())
        remote.updatedAt = Date()
        let encoded = try SyncRecord.eventRecord(for: remote, version: 1, originDevice: "dev-OTHER")
        await provider.injectServerRecord(encoded)

        let before = coordinator.lastSyncMs
        let r = try await coordinator.pullAndMerge()
        XCTAssertEqual(r.pulled, 1, "云端新增应被采纳")
        XCTAssertGreaterThan(coordinator.lastSyncMs, before,
                             "已采纳的记录必须推进水位线，否则每轮重复拉取")
        XCTAssertEqual(store.eventBy(idString: id.uuidString)?.title, "云端新增")
    }
}
