import Foundation

/// AI 助手的状态容器（P4-2 ③：把 11 个 `@State` 从视图里集中出来）。
///
/// 为什么集中：这 11 个状态**全部**被 body 与解析/执行逻辑同时读写（2026-10-05 实测：
/// 60 处引用 / 40 处写入，没有一个是"只被一边用"），散在视图里导致逻辑无法独立测试。
/// 集中之后下一步才能把解析/执行逻辑也搬进来，从而**脱离 UI 单测**。
///
/// ⚠️ 用法要点（P4-1 5b-1 的实测教训）：
/// - 使用点直接写 `x`，**不要**用"带 setter 的转发计算属性"——它在 `View` 的
///   逃逸闭包里不可赋值（结构体不可变），而 `@State` 之所以能用是因为 `nonmutating set`；
/// - 需要绑定时（本视图仅 2 处）在 `body` 里加 `@Bindable var model = model` 再写 `$x`。
/// ⚠️ `@MainActor`：`showSuccess` 里用 `Task { @MainActor in … }` 在休眠后回写状态，
/// 若不隔离，Swift 6 会报 "sending 'self' risks causing data races"（实测）。
/// 该模型只被 SwiftUI 视图（本身即主 actor）使用，标 `@MainActor` 语义上也是对的。
@Observable
@MainActor
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

    // MARK: - 结果状态的两个变更口（P4-2 ③-2 第一片：从视图搬进来）
    //
    // 这两个方法只写模型自己的状态、不依赖任何外部服务 —— 搬进来后就能**脱离 UI 单测**，
    // 这正是 ③-2 的目的。（`showSuccess` 含 Task/@MainActor 的并发细节，留到专门一步再搬。）

    /// 行内错误提示
    func present(_ error: AICommandError) {
        inlineError = error.message
    }

    /// 一次交互走完后的复位（输入与草稿一起清掉）
    func resetAfterCompletion() {
        input = ""
        draft = nil
        destructiveTarget = nil
        destructiveLabel = nil
        pendingCommand = nil
    }

    // MARK: - 成功提示（P4-2 ③-2b：含 Task/休眠，单独一步搬入）
    //
    // 带行动按钮的提示停留更久：2 秒够读一句纯文案，但不够「读日期 → 决定 → 点按钮」。
    // 这是 UX 取值，要调只动这两个常量。
    static let plainSuccessDwell: Duration = .seconds(2)
    static let actionableSuccessDwell: Duration = .seconds(6)

    func showSuccess(_ text: String, offDay: Date? = nil) {
        inlineError = nil
        completedOffDay = offDay
        completedMessage = text
        // 带行动按钮的提示停留更久：2 秒够读一句纯文案，但不够「读日期 → 决定 → 点按钮」。
        // 「去看看」正是那次真机反馈的补救路径，抢不到就等于没做；UI 测试也不该跟秒表赛跑。
        // 这是 UX 取值，要调只动这两个常量。
        let dwell: Duration = offDay == nil ? Self.plainSuccessDwell : Self.actionableSuccessDwell
        Task { @MainActor in
            try? await Task.sleep(for: dwell)
            if completedMessage == text {
                completedMessage = nil
                completedOffDay = nil
            }
        }
    }
}
