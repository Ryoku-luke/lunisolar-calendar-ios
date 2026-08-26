import Foundation

// MARK: - 真实 CloudKit 提供者

// CloudKit 仅在 Apple 平台（iOS/macOS）可用；Linux 构建时整个文件跳过。
// 测试继续使用 MockCloudKitProvider（不依赖真实 iCloud 账号）。

#if canImport(CloudKit)
import CloudKit

/// 真实 CloudKit 同步提供者：
///
/// - 私有数据库 + Custom Zone（`LunisolarZone`，首次同步自动创建）
/// - RecordType: `CalendarEvent`
/// - 字段映射 `SyncRecord` ↔ `CKRecord`（version / originDevice / updatedAtMs / isDeleted / payloadJSON）
/// - push：先批量 fetch 取得 change tag → 修改字段 → `CKModifyRecordsOperation`（`.ifServerRecordUnchanged`）
/// - pull：`CKQuery`（`updatedAtMs > sinceMs`）+ cursor 分页
/// - delete：写墓碑记录（`isDeleted=1`），不直接物理删除
/// - subscription：`CKQuerySubscription`（zone 级变更推送）
public final class RealCloudKitProvider: ICloudSyncProvider, @unchecked Sendable {

    // MARK: - 配置

    public let containerIdentifier: String?
    public let zoneName: String
    public let recordType: String
    public let currentDeviceID: String

    /// iCloud 容器（nil identifier → `CKContainer.default()`）
    private let container: CKContainer
    /// 私有数据库（iOS 17+：`database(with: .private)`）
    private let database: CKDatabase
    /// Custom Zone（事件记录隔离区，支持增量查询与墓碑）
    private let zone: CKRecordZone

    // MARK: - 内部状态

    /// Zone 是否已确认存在（避免每次同步都 fetch zone）
    private var zoneEnsured = false
    /// 防止 ensureZoneExists 并发重入
    private let zoneLock = NSLock()

    // MARK: - accountStatus 会话级缓存（10s TTL，避免双向同步内 3 次重复 IPC）

    private let availabilityCacheLock = NSLock()
    private var cachedAvailability: Bool?
    private var cachedAvailabilityAt: TimeInterval = 0
    private let availabilityCacheTTL: TimeInterval = 10  // 10 秒内复用结果
    /// 账户状态切换时（设置里登出/登入 iCloud）外部可主动清缓存
    public func invalidateAvailabilityCache() {
        availabilityCacheLock.lock()
        defer { availabilityCacheLock.unlock() }
        cachedAvailability = nil
        cachedAvailabilityAt = 0
    }

    // MARK: - Init

    public init(
        containerIdentifier: String? = nil,
        zoneName: String = "LunisolarZone",
        recordType: String = "CalendarEvent",
        deviceID: String? = nil
    ) {
        self.containerIdentifier = containerIdentifier
        self.zoneName = zoneName
        self.recordType = recordType
        if let cid = containerIdentifier {
            self.container = CKContainer(identifier: cid)
        } else {
            self.container = .default()
        }
        self.database = container.database(with: .private)
        self.zone = CKRecordZone(zoneName: zoneName)

        // 设备 ID：跨启动稳定，持久化到 UserDefaults
        let key = "Lunisolar.sync.deviceID"
        if let stored = UserDefaults.standard.string(forKey: key) {
            self.currentDeviceID = stored
        } else {
            let id = deviceID ?? UUID().uuidString
            UserDefaults.standard.set(id, forKey: key)
            self.currentDeviceID = id
        }
    }

    // MARK: - ICloudSyncProvider

