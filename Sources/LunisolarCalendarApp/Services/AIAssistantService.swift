import Foundation

// MARK: - AI 助手应用服务（docs #35 / #41：AI 只能经 Domain 层写数据）
//
// 职责：把已解析的自然语言命令落到数据层。
// 约束（红线）：
// - 唯一写入路径是 EventService（→ EventStore），绝不由本类直接操作
//   EventStore / JSON 文件 / CloudKit / WidgetKit；
// - 执行前必定经过 AICommandValidator，任何调用者都无法绕过校验；
// - 查询（queryAgenda）是只读路径：直接读当日事件快照，不写入任何数据；
// - 通知调度、Widget 刷新、同步入队都由 EventService/EventStore 既有链路负责。

/// 执行结果（查询返回只读快照，不持有 store 引用）
public enum AIExecutionOutcome: Sendable {
    case createdEvent(UUID)
    case queried([CalendarEvent])
}

@MainActor
public final class AIAssistantService {
    public static let shared = AIAssistantService()

    /// 事件写入通道。默认 App 单例；测试注入隔离实例（避免写入真实 Documents）。
    private let eventService: EventService

    public init(eventService: EventService = .shared) {
        self.eventService = eventService
    }

    /// 解析 + 校验 + 执行的一站式入口（UI 也可分两步调用 Parser/Validator 以做预览）。
    public func handle(_ input: String, now: Date = Date()) -> Result<AIExecutionOutcome, AICommandError> {
        switch AICommandParser.parse(input, baseDate: now) {
        case .failure(let error):
            return .failure(error)
        case .success(let command):
            return execute(command, now: now)
        }
    }

    /// 执行结构化命令（先校验，再经 EventService 写入 / 只读查询）。
    @discardableResult
    public func execute(_ command: AIStructuredCommand, now: Date = Date()) -> Result<AIExecutionOutcome, AICommandError> {
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
            return .success(.createdEvent(event.id))

        case .success(.queryAgenda(let range)):
            // 只读查询：取当日事件快照（含 EventStore 缓存），不写入任何数据
            let events = eventService.store.events(on: range.baseDate)
            return .success(.queried(events))
        }
    }
}
