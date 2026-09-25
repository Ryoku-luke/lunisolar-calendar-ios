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

    /// 从 SolarTermProvider 构造下一个节气的 Live Activity 候选（文档 #29）。
    /// 节气是短生命周期事件：交节前后 2h 内才上岛，过后自动消失。
    /// 返回 nil 表示未来 24h 内无节气。
    public static func nextSolarTermCandidate(now: Date = Date()) -> QingheTimeCapsuleCandidate? {
        // 先处理“刚刚交节”的窗口。旧实现只查 nextTerm(from:)，
        // 在节气交节后的两小时内会直接跳到下一个节气，导致“节气已至”的 Live Activity
        // 永远无法进入时间胶囊。
        if let active = SolarTermProvider.termAround(now, window: 2 * 3600),
           active.date <= now {
            return QingheTimeCapsuleCandidate(
                eventID: stableSolarTermID(name: active.name, date: active.date),
                type: .solarTerm,
                priority: .normal,
                startDate: active.date,
                endDate: active.date.addingTimeInterval(2 * 3600),
                isAllDay: false
            )
        }

        guard let t = SolarTermProvider.nextTerm(from: now), t.daysRemaining <= 1 else { return nil }
        let end = t.date.addingTimeInterval(2 * 3600)
        return QingheTimeCapsuleCandidate(
            eventID: stableSolarTermID(name: t.name, date: t.date),
            type: .solarTerm,
            priority: .normal,
            startDate: t.date,
            endDate: end,
            isAllDay: false
        )
    }

    /// 节气没有 CalendarEvent ID，但候选需要稳定 ID 才能做到“同一节气就地更新”。
    /// 交节时间在现有数据集中唯一，因此直接由 Unix 时间戳构造确定性 UUID。
    private static func stableSolarTermID(name: String, date: Date) -> UUID {
        _ = name // 保留参数，便于未来同一时刻支持多来源节气数据。
        let seconds = Int64(date.timeIntervalSince1970)
        let suffix = String(format: "%012llx", seconds & 0x0000_FFFF_FFFF_FFFF)
        return UUID(uuidString: "00000000-0000-5000-8000-\(suffix)")!
    }

    /// 候选的**有效结束时刻**：显式结束时间优先；全天事件补一个隐式结束 = 当天 24:00。
    ///
    /// 为什么必须补：全天候选的 `endDate` 是 nil（表示"没有具体结束钟点"），而 `isLive`
    /// 的判据是 `endDate == nil || endDate >= now`，于是它一旦进入当天就**永远**「进行中」——
    /// 上周的全天高优先级日程会盖过今天真正相关的提醒、长期霸占灵动岛；
    /// 又因为没有结束时刻，岛上右侧的剩余时间三档文案全部落空，只剩图标和旧标题。
    static func effectiveEnd(of candidate: QingheTimeCapsuleCandidate) -> Date? {
        if let end = candidate.endDate { return end }
        guard candidate.isAllDay else { return nil }
        return QingheCalendarContext.userCalendar
            .startOfDay(for: candidate.startDate)
            .addingTimeInterval(24 * 60 * 60)
    }

    /// 该候选此刻是否「进行中」（live 判定与排序共用同一判据）
    static func isLive(_ candidate: QingheTimeCapsuleCandidate, now: Date) -> Bool {
        guard candidate.startDate <= now else { return false }
        guard let end = effectiveEnd(of: candidate) else { return true }
        return end >= now
    }

    /// 从候选集中选出最值得上岛的一个。
    public static func pickForIsland(
        from candidates: [QingheTimeCapsuleCandidate],
        now: Date = Date()
    ) -> QingheTimeCapsuleCandidate? {
        let horizon = now.addingTimeInterval(lookaheadWindow)

        // 入选时把「有效结束时刻」写回候选：下游（岛的剩余时间文案 / staleDate / 展开态）
        // 与 live 判定因此用的是同一份时间，不会一个说"进行中"、另一个算不出剩余时间。
        let eligible = candidates.compactMap { c -> QingheTimeCapsuleCandidate? in
            let live = isLive(c, now: now)
            let isUpcoming = c.startDate > now && c.startDate <= horizon
            guard live || isUpcoming else { return nil }
            return QingheTimeCapsuleCandidate(
                eventID: c.eventID, type: c.type, priority: c.priority,
                startDate: c.startDate, endDate: effectiveEnd(of: c), isAllDay: c.isAllDay
            )
        }
        guard !eligible.isEmpty else { return nil }

        return eligible.sorted { a, b in
            if a.priority != b.priority { return a.priority > b.priority }
            let aLive = isLive(a, now: now)
            let bLive = isLive(b, now: now)
            if aLive != bLive { return aLive }
            // 同优先级、同进行状态：先开始的优先（距当前最近的）
            return a.startDate < b.startDate
        }.first
    }
}