    public var isAvailable: Bool {
        get async {
            let now = Date().timeIntervalSince1970
            // 1) 快路径：读取缓存（lock 包裹，线程安全）
            availabilityCacheLock.lock()
            if let cached = cachedAvailability,
               now - cachedAvailabilityAt < availabilityCacheTTL {
                availabilityCacheLock.unlock()
                return cached
            }
            availabilityCacheLock.unlock()

            // 2) 慢路径：真实查 accountStatus
            let result: Bool
            do {
                let status = try await container.accountStatus()
                switch status {
                case .available: result = true
                case .noAccount, .restricted, .couldNotDetermine, .temporarilyUnavailable:
                    result = false
                @unknown default: result = false
                }
            } catch {
                result = false
            }

            // 3) 写回缓存
            availabilityCacheLock.lock()
            cachedAvailability = result
            cachedAvailabilityAt = now
            availabilityCacheLock.unlock()
            return result
        }
    }

    public func push(records: [SyncRecord]) async throws -> (written: Int, errors: [String: SyncError]) {
        try await ensureZoneExists()
        guard !records.isEmpty else { return (0, [:]) }

        let zoneID = zone.zoneID
        let ids = records.map { CKRecord.ID(recordName: $0.id, zoneID: zoneID) }

        // 1. 批量 fetch 现有记录（取得 change tag，避免 serverRecordChanged 冲突）
        let fetchResults = await fetchRecords(ids: ids)

        // 2. 组装 CKRecord：现有的修改字段，不存在的新建
        var ckRecords: [CKRecord] = []
        for r in records {
            let recordID = CKRecord.ID(recordName: r.id, zoneID: zoneID)
            if case .success(let existing) = fetchResults[recordID] {
                apply(r, to: existing)
                ckRecords.append(existing)
            } else {
                let fresh = CKRecord(recordType: recordType, recordID: recordID)
                apply(r, to: fresh)
                ckRecords.append(fresh)
            }
        }

        // 3. 批量保存
        let (saved, failed) = try await saveBatch(ckRecords)
        var errors: [String: SyncError] = [:]
        for (recordID, err) in failed {
            errors[recordID.recordName] = mapCKError(err)
        }
        return (saved.count, errors)
    }

    public func pull(sinceMs: Int64) async throws -> [SyncRecord] {
        try await ensureZoneExists()
        let predicate: NSPredicate
        if sinceMs > 0 {
            predicate = NSPredicate(format: "updatedAtMs > %lld", sinceMs)
        } else {
            predicate = NSPredicate(value: true)
        }
        let query = CKQuery(recordType: recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "updatedAtMs", ascending: true)]

        var allRecords: [SyncRecord] = []
        var cursor: CKQueryOperation.Cursor?

        // 首次查询
        var page = try await runQuery(query: query, cursor: nil)
        allRecords.append(contentsOf: page.records)
        cursor = page.cursor

