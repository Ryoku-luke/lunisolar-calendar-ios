import Foundation

// MARK: - 同步错误 & 结果类型

/// 云同步通用错误（抽象 CloudKit / 任意后端，不绑定具体实现）
public enum SyncError: Error, Equatable, Hashable, Sendable {
    case notAvailable            // 无 iCloud 账号 / 框架未链接 / 容器未启用
    case networkUnavailable      // 无网络
    case permissionDenied        // 用户拒绝 iCloud Drive/CloudKit 权限
    case quotaExceeded           // iCloud 容量超限
    case conflict(String)        // 冲突（关联冲突记录 ID）
    case recordNotFound(String)  // 指定记录云端不存在 (传 recordID)
    case invalidPayload(String)  // 编解码失败 / 数据损坏
    case rateLimited             // 请求过频，建议指数退避
    case unknown(String)         // 其它，保留原始描述
}

/// 同步方向
public enum SyncDirection: String, Sendable, CaseIterable {
    case push    // 本地 → 云端
    case pull    // 云端 → 本地
    case both    // 双向合并
}

/// 单次同步操作结果
public struct SyncResult: Equatable, Hashable, Sendable {
    public let direction: SyncDirection
    public let pushed: Int
    public let pulled: Int
    public let conflictsResolved: Int
    public let errors: [SyncError]
    public let startedAt: Date
    public let finishedAt: Date

    public init(direction: SyncDirection, pushed: Int, pulled: Int,
                conflictsResolved: Int, errors: [SyncError],
                startedAt: Date, finishedAt: Date) {
        self.direction = direction
        self.pushed = pushed
        self.pulled = pulled
        self.conflictsResolved = conflictsResolved
        self.errors = errors
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }

    public var duration: TimeInterval { finishedAt.timeIntervalSince(startedAt) }
    public var isSuccess: Bool { errors.isEmpty }
}

/// 同步状态（用于 UI 展示 / 协调器状态机）
public enum SyncStatus: Equatable, Hashable, Sendable {
    case idle
    case inProgress(SyncDirection)
    case succeeded(SyncResult)
    case failed(SyncError)
}

// MARK: - 同步记录模型（通用中间层，解耦 CalendarEvent ↔ CloudKit Record）

/// 任意事件在"同步层"的通用表达。字段设计对应 CloudKit 私有数据库 Custom Zone 的 CKRecord 字段。
/// 未来换 RealCloudKitProvider 只要做 SyncRecord <-> CKRecord 映射即可。
public struct SyncRecord: Equatable, Hashable, Identifiable, Sendable {
    /// 全局唯一 recordID（建议 event.id.uuidString；跨设备必须一致）
    public let id: String
    /// 实体类型：目前就是 CalendarEvent，留枚举位未来加 memo/settings
    public enum Kind: String, Codable, Sendable { case event }
    public let kind: Kind
    /// 版本号（用于冲突解决：数值越大越新，last-write-wins）
    public let version: Int64
    /// 最后更新方（设备 UUID 或 user-defined），用于冲突调试/展示
    public let originDevice: String
    /// 最后修改时间（毫秒时间戳，跨时区一致）
    public let updatedAtMs: Int64
    /// 是否已删除（tombstone 墓碑：真删不立即删云端，先发 delete=true，TTL 30 天再清）
    public let isDeleted: Bool
    /// 负载：JSONEncoded CalendarEvent（或任意 Codable 模型）
    public let payloadJSON: String

    public init(id: String, kind: Kind, version: Int64, originDevice: String,
                updatedAtMs: Int64, isDeleted: Bool, payloadJSON: String) {
        self.id = id
        self.kind = kind
        self.version = version
        self.originDevice = originDevice
        self.updatedAtMs = updatedAtMs
        self.isDeleted = isDeleted
        self.payloadJSON = payloadJSON
    }

    /// helper: 从 CalendarEvent 构造 SyncRecord（JSON 编码 payload）
    public static func eventRecord(
        for event: CalendarEvent,
        version: Int64,
        originDevice: String,
        isDeleted: Bool = false,
        encoder: JSONEncoder = SyncCoders.encoder
    ) throws -> SyncRecord {
        let data = try encoder.encode(event)
        guard let json = String(data: data, encoding: .utf8) else {
            throw SyncError.invalidPayload("CalendarEvent -> UTF8 失败")
        }
        let ms = Int64(event.updatedAt.timeIntervalSince1970 * 1000)
        return SyncRecord(
            id: event.id.uuidString,
            kind: .event,
            version: version,
            originDevice: originDevice,
            updatedAtMs: ms,
            isDeleted: isDeleted,
            payloadJSON: json
        )
    }

    /// helper: 反解出 CalendarEvent
    public func decodedEvent(decoder: JSONDecoder = SyncCoders.decoder) throws -> CalendarEvent {
        guard let data = payloadJSON.data(using: .utf8) else {
            throw SyncError.invalidPayload("SyncRecord.payloadJSON 非 UTF8")
        }
        return try decoder.decode(CalendarEvent.self, from: data)
    }
}

// MARK: - Coders（统一 Date 策略，避免时区问题）

public enum SyncCoders {
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

// MARK: - iCloud 同步抽象协议

/// iCloud/CloudKit 同步提供者抽象：
/// - MockCloudKitProvider: 内存实现，本地测试/Preview/Linux 可用
/// - RealCloudKitProvider: 未来接入真实 CKContainer（iOS/macOS 真机）
public protocol ICloudSyncProvider: AnyObject, Sendable {

    /// 账户状态：true=当前有可用 iCloud 账号且容器已启用
    var isAvailable: Bool { get async }

    /// 当前本机设备唯一标识（UUID 生成后持久化到 UserDefaults，冲突时显示"来自 XX 设备的修改"）
    var currentDeviceID: String { get }

    // MARK: - 推送 (本地 → 云端)

    /// 批量推送一批记录。返回值：成功写入的条数 + 每条对应错误
    func push(records: [SyncRecord]) async throws -> (written: Int, errors: [String: SyncError])

    // MARK: - 拉取 (云端 → 本地)

    /// 增量拉取：since 为上次同步时间戳（毫秒），传 0 表示全量
    func pull(sinceMs: Int64) async throws -> [SyncRecord]

    // MARK: - 删除

    /// 按 ID 删除一批（本质：写入 isDeleted=true 的墓碑）
    func delete(recordIDs: [String]) async throws -> (deletedCount: Int, errors: [String: SyncError])

    // MARK: - 变更订阅（可选，实时 sync）

    /// 注册/注销 CloudKit 订阅。返回 true=成功注册，false=后端不支持或失败
    func setupSubscription(enabled: Bool) async -> Bool

    // MARK: - 墓碑 TTL 清理

    /// 物理删除「isDeleted=true 且 updatedAtMs < olderThanMs」的过期墓碑记录。
    /// 返回被真正物理删除的条数。默认 TTL 30 天（= 30 * 86400 * 1000 ms）。
    func purgeExpiredTombstones(olderThanMs: Int64) async throws -> Int
}
