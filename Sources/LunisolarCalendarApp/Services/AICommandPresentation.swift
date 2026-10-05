import Foundation

/// AI 指令的**展示/判定逻辑**（P4-2 ③：从 `AIAssistantView` 搬出的两个纯函数）。
///
/// 为什么单独成类型：它们不读不写任何视图状态（`draft` 是枚举的关联值，不是 `@State draft`），
/// 是纯函数 —— 搬出来就能**直接单测**，而此前这部分只有缓慢的 UI 流程覆盖。
/// 这也为后续"把 11 个 `@State` 与解析/执行逻辑整体移入 `@Observable` 模型"开了个头。
enum AICommandPresentation {
    static func destructiveCriteria(of command: AIStructuredCommand) -> AIEventCriteria? {
        switch command {
        case .deleteEvent(let draft): return draft.criteria
        case .updateEvent(let draft): return draft.criteria
        default: return nil
        }
    }

    static func destructiveLabel(for command: AIStructuredCommand) -> String {
        switch command {
        case .deleteEvent:
            return NSLocalizedString("确认删除 · 不可撤销", comment: "AI助手")
        case .updateEvent(let draft):
            let when = draft.newStartDate.formatted(date: .abbreviated, time: .shortened)
            return String(format: NSLocalizedString("确认修改 · 改到 %@", comment: "AI助手"), when)
        default:
            return ""
        }
    }
}
