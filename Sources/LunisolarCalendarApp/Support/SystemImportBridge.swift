import Foundation

// MARK: - 系统导入桥：DTO + 协议 + Mapper（Linux 全可测，无 EventKit/Contacts 依赖）

/// 从系统日历 / 联系人 抽出来的"中性数据"，与 EventKit/Contacts 解耦。
/// 这样 Mapper 逻辑（DTO → CalendarEvent）能在 Linux 上单测，iOS 只负责"采集"。
public struct SystemImportEvent: Sendable, Equatable {
    /// 源平台稳定标识（避免重复导入时同一条目产生两个 UUID）
    /// - 日历：EKEvent.eventIdentifier
    /// - 联系人："contact-birthday:<contactID>" / "contact-anniversary:<contactID>"
    public let sourceID: String

    public let title: String
    public let startDate: Date
    public let endDate: Date?
    public let isAllDay: Bool
    public let location: String?
    public let notes: String?

    /// 重复规则（已映射为本 App 的 RepeatRule；联系人生日=yearly 或 lunarAnnually）
    public let repeatRule: RepeatRule

    /// 导入后用哪种事件类型：日历事件=schedule，联系人生日/纪念日=reminder
    public let eventType: EventType

    /// 优先级（联系人紧急事项给 high，普通日历日程给 normal）
    public let priority: Priority

    public init(
        sourceID: String,
        title: String,
        startDate: Date,
        endDate: Date? = nil,
        isAllDay: Bool = false,
        location: String? = nil,
        notes: String? = nil,
        repeatRule: RepeatRule = .never,
        eventType: EventType = .schedule,
        priority: Priority = .normal
    ) {
        self.sourceID = sourceID
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.repeatRule = repeatRule
        self.eventType = eventType
        self.priority = priority
    }
}

// MARK: - 导入源协议（iOS 真实实现 + Linux 占位实现都遵循这个）

public enum SystemImportSource: String, Sendable, CaseIterable {
    case systemCalendar   // 系统日历（EventKit.EKEvent）
    case contacts         // 联系人（CNContact 生日/纪念日）

    public var displayName: String {
        switch self {
        case .systemCalendar: return "系统日历"
        case .contacts:       return "联系人"
        }
    }
}

public enum SystemImportError: Error, Equatable, Sendable {
    case unauthorized(source: SystemImportSource)
    case restricted(source: SystemImportSource)
    case fetchFailed(source: SystemImportSource, message: String)
    case unavailable(source: SystemImportSource)   // 平台不支持（Linux）
}

public protocol SystemImportProviding: Sendable {
    var source: SystemImportSource { get }
    /// 申请权限（返回是否已授权；denied 时抛 unauthorized 让 UI 引导去系统设置）
    func requestAuthorization() async throws -> Bool
    /// 拉取原始 DTO 列表（已映射成 SystemImportEvent，调用方只需 merge）
    func fetchEvents() async throws -> [SystemImportEvent]
}

// MARK: - Mapper：SystemImportEvent → CalendarEvent

/// 把 DTO 映射为 App 内的 CalendarEvent。源稳定 ID → 确定性 UUID（同 sourceID 二次导入不会产生副本）
public enum SystemImportMapper {

    /// 把 sourceID 映射成确定性 UUID（基于 sourceID 的 SHA-1 前 16 字节 → UUID）
    /// 这样同一条系统事件多次导入都走 merge 的"同 id 更新"分支，不会重复
    public nonisolated static func toCalendarEvent(_ dto: SystemImportEvent) -> CalendarEvent {
        let uuid = deterministicUUID(from: dto.sourceID)
        var ev = CalendarEvent(
            id: uuid,
            title: dto.title,
            type: dto.eventType,
            startDate: dto.startDate,
            endDate: dto.endDate,
            isAllDay: dto.isAllDay,
            location: dto.location,
            notes: dto.notes,
            repeatRule: dto.repeatRule,
            priority: dto.priority
        )
        // 系统事件导入后默认不通知（用户可在 App 内手动开启）
        ev.isNotified = false
        return ev
    }

    /// 批量映射并过滤无效项（标题空 / endDate<=startDate 由 EventStore.merge 再兜底）
    public nonisolated static func toCalendarEvents(_ dtos: [SystemImportEvent]) -> [CalendarEvent] {
        dtos.map(toCalendarEvent)
    }

    /// 用 sourceID 生成确定性 UUID：NSUUID(uuidBytes:) 接收 16 字节
    /// 在 Linux 上没有 NSUUID，用 Foundation.UUID(uuid:) 同样接收 16 字节
    public static func deterministicUUID(from sourceID: String) -> UUID {
        let bytes = sha1First16Bytes(of: sourceID)
        return UUID(uuid: bytes)
    }

    // MARK: - SHA-1（截断到 16 字节）
    // 极简实现：只为生成稳定 UUID，不需要密码学强度；Linux/Foundation 都能跑

