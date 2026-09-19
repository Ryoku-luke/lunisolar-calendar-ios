import Foundation

// MARK: - 清和时间胶囊 · 协调器（文档 #25）

/// 时间胶囊候选（去 UI 化的纯数据）。
public struct QingheTimeCapsuleCandidate: Equatable, Sendable {
    public let eventID: UUID
    public let type: QingheActivityType
    public let priority: QingheActivityPriority
    public let startDate: Date
    public let endDate: Date?
    public let isAllDay: Bool

    public init(eventID: UUID, type: QingheActivityType, priority: QingheActivityPriority,
                startDate: Date, endDate: Date?, isAllDay: Bool) {
        self.eventID = eventID
        self.type = type
        self.priority = priority
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
    }
}

/// 决定"当前哪个事件应该进入时间胶囊"（文档 #25）。
///
/// V1 规则（文档 #20：同一时间只维护一个主要时间胶囊）：
/// 1. 只看"正在进行"或"未来 24h 内开始"的候选；
/// 2. 普通日程 / 记事不参与（由调用方过滤，不产生候选）；
/// 3. 排序：优先级（urgent > important > normal）→ 进行中优先 →
///    距开始时间近者优先；
/// 4. 无合格候选 → nil（不强制上岛）。
public enum QingheActivityCoordinator {
    /// 时间胶囊候选窗口：未来 24h 内开始的事件可进入
    public static let lookaheadWindow: TimeInterval = 24 * 60 * 60

    /// 从候选集中选出最值得上岛的一个。
    public static func pickForIsland(
        from candidates: [QingheTimeCapsuleCandidate],
        now: Date = Date()
    ) -> QingheTimeCapsuleCandidate? {
        let horizon = now.addingTimeInterval(lookaheadWindow)

        let eligible = candidates.filter { c in
            let isLive = c.startDate <= now && (c.endDate == nil || c.endDate! >= now)
            let isUpcoming = c.startDate > now && c.startDate <= horizon
            return isLive || isUpcoming
        }
        guard !eligible.isEmpty else { return nil }

        return eligible.sorted { a, b in
            if a.priority != b.priority { return a.priority > b.priority }
            let aLive = a.startDate <= now && (a.endDate == nil || a.endDate! >= now)
            let bLive = b.startDate <= now && (b.endDate == nil || b.endDate! >= now)
            if aLive != bLive { return aLive }
            // 同优先级、同进行状态：先开始的优先（距当前最近的）
            return a.startDate < b.startDate
        }.first
    }
}
