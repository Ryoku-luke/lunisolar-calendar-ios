import XCTest
@testable import LunisolarCalendarApp

// MARK: - 双设备等版本分叉的收敛测试（P1-1 要求 3）
//
// 场景：两台设备从同一 base 版本各自离线编辑 → 双方都产出同一个 version
// （例如都从 v1 → v2）。这是 `pullAndMerge` 用严格 `>` 时最容易出问题的情形：
// 本地已记 v2，远端的 v2 不满足 `>` 会被丢弃。
//
// 本测试**不假设一轮收敛**，而是把实际行为钉住并要求它满足两条底线：
//   1. **收敛**：无论中间经历几个同步周期，最终两台设备内容一致；
//   2. **不静默丢数据**：败方的编辑不会凭空消失——它要么最终胜出，
//      要么被明确定义的另一方覆盖（可解释），且从未出现「两台机器永久不一致」。
//
// ⚠️ 若未来把 pull 侧也改成 `updatedAtMs` 平局判定以实现「一轮收敛」，
// 本测试的 `XCTAssertGreaterThan(cycles)` 上限会需要放宽/调整——
// 届时请同时更新 `SyncConflictResolver.shouldAdoptRemote` 的注释。

@MainActor
final class SyncDivergenceConvergenceTests: XCTestCase {

    private var deviceA: (store: EventStore, provider: MockCloudKitProvider,
                          coordinator: EventSyncCoordinator, defaults: UserDefaults)!
    private var deviceB: (store: EventStore, provider: MockCloudKitProvider,
                          coordinator: EventSyncCoordinator, defaults: UserDefaults)!
    private let cloud = MockCloudKitStore()

    override func setUp() async throws {
        try await super.setUp()
        await cloud.reset()
        deviceA = await makeDevice(name: "A")
        deviceB = await makeDevice(name: "B")
    }

    override func tearDown() async throws {
        for d in [deviceA, deviceB] {
            guard let d else { continue }
            d.defaults.removeObject(forKey: "Lunisolar.sync.lastSyncMs.lo")
            d.defaults.removeObject(forKey: "Lunisolar.sync.lastSyncMs.hi")
            d.defaults.removeObject(forKey: "Lunisolar.sync.versionMap")
        }
        deviceA = nil
        deviceB = nil
        await cloud.reset()
        try await super.tearDown()
    }

    /// 造一台"设备"：独立本地库 + 独立 UserDefaults + 独立 provider，但共享同一个云端 store
    private func makeDevice(name: String) async -> (store: EventStore, provider: MockCloudKitProvider,
                                                   coordinator: EventSyncCoordinator, defaults: UserDefaults) {
        let baseDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lunisolar-2dev-\(name)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        let store = EventStore(storageBaseDir: baseDir)
        // 清掉示例数据（skipSync 避免自动推送）
        for ev in store.events { store.delete(ev, skipSync: true) }
        // ⚠️ 关键：`delete(_, skipSync: true)` / `add(_, skipSync: true)` 只跳过**自动推送**，
        // 仍会写入 dirty/deleted 标记。这里显式清干净，让设备从「已同步」状态出发——
        // 否则残留的脏标记会在下一轮 sync 把陈旧内容重新推上云端，制造出**测试假象**
        // （并非生产路径：生产路径的 add/update 会走 enqueuePush → flushDirtyAndDeleted
        //   把成功推送的记录从 dirty 里移除）。
        store.clearDirtyFlags()

        let suite = "test.lunisolar.2dev.\(name).\(UUID().uuidString)"
        let td = UserDefaults(suiteName: suite) ?? .standard
        td.removePersistentDomain(forName: suite)

        let provider = MockCloudKitProvider(deviceID: "device-\(name)", sharedStore: cloud)
        provider.simulatedLatencyMs = 0
        provider.isOnline = true
        provider.iCloudAvailable = true

        let coordinator = EventSyncCoordinator(eventStore: store, provider: provider, defaults: td)
        coordinator.resetSyncMetadata()
        coordinator.isEnabled = true
        store.syncCoordinator = coordinator

        return (store, provider, coordinator, td)
    }

