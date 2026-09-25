import Foundation

// MARK: - 清和时间胶囊 · 上岛内容与同步决策（纯逻辑，平台无关）
//
// 文档 #24：EventService → QingheActivityCoordinator → QingheLiveActivityManager → ActivityKit。
// 本文件只放「快照 + 决策」纯值类型，不依赖 ActivityKit，Linux 单测可覆盖；
// ActivityKit 侧（QingheLiveActivityWidget / Manager）在 Widgets/QingheLiveActivity.swift。

/// 上岛内容快照：用于幂等复用与 diff 决策（可 Equatable 比较）。
public struct QingheTimeCapsuleDisplay: Equatable, Sendable {
    public let eventID: UUID
    public let type: QingheActivityType
    public let phase: QingheActivityPhase
    public let title: String
    public let icon: String
    public let startDate: Date
    public let endDate: Date?
    public let countdownTarget: Date?
    public let isImportant: Bool

    public init(eventID: UUID, type: QingheActivityType, phase: QingheActivityPhase,
                title: String, icon: String, startDate: Date, endDate: Date?,
                countdownTarget: Date?, isImportant: Bool) {
        self.eventID = eventID
        self.type = type
        self.phase = phase
        self.title = title
        self.icon = icon
        self.startDate = startDate
        self.endDate = endDate
        self.countdownTarget = countdownTarget
        self.isImportant = isImportant
    }
}

/// 同步决策结果（纯函数输出）。
public enum QingheActivitySyncAction: Equatable, Sendable {
    /// 当前无活动且目标非空 → 新建
    case start
    /// 同事件内容变化 → 更新
    case update
    /// 目标为空，或 current/target 是不同事件。
    /// 后者（切换候选）由调用方负责撤掉旧活动，且顺序必须是**先上新、后撤旧**：
    /// 旧的 end 是异步的，先撤会让新活动 request 落进旧活动仍存活的窗口。
    case end
    /// 内容一致 → 什么都不做（幂等）
    case none
}

/// 幂等 diff：决定「开始 / 更新 / 结束 / 不动」。
/// 规则：
/// - target == nil：current 非空 → end，否则 none；
/// - current == nil：target 非空 → start；
/// - 同 eventID 且关键内容相同 → none；
/// - 同 eventID 内容不同 → update；
/// - 不同 eventID → end（调用方随后 start 新事件）。
public enum QingheLiveActivityLifecycle {
    public static func decision(
        current: QingheTimeCapsuleDisplay?,
        target: QingheTimeCapsuleDisplay?
    ) -> QingheActivitySyncAction {
        guard let target else {
            return (current == nil) ? .none : .end
        }
        guard let current else { return .start }
        guard current.eventID == target.eventID else { return .end }
        // 同事件：比较可渲染内容（标题/图标/阶段/时间/重要度）
        let sameContent =
            current.title == target.title
            && current.icon == target.icon
            && current.phase == target.phase
            && current.startDate == target.startDate
            && current.endDate == target.endDate
            && current.countdownTarget == target.countdownTarget
            && current.isImportant == target.isImportant
        return sameContent ? .none : .update
    }
}