    private static func sha1First16Bytes(of input: String) -> (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) {
        let data = Array(input.utf8)
        let h0: UInt32 = 0x67452301, h1: UInt32 = 0xEFCDAB89
        let h2: UInt32 = 0x98BADCFE, h3: UInt32 = 0x10325476, h4: UInt32 = 0xC3D2E1F0
        var msg = data
        let origLen = UInt64(data.count) * 8
        msg.append(0x80)
        while msg.count % 64 != 56 { msg.append(0) }
        for i in (0..<8).reversed() { msg.append(UInt8((origLen >> (UInt64(i) * 8)) & 0xFF)) }

        var hh0 = h0, hh1 = h1, hh2 = h2, hh3 = h3, hh4 = h4
        for chunkStart in stride(from: 0, to: msg.count, by: 64) {
            var w = [UInt32](repeating: 0, count: 80)
            for i in 0..<16 {
                let s = chunkStart + i * 4
                w[i] = (UInt32(msg[s]) << 24) | (UInt32(msg[s+1]) << 16) | (UInt32(msg[s+2]) << 8) | UInt32(msg[s+3])
            }
            for i in 16..<80 {
                w[i] = leftRotate(w[i-3] ^ w[i-8] ^ w[i-14] ^ w[i-16], by: 1)
            }
            var a = hh0, b = hh1, c = hh2, d = hh3, e = hh4
            for i in 0..<80 {
                let f: UInt32, k: UInt32
                switch i {
                case 0..<20:  f = (b & c) | ((~b) & d);          k = 0x5A827999
                case 20..<40: f = b ^ c ^ d;                    k = 0x6ED9EBA1
                case 40..<60: f = (b & c) | (b & d) | (c & d);  k = 0x8F1BBCDC
                default:      f = b ^ c ^ d;                    k = 0xCA62C1D6
                }
                let temp = leftRotate(a, by: 5) &+ f &+ e &+ k &+ w[i]
                e = d; d = c; c = leftRotate(b, by: 30); b = a; a = temp
            }
            hh0 = hh0 &+ a; hh1 = hh1 &+ b; hh2 = hh2 &+ c; hh3 = hh3 &+ d; hh4 = hh4 &+ e
        }
        let bytes: [UInt8] = [
            UInt8((hh0 >> 24) & 0xFF), UInt8((hh0 >> 16) & 0xFF), UInt8((hh0 >> 8) & 0xFF), UInt8(hh0 & 0xFF),
            UInt8((hh1 >> 24) & 0xFF), UInt8((hh1 >> 16) & 0xFF), UInt8((hh1 >> 8) & 0xFF), UInt8(hh1 & 0xFF),
            UInt8((hh2 >> 24) & 0xFF), UInt8((hh2 >> 16) & 0xFF), UInt8((hh2 >> 8) & 0xFF), UInt8(hh2 & 0xFF),
            UInt8((hh3 >> 24) & 0xFF), UInt8((hh3 >> 16) & 0xFF), UInt8((hh3 >> 8) & 0xFF), UInt8(hh3 & 0xFF)
        ]
        return (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])
    }

    private static func leftRotate(_ x: UInt32, by n: UInt32) -> UInt32 {
        (x << n) | (x >> (32 - n))
    }
}

// MARK: - Linux / 非 EventKit 平台的占位 Provider（让单测能跑）

public struct StubSystemImportProvider: SystemImportProviding {
    public let source: SystemImportSource
    private let events: [SystemImportEvent]
    private let authorized: Bool

    public init(source: SystemImportSource, events: [SystemImportEvent], authorized: Bool = true) {
        self.source = source
        self.events = events
        self.authorized = authorized
    }

    public func requestAuthorization() async throws -> Bool { authorized }

    public func fetchEvents() async throws -> [SystemImportEvent] {
        guard authorized else { throw SystemImportError.unauthorized(source: source) }
        return events
    }
}

// MARK: - 聚合：把多个 Provider 的结果合并成一份 CalendarEvent 数组

public enum SystemImportAggregator {

    /// 并发拉取所有 Provider（任意一个失败不阻塞其他源，错误计入 failures）
    public static func gather(
        providers: [SystemImportProviding],
        conflictPolicy: ImportConflictPolicy = .keepLatest
    ) async -> (events: [CalendarEvent], failures: [SystemImportError]) {
        var dtos: [SystemImportEvent] = []
        var failures: [SystemImportError] = []
        for p in providers {
            do {
                let list = try await p.fetchEvents()
                dtos.append(contentsOf: list)
            } catch let e as SystemImportError {
                failures.append(e)
            } catch {
                failures.append(.fetchFailed(source: p.source, message: String(describing: error)))
            }
        }
        let mapped = SystemImportMapper.toCalendarEvents(dtos)
        // 注意：此处不直接 merge 进 EventStore；让调用方（SettingsView/EventStore）统一 merge，
        // 这样可以复用现有的冲突策略与 Toast 提示
        return (mapped, failures)
    }
}