    /// 两设备从同一 base 各自编辑 → 必须在有限周期内收敛到同一内容
    func testEqualVersionDivergenceConverges() async throws {
        let id = UUID()

        // ---- 0) 设备 A 建立事件并推到云端（v1）----
        var event = CalendarEvent(id: id, title: "初始标题", startDate: Date())
        event.updatedAt = Date()
        deviceA.store.add(event, skipSync: true)

        _ = try await deviceA.coordinator.push(events: [event])
        let v1 = await deviceA.provider.serverGet(id: id.uuidString)
        XCTAssertEqual(v1?.version, 1, "A 首次推送应为 v1")

        // ---- 1) B 拉取，双方都拿到 v1（versionMap 都是 1）----
        _ = try await deviceB.coordinator.pullAndMerge()
        let bAfterPull = deviceB.store.eventBy(idString: id.uuidString)
        XCTAssertEqual(bAfterPull?.title, "初始标题", "B 应拉到 A 的事件")

        // 让两台设备都处于「已同步、无待推送」的干净状态，再各自离线编辑。
        // （若不清，A 首次 add 留下的脏标记会在下一轮 sync 把陈旧内容重推上云端，
        //   那是测试设置假象，不是生产路径。）
        deviceA.store.clearDirtyFlags()
        deviceB.store.clearDirtyFlags()

        // ---- 2) 双方各自离线编辑，都从 v1 → v2（这就是"等版本分叉"）----
        // A 的编辑时间戳刻意更晚 → A 的 v2 在同版本平局中胜出（规则：版本相等比 updatedAtMs）
        // ⚠️ 必须**写进各自的 store**：syncBidirectional → consumeDirtyEvents 是从 store 里
        // 取事件的。若只改一份游离对象去 push，store 里仍是旧内容，下一轮 sync 会把旧内容
        // 以更高版本重新推上云端（真实存在的数据回退路径，但那是另一个缺陷，
        // 不应混进本测试——本测试只钉等版本分叉的收敛）。
        var aEdit = event
        aEdit.title = "A 的编辑"
        aEdit.updatedAt = Date().addingTimeInterval(2)
        deviceA.store.update(aEdit, skipSync: true)
        deviceA.store.clearDirtyFlags()

        var bEdit = bAfterPull!
        bEdit.title = "B 的编辑"
        bEdit.updatedAt = Date().addingTimeInterval(1)
        deviceB.store.update(bEdit, skipSync: true)
        deviceB.store.clearDirtyFlags()

        let aPush = try await deviceA.coordinator.push(events: [aEdit])
        XCTAssertEqual(aPush.pushed, 1, "A 的 v2 应推上云端")

        let bPush = try await deviceB.coordinator.push(events: [bEdit])
        // B 的 v2 与云端 A 的 v2 等版本且时间戳更旧 → 必须被拒（否则 A 的编辑被静默回滚）
        XCTAssertEqual(bPush.pushed, 0, "B 的等版本但更旧的 v2 应被拒——不得覆盖 A")
        XCTAssertFalse(bPush.errors.isEmpty, "被拒必须体现为 per-record 错误，上层才会保留脏标记")
        let serverAfterBoth = await deviceA.provider.serverGet(id: id.uuidString)
        XCTAssertEqual(serverAfterBoth?.version, 2, "云端应停在 v2")
        XCTAssertEqual(try serverAfterBoth?.decodedEvent().title, "A 的编辑",
                       "等版本平局由 updatedAtMs 决定：A 更新 → 云端保留 A")

        // ---- 3) 收敛循环：双方各做一轮双向同步 ----
        // 水位线缺陷修复（被拒记录曾被迈过、此后永久不可拉）之后，等版本分叉**一轮即收敛**：
        // 两端各 sync 一次，各自在 pull 阶段采纳云端权威版本。
        var cycles = 0
        let maxCycles = 5
        var converged = false
        while cycles < maxCycles {
            cycles += 1
            _ = try await deviceA.coordinator.syncBidirectional()
            _ = try await deviceB.coordinator.syncBidirectional()

            let aTitle = deviceA.store.eventBy(idString: id.uuidString)?.title
            let bTitle = deviceB.store.eventBy(idString: id.uuidString)?.title
            if let aTitle, let bTitle, aTitle == bTitle {
                converged = true
                break
            }
        }

        // ---- 4) 底线断言 ----
        XCTAssertTrue(converged, "两台设备必须收敛；实际未一致（cycles=\(cycles)）")
        XCTAssertEqual(cycles, 1,
                       "等版本分叉应**一轮**收敛（水位线修复前需多轮、甚至永远收不敛）")
        XCTAssertLessThanOrEqual(cycles, maxCycles)

        let finalA = deviceA.store.eventBy(idString: id.uuidString)?.title
        let finalB = deviceB.store.eventBy(idString: id.uuidString)?.title
        XCTAssertEqual(finalA, finalB, "收敛后内容必须相同")

        // 不静默丢数据：胜出者必须是**某一方的真实编辑**，不能变成空/初始标题
        XCTAssertTrue(finalA == "A 的编辑" || finalA == "B 的编辑",
                      "收敛结果必须是某台设备的真实编辑，实际：\(String(describing: finalA))")
    }

