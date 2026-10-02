import XCTest
@testable import LunisolarCalendarApp

// MARK: - 同步状态机：任何退出路径都必须离开 .inProgress（B3）
//
// 旧行为：`push()` 在开头设 `status = .inProgress(.push)`，但只在**正常走到末尾**时
//   设 .succeeded/.failed。一旦中途抛出（provider.isAvailable 失败、
//   编码/网络异常），status 永远停在 .inProgress(.push)。
//   设置页据此显示「同步中…」并**禁用**「立即同步」；而错误又被
//   `EventStore.flushDirtyAndDeleted` 吞进日志 → 用户看到"一直同步中、按钮点不动"
//   且没有任何提示，只能重启 App。复现：离线 + 任一 CRUD 编辑。
//
// 本文件锁定三条：① 失败必须落到 .failed；② 「未启用」路径不得被 inProgress 污染；
// ③ 成功必须落到 .succeeded。

@MainActor
final class SyncStatusTests: XCTestCase {

    private func makeDevice() async -> (store: EventStore, provider: MockCloudKitProvider,
                                       coordinator: EventSyncCoordinator) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lunisolar-status-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = EventStore(storageBaseDir: dir)
        for e in store.events { store.delete(e, skipSync: true) }
        store.clearDirtyFlags()

        let suite = "test.lunisolar.status.\(UUID().uuidString)"
        let td = UserDefaults(suiteName: suite) ?? .standard
        td.removePersistentDomain(forName: suite)
        td.removeObject(forKey: "Lunisolar.sync.lastSyncMs.lo")
        td.removeObject(forKey: "Lunisolar.sync.lastSyncMs.hi")
        td.removeObject(forKey: "Lunisolar.sync.versionMap")

        let provider = MockCloudKitProvider(deviceID: "dev-status", sharedStore: MockCloudKitStore())
        provider.simulatedLatencyMs = 0
        provider.isOnline = true
        provider.iCloudAvailable = true

        let coordinator = EventSyncCoordinator(eventStore: store, provider: provider, defaults: td)
        coordinator.resetSyncMetadata()
        coordinator.isEnabled = true
        store.syncCoordinator = coordinator
        return (store, provider, coordinator)
    }

    /// iCloud 不可用 → push 抛出 → status **不得**停在 .inProgress
    func testPushFailureLeavesInProgress() async throws {
        let (_, provider, coordinator) = await makeDevice()
        XCTAssertEqual(coordinator.status, .idle, "前置：初始应为 idle")

        provider.iCloudAvailable = false
        let event = CalendarEvent(title: "离线编辑", startDate: Date())

        do {
            _ = try await coordinator.push(events: [event])
            XCTFail("iCloud 不可用时 push 应抛出")
        } catch {
            // 期望就是抛错
        }

        if case .inProgress = coordinator.status {
            XCTFail("B3：push 抛出后 status 仍停在 .inProgress → 设置页会一直显示「同步中…」并禁用按钮")
        }
        guard case .failed = coordinator.status else {
            return XCTFail("push 失败后应为 .failed，实际：\(coordinator.status)")
        }
    }

    /// 网络不可用（provider 抛 networkUnavailable）同样必须离开 .inProgress
    func testPushNetworkFailureLeavesInProgress() async throws {
        let (_, provider, coordinator) = await makeDevice()
        provider.isOnline = false

        do {
            _ = try await coordinator.push(events: [CalendarEvent(title: "断网", startDate: Date())])
            XCTFail("断网时 push 应抛出")
        } catch {}

        XCTAssertFalse(isInProgress(coordinator.status),
                       "B3：断网 push 失败后不能停在 .inProgress（真机上就是这样卡死的："
                       + "provider.push 抛出 → status 永久 inProgress → 设置页显示「同步中…」且按钮禁用）")
        // 兜底复位不能把已分类的错误盖成 .unknown，否则设置页与日志都失去可诊断性
        XCTAssertEqual(coordinator.status, .failed(.networkUnavailable),
                       "断网应如实报 .networkUnavailable，而不是 .unknown")
    }

    private func isInProgress(_ s: SyncStatus) -> Bool {
        if case .inProgress = s { return true }
        return false
    }

    /// 「同步未启用」路径：status 必须保持原样（不能被 inProgress 污染）
    ///
    /// 这条是修 B3 时最容易踩的坑——若把 `status = .inProgress` 提到 isEnabled guard 之前，
    /// 关闭同步的用户会看到状态被反复改写，设置页的「未启用」提示失真。
    func testDisabledSyncDoesNotEnterInProgress() async throws {
        let (_, _, coordinator) = await makeDevice()
        coordinator.isEnabled = false
        XCTAssertEqual(coordinator.status, .idle, "前置：关闭同步后应为 idle")

        let statusBefore = coordinator.status
        let r = try await coordinator.push(events: [CalendarEvent(title: "不该推", startDate: Date())])
        XCTAssertEqual(r.pushed, 0, "未启用时不应推送")
        XCTAssertFalse(r.failedRecordIDs.isEmpty, "未启用时必须把入参标为未推送，让调用方保留脏标记")
        XCTAssertEqual(coordinator.status, statusBefore, "未启用路径必须保持 status 原样")
        if case .inProgress = coordinator.status {
            XCTFail("B3：关闭同步时进入 .inProgress 会永远卡住（该路径不抛错，没有复位点）")
        }
    }

    /// 成功路径必须落到 .succeeded
    func testPushSuccessLeavesSucceeded() async throws {
        let (_, _, coordinator) = await makeDevice()
        let r = try await coordinator.push(events: [CalendarEvent(title: "正常", startDate: Date())])
        XCTAssertEqual(r.pushed, 1)
        guard case .succeeded = coordinator.status else {
            return XCTFail("push 成功后应为 .succeeded，实际：\(coordinator.status)")
        }
    }
}
