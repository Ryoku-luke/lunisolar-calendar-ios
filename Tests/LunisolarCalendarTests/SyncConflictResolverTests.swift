import XCTest
@testable import LunisolarCalendarApp

// MARK: - 同步冲突解决契约测试（P1-1）
//
// 背景：修复前 `MockCloudKitProvider` 与 `RealCloudKitProvider` **各自实现**了
// last-write-wins，且语义不同——Mock 会拒绝「陈旧推送」，Real 只取 change tag 就
// 无条件覆盖。所有同步测试只跑 Mock，所以真机上的分叉在 CI 里永远看不见。
//
// 本文件做两件事：
//   1) 把 LWW 规则当纯函数测（`RealCloudKitProvider` 无法在测试进程构造，
//      它做了 entitlement 预检、容器恒为 nil，所以规则必须可脱离 CloudKit 验证）；
//   2) 用**同一组断言**跑 Mock，锁定 Provider 行为与纯规则一致（契约测试）。
//
// ⚠️ 新增 Provider 时请把 `testContract_*` 那组断言也接到它上面，
// 否则「两个 Provider 漂移」这个 bug 会以另一种形式回来。

final class SyncConflictResolverTests: XCTestCase {

    private func rec(_ id: String, version: Int64, updatedAtMs: Int64,
                     isDeleted: Bool = false, device: String = "dev-A") -> SyncRecord {
        SyncRecord(id: id, kind: .event, version: version, originDevice: device,
                   updatedAtMs: updatedAtMs, isDeleted: isDeleted, payloadJSON: "{}")
    }

    // MARK: - 纯规则

    /// 云端没有该记录 → 接受（新增）
    func testAcceptsWhenServerHasNoRecord() {
        XCTAssertEqual(
            SyncConflictResolver.resolve(incoming: rec("a", version: 1, updatedAtMs: 100),
                                         existing: nil),
            .accept
        )
    }

    /// 版本更高 → 接受（正常前进方向）
    func testAcceptsHigherVersion() {
        XCTAssertEqual(
            SyncConflictResolver.resolve(incoming: rec("a", version: 3, updatedAtMs: 100),
                                         existing: rec("a", version: 2, updatedAtMs: 999)),
            .accept,
            "版本更高必须胜出，即使时间戳更旧（版本是单调前进的权威信号）"
        )
    }

    /// **P1-1 核心**：云端版本更高 → 必须拒绝。
    /// 修复前 Real 会在这里覆盖云端，导致低版本回滚高版本 → 设备间永久分叉。
    func testRejectsLowerVersionAgainstNewerServer() {
        XCTAssertEqual(
            SyncConflictResolver.resolve(incoming: rec("a", version: 2, updatedAtMs: 999),
                                         existing: rec("a", version: 5, updatedAtMs: 100)),
            .rejectHigherVersionOnServer,
            "陈旧设备（低版本）不得覆盖云端更新记录——这就是 P1-1 的数据分叉路径"
        )
    }

    /// 版本相等：时间戳不更旧 → 接受（重复推送幂等通过）
    func testAcceptsEqualVersionWithEqualOrNewerTimestamp() {
        XCTAssertEqual(
            SyncConflictResolver.resolve(incoming: rec("a", version: 2, updatedAtMs: 500),
                                         existing: rec("a", version: 2, updatedAtMs: 500)),
            .accept, "同版本同时间戳（重复推送）应幂等接受"
        )
        XCTAssertEqual(
            SyncConflictResolver.resolve(incoming: rec("a", version: 2, updatedAtMs: 600),
                                         existing: rec("a", version: 2, updatedAtMs: 500)),
            .accept, "同版本但时间戳更新 → 接受"
        )
    }

    /// 版本相等但时间戳更旧 → 拒绝
    func testRejectsEqualVersionWithOlderTimestamp() {
        XCTAssertEqual(
            SyncConflictResolver.resolve(incoming: rec("a", version: 2, updatedAtMs: 400),
                                         existing: rec("a", version: 2, updatedAtMs: 500)),
            .rejectHigherVersionOnServer
        )
    }

    /// 便捷重载与主入口必须同结论（防两套实现漂移）
    func testFieldOverloadMatchesRecordOverload() {
        let cases: [(Int64, Int64, Int64, Int64)] = [
            (1, 100, 1, 100), (1, 100, 2, 100), (3, 100, 2, 999),
            (2, 400, 2, 500), (2, 600, 2, 500), (0, 0, 0, 0)
        ]
        for (iv, im, ev, em) in cases {
            XCTAssertEqual(
                SyncConflictResolver.resolve(incoming: rec("a", version: iv, updatedAtMs: im),
                                             existing: rec("a", version: ev, updatedAtMs: em)),
                SyncConflictResolver.resolve(incomingVersion: iv, incomingUpdatedAtMs: im,
                                             existingVersion: ev, existingUpdatedAtMs: em),
                "重载结论不一致：incoming v\(iv)/\(im) vs existing v\(ev)/\(em)"
            )
        }
    }