    /// 反向：B 的编辑更新时，B 应在下一轮胜出，且同样收敛
    func testEqualVersionDivergenceConvergesWithOtherWinner() async throws {
        let id = UUID()

        var event = CalendarEvent(id: id, title: "初始", startDate: Date())
        event.updatedAt = Date()
        deviceA.store.add(event, skipSync: true)
        _ = try await deviceA.coordinator.push(events: [event])
        _ = try await deviceB.coordinator.pullAndMerge()
        deviceA.store.clearDirtyFlags()
        deviceB.store.clearDirtyFlags()

        // 这次 B 的时间戳更晚 → B 的 v2 胜出
        var aEdit = event
        aEdit.title = "A 版"
        aEdit.updatedAt = Date().addingTimeInterval(1)
        deviceA.store.update(aEdit, skipSync: true)
        deviceA.store.clearDirtyFlags()

        var bEdit = deviceB.store.eventBy(idString: id.uuidString)!
        bEdit.title = "B 版"
        bEdit.updatedAt = Date().addingTimeInterval(3)
        deviceB.store.update(bEdit, skipSync: true)
        deviceB.store.clearDirtyFlags()

        let bPush = try await deviceB.coordinator.push(events: [bEdit])
        XCTAssertEqual(bPush.pushed, 1, "B 的时间戳更新 → 其 v2 应被接受")
        let server = await deviceB.provider.serverGet(id: id.uuidString)
        XCTAssertEqual(try server?.decodedEvent().title, "B 版")

        let aPush = try await deviceA.coordinator.push(events: [aEdit])
        XCTAssertEqual(aPush.pushed, 0, "A 的等版本且更旧的 v2 应被拒")

        var converged = false
        for _ in 0..<5 {
            _ = try await deviceA.coordinator.syncBidirectional()
            _ = try await deviceB.coordinator.syncBidirectional()
            let a = deviceA.store.eventBy(idString: id.uuidString)?.title
            let b = deviceB.store.eventBy(idString: id.uuidString)?.title
            if let a, let b, a == b { converged = true; break }
        }
        XCTAssertTrue(converged, "另一方向的等版本分叉同样必须收敛")
        XCTAssertEqual(deviceA.store.eventBy(idString: id.uuidString)?.title, "B 版",
                       "时间戳更新的 B 版最终应胜出")
    }
}
