import Foundation

/// AI 助手的状态容器（P4-2 ③：把 11 个 `@State` 从视图里集中出来）。
///
/// 为什么集中：这 11 个状态**全部**被 body 与解析/执行逻辑同时读写（2026-10-05 实测：
/// 60 处引用 / 40 处写入，没有一个是"只被一边用"），散在视图里导致逻辑无法独立测试。
/// 集中之后下一步才能把解析/执行逻辑也搬进来，从而**脱离 UI 单测**。
///
/// ⚠️ 用法要点（P4-1 5b-1 的实测教训）：
/// - 使用点直接写 `model.x`，**不要**用"带 setter 的转发计算属性"——它在 `View` 的
///   逃逸闭包里不可赋值（结构体不可变），而 `@State` 之所以能用是因为 `nonmutating set`；
/// - 需要绑定时（本视图仅 2 处）在 `body` 里加 `@Bindable var model = model` 再写 `$model.x`。
@Observable
final class AIAssistantModel {
    /// 输入框文本
    var input: String = ""
    /// 解析出的创建草稿（确认卡）
    var draft: AICreateEventDraft?
    /// 查询结果（只读快照）
    var queryResults: [CalendarEvent]?
    /// 查询结果对应的日期（用于标题）
    var queryDate: Date?
    /// 破坏性操作的目标与说明
    var destructiveTarget: CalendarEvent?
    var destructiveLabel: String?
    /// 待执行的命令（破坏性操作确认后执行）
    var pendingCommand: AIStructuredCommand?
    /// 完成提示（成功文案 + 可选的休息日）
    var completedMessage: String?
    var completedOffDay: Date?
    /// 行内错误
    var inlineError: String?
    /// 输入框焦点
    var inputFocused: Bool = false
}