        // cursor 翻页
        while let c = cursor {
            page = try await runQuery(query: nil, cursor: c)
            allRecords.append(contentsOf: page.records)
            cursor = page.cursor
        }
        return allRecords
    }

    public func delete(recordIDs: [String]) async throws -> (deletedCount: Int, errors: [String: SyncError]) {
        try await ensureZoneExists()
        guard !recordIDs.isEmpty else { return (0, [:]) }

        // P12 修复：如果用户绕过 Coordinator 直调 delete，version=1 会被云端已存在的 version>1 拒绝
        // （last-write-wins）。此处先 FETCH 云端现有 version，取 max(existing, 0) + 1，保证永远前进。
        let existingVersions = try await fetchVersions(of: recordIDs)
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var tombstones: [SyncRecord] = []
        for id in recordIDs {
            let existingV = existingVersions[id] ?? 0
            let tomb = SyncRecord(
                id: id, kind: .event,
                version: existingV + 1,
                originDevice: currentDeviceID,
                updatedAtMs: now, isDeleted: true, payloadJSON: "{}"
            )
            tombstones.append(tomb)
        }
        let (written, errs) = try await push(records: tombstones)
        return (written, errs)
    }

    /// 根据 id 列表从 CloudKit 查 {id: existingVersion}，不存在的 id 不返回（调用者当作 0 处理）
    private func fetchVersions(of ids: [String]) async throws -> [String: Int64] {
        guard !ids.isEmpty else { return [:] }
        let recordNames = ids
        let predicate = NSPredicate(format: "recordID.recordName IN %@", recordNames)
        let query = CKQuery(recordType: recordType, predicate: predicate)
        var result: [String: Int64] = [:]
        var cursor: CKQueryOperation.Cursor?
        var page = try await runQuery(query: query, cursor: nil)
        for r in page.records { result[r.id] = r.version }
        cursor = page.cursor
        while let c = cursor {
            page = try await runQuery(query: nil, cursor: c)
            for r in page.records { result[r.id] = r.version }
            cursor = page.cursor
        }
        return result
    }

    public func setupSubscription(enabled: Bool) async -> Bool {
        guard enabled else {
            do {
                try await database.deleteSubscription(withID: subscriptionID)
                return true
            } catch {
                return false
            }
        }
        do {
            try await ensureZoneExists()
            let predicate = NSPredicate(value: true)
            let subscription = CKQuerySubscription(
                recordType: recordType,
                predicate: predicate,
                subscriptionID: subscriptionID
            )
            let info = CKSubscription.NotificationInfo()
            info.shouldSendContentAvailable = true
            subscription.notificationInfo = info
            _ = try await database.save(subscription)
            return true
        } catch {
            return false
        }
    }

    // MARK: - 墓碑 TTL 清理（P3）：物理删除 30 天前的 isDeleted=true 记录

    public func purgeExpiredTombstones(olderThanMs: Int64) async throws -> Int {
        try await ensureZoneExists()

        // 1) 查询所有 isDeleted == 1 的 CKRecord（翻页）
        let predicate = NSPredicate(format: "isDeleted == 1")
        let query = CKQuery(recordType: recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "updatedAtMs", ascending: true)]

        var allTombstones: [(CKRecord.ID, Int64)] = []
        var cursor: CKQueryOperation.Cursor?
        var page = try await runQueryRaw(query: query, cursor: nil)
        allTombstones.append(contentsOf: page.tombstones)
        cursor = page.cursor
        while let c = cursor {
            page = try await runQueryRaw(query: nil, cursor: c)
            allTombstones.append(contentsOf: page.tombstones)
            cursor = page.cursor
        }

        // 2) 过滤 updatedAtMs < olderThanMs 的过期墓碑
        let expiredIDs = allTombstones
            .filter { $0.1 < olderThanMs }
            .map { $0.0 }
        guard !expiredIDs.isEmpty else { return 0 }

        // 3) 用 CKModifyRecordsOperation(recordsToSave:nil, recordIDsToDelete:expiredIDs) 物理删除
        let (_, failedDeletes) = await deleteBatch(recordIDsToDelete: expiredIDs)
        return expiredIDs.count - failedDeletes.count
    }

    // MARK: - Zone 管理

    private func ensureZoneExists() async throws {
        zoneLock.lock()
        let alreadyEnsured = zoneEnsured
        zoneLock.unlock()
        if alreadyEnsured { return }

        do {
            _ = try await database.recordZone(for: zone.zoneID)
        } catch let error as CKError where error.code == .zoneNotFound {
            do {
                _ = try await database.save(zone)
            } catch {
                throw mapCKError(error)
            }
        } catch {
            throw mapCKError(error)
        }

        zoneLock.lock()
        zoneEnsured = true
        zoneLock.unlock()
    }

    // MARK: - CKRecord ↔ SyncRecord 映射

    private func apply(_ rec: SyncRecord, to ck: CKRecord) {
        ck["kind"] = rec.kind.rawValue as NSString
        ck["version"] = NSNumber(value: rec.version)
        ck["originDevice"] = rec.originDevice as NSString
        ck["updatedAtMs"] = NSNumber(value: rec.updatedAtMs)
        ck["isDeleted"] = NSNumber(value: rec.isDeleted ? 1 : 0)
        ck["payloadJSON"] = rec.payloadJSON as NSString
    }

    private func toSyncRecord(_ ck: CKRecord) -> SyncRecord? {
        guard let kindStr = ck["kind"] as? String,
              let kind = SyncRecord.Kind(rawValue: kindStr),
              let originDevice = ck["originDevice"] as? String,
              let payload = ck["payloadJSON"] as? String,
              let version = int64Value("version", from: ck),
              let updatedAtMs = int64Value("updatedAtMs", from: ck),
              let isDeletedInt = int64Value("isDeleted", from: ck)
        else { return nil }

        return SyncRecord(
            id: ck.recordID.recordName,
            kind: kind,
            version: version,
            originDevice: originDevice,
            updatedAtMs: updatedAtMs,
            isDeleted: isDeletedInt != 0,
            payloadJSON: payload
        )
    }

    private func int64Value(_ key: String, from ck: CKRecord) -> Int64? {
        guard let value = ck[key] else { return nil }
        if let v = value as? Int64 { return v }
        if let v = value as? Int { return Int64(v) }
        if let n = value as? NSNumber { return n.int64Value }
        return nil
    }

    // MARK: - 批量 fetch（取得 change tag）

    private func fetchRecords(ids: [CKRecord.ID]) async -> [CKRecord.ID: Result<CKRecord, Error>] {
        guard !ids.isEmpty else { return [:] }
        let op = CKFetchRecordsOperation(recordIDs: ids)
        op.qualityOfService = .utility

        return await withCheckedContinuation { (cont: CheckedContinuation<[CKRecord.ID: Result<CKRecord, Error>], Never>) in
            var results: [CKRecord.ID: Result<CKRecord, Error>] = [:]

            op.perRecordResultBlock = { recordID, result in
                results[recordID] = result
            }

            op.fetchRecordsResultBlock = { _ in
                cont.resume(returning: results)
            }
            database.add(op)
        }
    }

    // MARK: - 批量保存

    private func saveBatch(_ records: [CKRecord]) async throws -> (saved: [CKRecord], failed: [(CKRecord.ID, Error)]) {
        guard !records.isEmpty else { return ([], []) }
        let op = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
        op.savePolicy = .ifServerRecordUnchanged
        op.qualityOfService = .utility

        return try await withThrowingCheckedContinuation { (cont: CheckedContinuation<(saved: [CKRecord], failed: [(CKRecord.ID, Error)]), Error>) in
            var saved: [CKRecord] = []
            var failed: [(CKRecord.ID, Error)] = []

            op.perRecordCompletionBlock = { record, error in
                if let error = error {
                    failed.append((record.recordID, error))
                } else {
                    saved.append(record)
                }
            }

            op.modifyRecordsResultBlock = { _ in
                cont.resume(returning: (saved, failed))
            }
            database.add(op)
        }
    }

    // MARK: - 查询 + cursor 翻页（完整版：解析为 SyncRecord）

    private func runQuery(query: CKQuery?, cursor: CKQueryOperation.Cursor?) async throws
        -> (records: [SyncRecord], cursor: CKQueryOperation.Cursor?) {

        let op: CKQueryOperation
        if let cursor = cursor {
            op = CKQueryOperation(cursor: cursor)
        } else if let query = query {
            op = CKQueryOperation(query: query)
        } else {
            return ([], nil)
        }
        op.zoneID = zone.zoneID
        op.qualityOfService = .utility
        op.resultsLimit = 100

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(records: [SyncRecord], cursor: CKQueryOperation.Cursor?), Error>) in
            var records: [SyncRecord] = []
            var nextCursor: CKQueryOperation.Cursor?

            op.recordMatchedBlock = { _, result in
                switch result {
                case .success(let ck):
                    if let sync = self.toSyncRecord(ck) {
                        records.append(sync)
                    }
                case .failure:
                    break
                }
            }
            op.queryResultBlock = { result in
                switch result {
                case .success(let cursor):
                    nextCursor = cursor
                    cont.resume(returning: (records, nextCursor))
                case .failure(let error):
                    cont.resume(throwing: error)
                }
            }
            database.add(op)
        }
    }

    // MARK: - 查询 + cursor 翻页（轻量版：只取 recordID + updatedAtMs，用于墓碑 TTL 扫描）

    private func runQueryRaw(query: CKQuery?, cursor: CKQueryOperation.Cursor?) async throws
        -> (tombstones: [(CKRecord.ID, Int64)], cursor: CKQueryOperation.Cursor?) {

        let op: CKQueryOperation
        if let cursor = cursor {
            op = CKQueryOperation(cursor: cursor)
        } else if let query = query {
            op = CKQueryOperation(query: query)
        } else {
            return ([], nil)
        }
        op.zoneID = zone.zoneID
        op.qualityOfService = .utility
        op.resultsLimit = 200  // 墓碑轻量查询每页可多一些

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(tombstones: [(CKRecord.ID, Int64)], cursor: CKQueryOperation.Cursor?), Error>) in
            var tombstones: [(CKRecord.ID, Int64)] = []
            var nextCursor: CKQueryOperation.Cursor?

            op.recordMatchedBlock = { recordID, result in
                switch result {
                case .success(let ck):
                    if let ms = self.int64Value("updatedAtMs", from: ck) {
                        tombstones.append((recordID, ms))
                    }
                case .failure:
                    break
                }
            }
            op.queryResultBlock = { result in
                switch result {
                case .success(let cursor):
                    nextCursor = cursor
                    cont.resume(returning: (tombstones, nextCursor))
                case .failure(let error):
                    cont.resume(throwing: error)
                }
            }
            database.add(op)
        }
    }

    // MARK: - 批量物理删除（配合墓碑 TTL 使用）

    private func deleteBatch(recordIDsToDelete: [CKRecord.ID]) async
        -> (deletedIDs: [CKRecord.ID], failed: [(CKRecord.ID, Error)]) {
        guard !recordIDsToDelete.isEmpty else { return ([], []) }
        let op = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordIDsToDelete)
        op.savePolicy = .ifServerRecordUnchanged
        op.qualityOfService = .utility

        return try await withThrowingCheckedContinuation { (cont: CheckedContinuation<(deletedIDs: [CKRecord.ID], failed: [(CKRecord.ID, Error)]), Error>) in
            var deletedIDs: [CKRecord.ID] = []
            var failed: [(CKRecord.ID, Error)] = []

            op.perRecordCompletionBlock = { record, error in
                let recordID = record.recordID
                if let error = error {
                    failed.append((recordID, error))
                } else {
                    deletedIDs.append(recordID)
                }
            }

            op.modifyRecordsResultBlock = { _ in
                cont.resume(returning: (deletedIDs, failed))
            }
            database.add(op)
        }
    }

    // MARK: - CKError → SyncError 映射

    private func mapCKError(_ error: Error) -> SyncError {
        guard let ckError = error as? CKError else {
            return .unknown(String(describing: error))
        }
        switch ckError.code {
        case .serviceUnavailable, .requestRateLimited:
            return .rateLimited
        case .quotaExceeded:
            return .quotaExceeded
        case .networkUnavailable, .networkFailure:
            return .networkUnavailable
        case .notAuthenticated, .managedAccountRestricted:
            return .permissionDenied
        case .zoneNotFound:
            return .notAvailable
        case .serverRecordChanged:
            let rid = ckError.serverRecord?.recordID.recordName ?? ""
            return .conflict(rid)
        case .unknownItem:
            return .recordNotFound("")
        case .constraintViolation:
            return .invalidPayload(ckError.localizedDescription)
        default:
            return .unknown(ckError.localizedDescription)
        }
    }

    // MARK: - 订阅 ID

    private var subscriptionID: String { "LunisolarSync-\(recordType)" }
}

#endif // canImport(CloudKit)
