import Foundation

// MARK: - 清和时间胶囊 · 基础模型（文档 #20-24）

/// Live Activity 业务阶段（文档 #21）。
/// 生命周期：scheduled → upcoming → live → ending → completed；
/// `stale` 是系统内容状态，不当作业务阶段推进。
public enum QingheActivityPhase: String, Codable, Hashable, Sendable {
    case scheduled
    case upcoming
    case live
    case ending
    case completed
    case stale
}

/// Live Activity 类型（文档 #22）。
public enum QingheActivityType: String, Codable, Hashable, Sendable {
    case event
    case reminder
    case countdown
    case anniversary
    case solarTerm
}

/// 时间胶囊候选优先级（文档 #25：normal → important → urgent）。
public enum QingheActivityPriority: Int, Codable, Hashable, Sendable, Comparable {
    case normal = 0
    case important = 1
    case urgent = 2

    public static func < (lhs: QingheActivityPriority, rhs: QingheActivityPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