    /// 墓碑（isDeleted）也走同一套版本规则——删除不该有特权
    func testTombstoneUsesSameVersionRule() {
        XCTAssertEqual(
            SyncConflictResolver.resolve(incoming: rec("a", version: 1, updatedAtMs: 100, isDeleted: true),
                                         existing: rec("a", version: 2, updatedAtMs: 100)),
            .rejectHigherVersionOnServer,
            "低版本墓碑不得删掉云端更高版本的活记录"
        )
        XCTAssertEqual(
            SyncConflictResolver.resolve(incoming: rec("a", version: 3, updatedAtMs: 100, isDeleted: true),
                                         existing: rec("a", version: 2, updatedAtMs: 100)),
            .accept
        )
    }

    // MARK: - pull 侧规则

    func testShouldAdoptRemoteOnlyWhenStrictlyNewer() {
        XCTAssertTrue(SyncConflictResolver.shouldAdoptRemote(remoteVersion: 3, localVersion: 2))
        XCTAssertFalse(SyncConflictResolver.shouldAdoptRemote(remoteVersion: 2, localVersion: 2),
                       "等版本不采纳（避免把远端回声当新数据；收敛需再推一轮）")
        XCTAssertFalse(SyncConflictResolver.shouldAdoptRemote(remoteVersion: 1, localVersion: 2))
        XCTAssertTrue(SyncConflictResolver.shouldAdoptRemote(remoteVersion: 1, localVersion: 0),
                      "本地从未见过该记录（v0）→ 采纳")
    }

    // MARK: - 契约测试：Mock Provider 必须与纯规则同结论
    //
    // 这组断言就是「Mock / Real 不得漂移」的可执行形式。
    // 接入新 Provider 时，把下面 4 个场景照抄一遍即可。

    @MainActor
    func testContract_MockProviderMatchesSharedRule() async throws {
        let server = MockCloudKitStore()
        let provider = MockCloudKitProvider(deviceID: "dev-A", sharedStore: server)
        let id = "contract-1"

        // 1) 云端无记录 → 推送成功
        var r = try await provider.push(records: [rec(id, version: 1, updatedAtMs: 100)])
        XCTAssertEqual(r.written, 1, "云端无记录应写入")
        XCTAssertTrue(r.errors.isEmpty)
        var serverRec = await provider.serverGet(id: id)
        XCTAssertEqual(serverRec?.version, 1)

        // 2) 云端 v2，本地也推 v2 但时间戳更新 → 按规则应接受（同版本比较时间戳）
        r = try await provider.push(records: [rec(id, version: 2, updatedAtMs: 999)])
        XCTAssertEqual(r.written, 1, "同版本且时间戳更新 → 接受")
        serverRec = await provider.serverGet(id: id)
        XCTAssertEqual(serverRec?.updatedAtMs, 999)

        // 3) 云端更高版本（5），本地推 v3 → 必须被拒（P1-1 契约核心）
        await provider.injectServerRecord(rec(id, version: 5, updatedAtMs: 100, device: "dev-B"))
        r = try await provider.push(records: [rec(id, version: 3, updatedAtMs: 999)])
        XCTAssertEqual(r.written, 0, "v3 不得覆盖云端 v5——修复前 Real 正是在这里覆盖")
        guard case .conflict = r.errors[id] else {
            return XCTFail("必须返回 .conflict，实际：\(String(describing: r.errors[id]))")
        }
        serverRec = await provider.serverGet(id: id)
        XCTAssertEqual(serverRec?.version, 5, "云端版本不得被回滚")

        // 4) 版本更高 → 接受
        r = try await provider.push(records: [rec(id, version: 6, updatedAtMs: 200)])
        XCTAssertEqual(r.written, 1, "v6 > 云端 v5，应写入")
        serverRec = await provider.serverGet(id: id)
        XCTAssertEqual(serverRec?.version, 6)
    }

    /// 契约的一致性由「同一函数」保证，这条测试锁定 Mock 的 store.upsert 也走同一规则
    /// （即直接 upsert 低版本也不会回滚云端）。
    @MainActor
    func testContract_MockStoreUpsertRejectsLowerVersion() async {
        let server = MockCloudKitStore()
        await server.upsert(rec("x", version: 5, updatedAtMs: 100))
        let changed = await server.upsert(rec("x", version: 3, updatedAtMs: 999))
        XCTAssertFalse(changed, "低版本 upsert 不应发生变更")
        let after = await server.get("x")
        XCTAssertEqual(after?.version, 5, "云端版本必须保持 5")
    }
}
