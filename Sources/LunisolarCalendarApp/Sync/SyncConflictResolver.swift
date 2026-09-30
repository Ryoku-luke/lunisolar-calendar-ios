import Foundation

// MARK: - 同步冲突解决契约（Mock 与 Real 必须共用同一套规则）
//
// 为什么单独抽出来：
//
// 修复前，Mock 与 Real **各自实现**了 last-write-wins，且两者语义不同：
//   - `MockCloudKitProvider.push`：显式比对 version 与 updatedAtMs，输了返回 per-record `.conflict`
//   - `RealCloudKitProvider.push`：只 fetch 现有记录拿 change tag，**然后无条件覆盖所有字段**
//
// 后果（P1-1，2026-09-30 审查发现）：真机上持有陈旧 `versionMap` 的设备会用自己的
// **更低版本**覆盖云端更新的记录，其他设备再在 `EventSyncCoordinator.pullAndMerge`
// 的 `remoteRec.version > localVersion` 处丢弃它 → **永久分叉**。
// 而所有同步测试只跑 Mock，所以这个差异在 CI 里永远看不见。
//
// 把规则收成一个纯函数后：
//   1) 两个 Provider 无法再各自漂移；
//   2) 规则本身可脱离 CloudKit 单测（`RealCloudKitProvider` 在测试进程里无法构造——
//      它做了 entitlement 预检，容器恒为 nil）。
public enum SyncConflictResolver {

    /// 一条记录与云端现存记录比较后的结论
    public enum Resolution: Equatable, Sendable {
        /// 应写入云端（版本更高，或版本相同但时间戳不更旧）
        case accept
        /// 不应写入：云端更新。调用方应把该记录记为 per-record `.conflict`，
        /// **保留其脏标记**等待下一轮；随后的 pull 会先追平版本，下轮 push 即可通过。
        case rejectHigherVersionOnServer

        public var isAccepted: Bool { self == .accept }
    }

    /// last-write-wins 判定。
    ///
    /// 规则（**与修复前的 Mock 行为逐字一致**，抽出时不改变语义）：
    /// 1. 云端不存在该 id → 接受（新增）；
    /// 2. `incoming.version > existing.version` → 接受；
    /// 3. 版本相等时比 `updatedAtMs`：**不更旧**（`>=`）即接受 —— 这样同一秒内的
    ///    重复推送不会因为相等而被拒；也更新的编辑能覆盖旧编辑；
    /// 4. 其余（版本更低，或版本相等但时间戳更旧）→ 拒绝。
    ///
    /// ⚠️ 不要为了让"等版本分叉"更快收敛而放宽第 3 条的边界或删掉版本比较：
    /// 版本号是单调前进的（每次本地编辑 +1），一旦允许**更低版本**覆盖更高版本，
    /// 陈旧的离线设备就能回滚其他设备的新数据——这正是 P1-1 要修的那个 bug。
    public static func resolve(incoming: SyncRecord, existing: SyncRecord?) -> Resolution {
        guard let existing else { return .accept }
        if incoming.version > existing.version { return .accept }
        if incoming.version == existing.version && incoming.updatedAtMs >= existing.updatedAtMs {
            return .accept
        }
        return .rejectHigherVersionOnServer
    }

    /// 便捷重载：只给字段（避免调用方为比较而临时构造 SyncRecord）
    public static func resolve(incomingVersion: Int64, incomingUpdatedAtMs: Int64,
                              existingVersion: Int64, existingUpdatedAtMs: Int64) -> Resolution {
        if incomingVersion > existingVersion { return .accept }
        if incomingVersion == existingVersion && incomingUpdatedAtMs >= existingUpdatedAtMs {
            return .accept
        }
        return .rejectHigherVersionOnServer
    }

    /// 该记录被拒绝时应写给调用方的错误（两个 Provider 用同一措辞，便于日志比对）
    public static func rejectionError(incoming: SyncRecord, existing: SyncRecord) -> SyncError {
        .conflict("LWW: server v=\(existing.version) > incoming v=\(incoming.version)")
    }
}

// MARK: - pull 侧的同一条规则
//
// push 侧与 pull 侧必须用**同一个方向性判断**，否则会出现「推得上、拉不回」的不对称死锁：
//   - push 说「本地 v3 > 云端 v2 → 接受」
//   - pull 也必须说「云端 v3 > 本地 v2 → 采纳」
// 反之亦然。把 pull 的判定也收到这里，是为了让两端永远同源。
extension SyncConflictResolver {

    /// pull 合并时：远端记录是否应采纳到本地。
    /// - Parameters:
    ///   - localVersion: `versionMap[remoteRec.id] ?? 0`（本地追踪到的该记录版本）
    ///   - remoteVersion: 云端记录的版本
    ///
    /// 规则：仅当 `remoteVersion > localVersion` 时采纳。
    ///
    /// **等版本分叉如何收敛**（要求 3，由 `SyncDivergenceConvergenceTests` 锁住）：
    /// 两台设备从同一 base 各自编辑（都 v1 → 都 v2）时，先到云端的一方胜出；
    /// 落后一方本地已记 v2，因此**不采纳**云端的 v2 —— 但它也不会推进增量水位线
    /// （见 `EventSyncCoordinator.pullAndMerge`：只有被采纳/按墓碑删除的记录才允许推进），
    /// 于是下轮 pull 仍能拿到那条记录，在自己 push 被拒后重试，最终两端收敛到云端权威版本。
    /// 实测**一轮 sync 即收敛**。
    ///
    /// ⚠️ 不要把这里放宽成 `>=`（"等版本也采纳"）来图省事：那会让
    /// **被云端拒绝、仍带脏标记的本地编辑**被服务端版本覆盖，等于静默吞掉用户更改。
    public static func shouldAdoptRemote(remoteVersion: Int64, localVersion: Int64) -> Bool {
        remoteVersion > localVersion
    }
}
