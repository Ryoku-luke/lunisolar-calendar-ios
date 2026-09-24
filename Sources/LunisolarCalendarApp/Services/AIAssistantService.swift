import Foundation

// MARK: - AI 助手应用服务（docs #35 / #41：AI 只能经 Domain 层写数据）
//
// 职责：把已解析的自然语言命令落到数据层。
// 约束（红线）：
// - 唯一写入路径是 EventService（→ EventStore），绝不由本类直接操作
//   EventStore / JSON 文件 / CloudKit / WidgetKit；
// - 执行前必定经过 AICommandValidator，任何调用者都无法绕过校验；
// - 通知调度、Widget 刷新、同步入队都由 EventService/EventStore 既有链路负责。

@MainActor
public final class AIAssistantService {
    public static let shared = AIAssistantService()

    /// 事件写入通道。默认 App 单例；测试注入隔离实例（避免写入真实 Documents）。
    private let eventService: EventService

    public init(eventService: EventService = .shared) {
        self.eventService = eventService
    }

    /// 解析 + 校验 + 执行的一站式入口（UI 也可分两步调用 Parser/Validator 以做预览）。
    public func handle(_ input: String, now: Date = Date()) -> Result<UUID, AICommandError> {
        switch AICommandParser.parse(input, baseDate: now) {
        case .failure(let error):
            return .failure(error)
        case .success(let command):
            return execute(command, now: now)
        }
    }

    /// 执行结构化命令（先校验，再经 EventService 写入）。
    @discardableResult
    public func execute(_ command: AIStructuredCommand, now: Date = Date()) -> Result<UUID, AICommandError> {
        switch AICommandValidator.validate(command, now: now) {
        case .failure(let error):
            return .failure(error)

        case .success(.createEvent(let draft)):
            let event = CalendarEvent(
                title: draft.title,
                startDate: draft.startDate,
                repeatRule: draft.repeatRule
            )
            // 唯一写入路径：EventService（内部处理 add/update、通知刷新、落盘、同步入队、Widget 快照）
            eventService.upsertEvent(event, flush: true)
            return .success(event.id)
        }
    }
}
