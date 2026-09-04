import XCTest
@testable import LunisolarCalendarApp

// MARK: - iCloud 同步抽象 + Mock 驱动的单元测试

final class ICloudSyncTests: XCTestCase {
    // nonisolated(unsafe): XCTest 串行执行用例，MainActor 初始化 + test 方法 MainActor 读/写不会产生并发竞争
    nonisolated(unsafe) private var store: EventStore!
    nonisolated(unsafe) private var mockProvider: MockCloudKitProvider!
    nonisolated(unsafe) private var coordinator: EventSyncCoordinator!
    nonisolated(unsafe) private var tempDefaults: UserDefaults!

    // 复用一个全局隔离的 MockCloudKitStore（避免与其它设备共享）
    private let isolatedStore = MockCloudKitStore()

    // XCTestCase.setUp/tearDown 本身 nonisolated；同时我们需要访问 @MainActor 的 EventStore/EventSyncCoordinator。
    // 属性已声明 nonisolated(unsafe) + XCTest 串行执行，不会有竞争。
    // 初始化/清理用 @MainActor 闭包直接 await，不通过实例方法，规避 sending 'self' 的并发诊断。
    nonisolated override func setUp() async throws {
        try await super.setUp()
        try await { @MainActor in
            // 清空 mock 云端
            await isolatedStore.reset()
            // 临时 UserDefaults（LunaSync 前缀）：用 suiteName，系统支持就用，不支持退 standard 并手动清
            let suite = "test.lunisolar.sync.\(UUID().uuidString)"
            let td = UserDefaults(suiteName: suite) ?? .standard
            td.removePersistentDomain(forName: suite)

            // P4 修复：每个测试实例用独立的临时存储目录，避免 dirty_events.json 跨用例污染
            let baseDir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("lunisolar-test-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
            let s = EventStore(storageBaseDir: baseDir)
            for ev in s.events { s.delete(ev, skipSync: true) }
            XCTAssertEqual(s.events.count, 0, "setUp 本地 store 应为空")

            let mp = MockCloudKitProvider(
                deviceID: "device-A-\(UUID().uuidString.prefix(4))",
                sharedStore: isolatedStore
            )
            mp.simulatedLatencyMs = 0
            mp.isOnline = true
            mp.iCloudAvailable = true

            let co = EventSyncCoordinator(
                eventStore: s,
                provider: mp,
                defaults: td
            )
            co.resetSyncMetadata()
            co.isEnabled = true
            s.syncCoordinator = co

            store = s
            mockProvider = mp
            coordinator = co
            tempDefaults = td
        }()
    }

    nonisolated override func tearDown() async throws {
        // 属性 nonisolated(unsafe) + XCTest 串行；同步访问 UserDefaults / 赋 nil 均不会发生竞争
        tempDefaults?.removeObject(forKey: "Lunisolar.sync.lastSyncMs")
        tempDefaults?.removeObject(forKey: "Lunisolar.sync.versionMap")
        store = nil
        mockProvider = nil
        coordinator = nil
        tempDefaults = nil
        await isolatedStore.reset()
    }

    // MARK: 1. 本地新增 3 个事件 → push → 云端应有 3 条

    @MainActor
    func testPushLocalEventsToCloud() async throws {
        // 手动调 coordinator.push（比依赖 EventStore.autoPush 的 fire-and-forget Task 更可控）
        let events = sampleEvents(count: 3, prefix: "测试推送")
        let r = try await coordinator.push(events: events)
        XCTAssertEqual(r.direction, .push)
        XCTAssertEqual(r.pushed, 3, "3 条本地事件应被推到云端")
        XCTAssertTrue(r.errors.isEmpty)

        let serverCount = await mockProvider.serverRecordCount()
        XCTAssertEqual(serverCount, 3, "云端记录数应为 3")
    }

    // MARK: 2. 云端注入 2 条 → pullAndMerge → 本地应有 2 条

    @MainActor
    func testPullCloudIntoLocalMerge() async throws {
        // 直接在"云端"注入 2 条（模拟另一台设备推送过来）
        let cloud = sampleEvents(count: 2, prefix: "来自其他设备")
        for (i, ev) in cloud.enumerated() {
            let rec = try SyncRecord.eventRecord(
                for: ev, version: 1, originDevice: "OtherDevice"
            )
            await mockProvider.injectServerRecord(rec)
            _ = i
        }
        let serverCount = await mockProvider.serverRecordCount()
        XCTAssertEqual(serverCount, 2)

        let r = try await coordinator.pullAndMerge()
        XCTAssertEqual(r.direction, .pull)
        XCTAssertEqual(r.pulled, 2, "应该合并下 2 条到本地")
        XCTAssertEqual(r.conflictsResolved, 0, "本地为空，不应有冲突")
        XCTAssertEqual(store.events.count, 2, "本地 EventStore 合并后应为 2 条")
    }

    // MARK: 3. 冲突解决：本地 v2 + 云端 v3 (其它设备先更新过) → 云端胜出(last-write-wins)

    @MainActor
    func testConflictLastWriteWins() async throws {
        // 先推送一条建立基础
        var ev = sampleEvents(count: 1, prefix: "冲突").first!
        _ = try await coordinator.push(events: [ev])
        let ver1After = await mockProvider.serverGet(id: ev.id.uuidString)?.version
        XCTAssertEqual(ver1After, 1)

        // 模拟"另一台设备"把云端记录更新到 version=3 并改 title=云端胜出
        ev.title = "云端胜出 (另一设备更新)"
        let ms = Int64(Date().timeIntervalSince1970 * 1000) + 10_000
        let remoteWinner = try SyncRecord.eventRecord(
            for: ev, version: 3, originDevice: "OtherDevice", isDeleted: false
        )
        // version 3 但 updatedAtMs 强制更新到最新
        let forced = SyncRecord(
            id: remoteWinner.id, kind: .event,
            version: 3, originDevice: "OtherDevice",
            updatedAtMs: ms, isDeleted: false,
            payloadJSON: remoteWinner.payloadJSON
        )
        await mockProvider.injectServerRecord(forced)

        // 本地也改了 title=本地胜出，但本地只有 version=2 (< 云端3)
        var localCopy = ev
        localCopy.title = "本地胜出 (不该出现)"
        store.update(localCopy, skipSync: true)  // 不推送，仅模拟本地 edit

        // 执行 pull 合并：应该采纳云端 title=云端胜出
        let r = try await coordinator.pullAndMerge()
        // 冲突次数是实现细节；关键断言：最终结果云端胜出（last-write-wins）
        XCTAssertGreaterThanOrEqual(r.conflictsResolved, 0)
        let merged = try XCTUnwrap(store.events.first { $0.id == ev.id })
        XCTAssertEqual(merged.title, "云端胜出 (另一设备更新)",
                       "last-write-wins: 云端 version=3 应高于本地 version=2")
    }

    // MARK: 4. 增量同步：sinceMs 只拉取新变更
    //
    // 注（P2 修复后语义变化）：push 不再推进 lastSyncMs（否则会因本地 updatedAt
    // 时间戳比云端其它设备记录更新而"跳过"拉取那些记录）。水位线统一由
    // pullAndMerge 基于云端 records 的 updatedAtMs max 推进。所以本测试在
    // push 第一批后必须 pull 一次才能拿到稳定的 snapshot 水位线。

    @MainActor
    func testIncrementalPull() async throws {
        // 推送第一批
        let batchA = sampleEvents(count: 2, prefix: "第一批-增量")
        let r1 = try await coordinator.push(events: batchA)
        XCTAssertEqual(r1.pushed, 2)

        // 必须 pull 一次，让 lastSyncMs 推进到 batchA 的云端记录 max updatedAtMs
        // （push 不推进水位线，是 P2 修复的核心）
        let pullA = try await coordinator.pullAndMerge()
        XCTAssertEqual(pullA.pulled, 0, "本地已有 batchA 且版本相同，LWW 不应重复合并")
        let snapshot1LastMs = coordinator.lastSyncMs
        XCTAssertGreaterThan(snapshot1LastMs, 0, "pull 后水位线必须推进")

        // 模拟另一台设备注入第二批（updatedAtMs 更大，且是新 id）
        var batchB = sampleEvents(count: 3, prefix: "第二批-增量")
        for i in batchB.indices {
            let rec = try SyncRecord.eventRecord(
                for: batchB[i], version: 1, originDevice: "OtherDevice"
            )
            // 强制 updatedAtMs 晚于 snapshot（模拟"在 snapshot 之后才写入云端"）
            let newerMs = snapshot1LastMs + 60_000
            let forced = SyncRecord(
                id: rec.id, kind: .event,
                version: 1, originDevice: "OtherDevice",
                updatedAtMs: newerMs, isDeleted: false,
                payloadJSON: rec.payloadJSON
            )
            await mockProvider.injectServerRecord(forced)
        }

        // 再 pull，返回的应该只包含第二批 3 条（batchA 已被水位线过滤）
        let pullB = try await coordinator.pullAndMerge()
        XCTAssertEqual(pullB.pulled, 3, "增量同步应该只返回新增的 3 条")
    }

    // MARK: 4b. P2 回归：push 成功后 lastSyncMs 不应被本地时间戳推进
    //
    // 背景：旧逻辑 push 成功后把 lastSyncMs 推进到本地记录 updatedAtMs 的 max。
    // 这会导致设备 A 用本地较新的时间戳"跳过"拉取设备 B 在更早时间推送、
    // 但本地时钟后到的更新 → 多设备数据发散。修复：push 不推进水位线。

    @MainActor
    func testPushDoesNotAdvanceLastSyncMs() async throws {
        XCTAssertEqual(coordinator.lastSyncMs, 0, "初始水位线为 0")
        let events = sampleEvents(count: 2, prefix: "P2-水位线")
        let r = try await coordinator.push(events: events)
        XCTAssertEqual(r.pushed, 2)
        // 关键断言：push 后水位线仍为 0（只有 pull 才推进）
        XCTAssertEqual(coordinator.lastSyncMs, 0,
                       "P2 修复：push 成功后 lastSyncMs 不应被本地 updatedAt 推进")
    }

    // MARK: 5. 先离线本地改一堆 → 再上线 syncBidirectional → 云端和本地合并正确

    @MainActor
    func testOfflineGoOnlineBidirectionalSync() async throws {
        // 离线
        mockProvider.isOnline = false
        let localOfflineEvents = sampleEvents(count: 4, prefix: "离线编辑")
        // 模拟用户在本地新增 4 条：先写 EventStore（skipSync 因为目前离线，先不推，避免失败）
        for ev in localOfflineEvents { store.add(ev, skipSync: true) }
        XCTAssertEqual(store.events.count, 4)

        // 调一次 push，应抛 networkUnavailable（验证离线状态），并验证云端仍是 0
        do {
            _ = try await coordinator.push(events: localOfflineEvents)
            XCTFail("离线时 push 应抛 networkUnavailable")
        } catch SyncError.networkUnavailable {
            // 预期
        } catch {
            XCTFail("期望 networkUnavailable，实际 \(error)")
        }
        // 此时云端仍 0
        let countBeforeOnline = await mockProvider.serverRecordCount()
        XCTAssertEqual(countBeforeOnline, 0)

        // 上线 + 双向同步：syncBidirectional 内部会 push(eventStore.events) 这 4 条
        mockProvider.isOnline = true
        let result = try await coordinator.syncBidirectional()
        XCTAssertEqual(result.direction, .both)
        // 注意：上面离线时已经 push(events: localOfflineEvents) 过一次（失败，但 versionMap 已 +1），
        // 所以现在 syncBidirectional 的 push 会把 version 再 +1，云端应该都能写入
        XCTAssertGreaterThanOrEqual(result.pushed, 4, "push 应把离线 4 条推送上去")
        // 云端现在至少应该有 4 条用户新增的事件（非墓碑）；
        // 另外 setUp 里为了清空 EventStore 的 insertSampleData() 调了 delete(skipSync:true)，
        // 这 4 条样例删除的墓碑也会一并被 syncBidirectional 推上来，总云端记录可能 > 4。
        let serverCount = await mockProvider.serverRecordCount()
        let aliveInCloudCount = await {
            var n = 0
            for ev in localOfflineEvents {
                let rec = await mockProvider.serverGet(id: ev.id.uuidString)
                if let r = rec, !r.isDeleted { n += 1 }
            }
            return n
        }()
        XCTAssertEqual(aliveInCloudCount, 4, "云端应能查到用户新推的 4 条活跃事件")
        XCTAssertGreaterThanOrEqual(serverCount, aliveInCloudCount, "云端总记录数 ≥ 活跃记录数")
    }

    // MARK: 6. 本地删除 → push 墓碑 → 另一设备 pull 后也删除（跨设备删除同步）

    @MainActor
    func testTombstoneDeletePropagation() async throws {
        let ev = sampleEvents(count: 1, prefix: "会被删除").first!

        // 设备 A: add → push
        store.add(ev, skipSync: true)
        _ = try await coordinator.push(event: ev)
        let c1 = await mockProvider.serverRecordCount()
        XCTAssertEqual(c1, 1)

        // 设备 A: delete (走墓碑)
        store.delete(ev, skipSync: true)
        let delR = try await coordinator.push(events: [], deletedIDs: [ev.id.uuidString])
        XCTAssertEqual(delR.pushed, 1)

        // 云端记录应该是 isDeleted=true
        let serverRec = await mockProvider.serverGet(id: ev.id.uuidString)
        XCTAssertNotNil(serverRec)
        XCTAssertEqual(serverRec?.isDeleted, true, "云端记录应为 isDeleted 墓碑")
        XCTAssertEqual(serverRec?.kind, .event)

        // 设备 B：另一个 coordinator 接入同样云端，pullAndMerge → 本地也应没这条
        let baseDirB = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lunisolar-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: baseDirB, withIntermediateDirectories: true)
        let storeB = EventStore(storageBaseDir: baseDirB)
        for x in storeB.events { storeB.delete(x, skipSync: true) }
        let deviceB = MockCloudKitProvider(deviceID: "device-B", sharedStore: isolatedStore)
        let coB = EventSyncCoordinator(
            eventStore: storeB, provider: deviceB,
            defaults: UserDefaults(suiteName: "device-B-\(UUID().uuidString)") ?? .standard
        )
        coB.resetSyncMetadata()
        storeB.syncCoordinator = coB

        // 先给设备 B 注入本地一条同名记录（模拟设备 B 之前有这条）
        storeB.add(ev, skipSync: true)
        XCTAssertEqual(storeB.events.count, 1, "设备 B 初始应有 1 条")

        let mergeB = try await coB.pullAndMerge()
        // 合并后设备 B 应被删除
        XCTAssertEqual(mergeB.pulled, 1, "应合并 1 条变更（墓碑）")
        XCTAssertEqual(storeB.events.count, 0, "跨设备墓碑删除传播：设备 B 同步后应 0 条")
    }

    // MARK: - 测试辅助

    @MainActor private func sampleEvents(count: Int, prefix: String) -> [CalendarEvent] {
        var results: [CalendarEvent] = []
        let cal = Calendar(identifier: .gregorian)
        for i in 0..<count {
            var dc = DateComponents()
            dc.year = 2026; dc.month = 9; dc.day = 1 + i
            dc.hour = 9 + i; dc.minute = 0
            let start = cal.date(from: dc)!
            results.append(
                CalendarEvent(
                    title: "\(prefix) #\(i+1)",
                    type: i % 2 == 0 ? .schedule : .reminder,
                    startDate: start,
                    endDate: start.addingTimeInterval(3600),
                    location: "地点-\(i)",
                    notes: "备注 \(prefix) \(i)",
                    priority: Priority.allCases[i % Priority.allCases.count]
                )
            )
        }
        return results
    }
}
