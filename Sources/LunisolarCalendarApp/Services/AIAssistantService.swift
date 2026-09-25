import Foundation

// MARK: - AI 助手应用服务（docs #35 / #41：AI 只能经 Domain 层写数据）
//
// 职责：把已解析的自然语言命令落到数据层。
// 约束（红线）：
// - 唯一写入路径是 EventService（→ EventStore），绝不由本类直接操作
//   EventStore / JSON 文件 / CloudKit / WidgetKit；
// - 执行前必定经过 AICommandValidator，任何调用者都无法绕过校验；
// - 破坏性操作（删除 / 修改）先按条件解析出**唯一**目标，0 条或多条都拒绝执行；
// - 查询（queryAgenda）是只读路径：直接读当日事件快照，不写入任何数据；
// - 通知调度、Widget 刷新、同步入队都由 EventService/EventStore 既有链路负责。

/// 执行结果（查询返回只读快照，不持有 store 引用）
public enum AIExecutionOutcome: Sendable {
    case createdEvent(UUID)
    case queried([CalendarEvent])
    case deletedEvent(UUID)
    case updatedEvent(UUID)
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
                // 复用草稿 id：同一份解析结果被重复确认（连点）时按 id 更新而不是再建一条
                id: draft.id,
                title: draft.title,
                // 类型决定要不要响（见 NotificationManager.shouldScheduleNotification）：
                // 用户说了「提醒我」就必须真的响，否则语义只落在标题处理上
                type: draft.type,
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

        case .success(.deleteEvent(let draft)):
            switch resolveTarget(draft.criteria) {
            case .failure(let error):
                return .failure(error)
            case .success(let target):
                eventService.removeEvent(target, flush: true)
                return .success(.deletedEvent(target.id))
            }

        case .success(.updateEvent(let draft)):
            switch resolveTarget(draft.criteria) {
            case .failure(let error):
                return .failure(error)
            case .success(let existing):
                var copy = existing
                // 时长沿用原事件；改时间后必须重挂提醒（与 EventEditView 的处理一致）
                let duration = existing.endDate.timeIntervalSince(existing.startDate)
                copy.startDate = draft.newStartDate
                copy.endDate = draft.newStartDate.addingTimeInterval(max(duration, 0))
                copy.isNotified = false
                copy.updatedAt = Date()
                eventService.upsertEvent(copy, flush: true)
                return .success(.updatedEvent(copy.id))
            }
        }
    }

    /// 用户在「删除 / 修改」里指的那**一次出现**的开始时刻。
    ///
    /// 重复日程在数据层只有一条记录，它的 `startDate` 是序列**锚点**（可能是几个月前）：
    /// - 非重复日程 → 就是它自己；
    /// - 重复日程 → 用「用户所说的那一天（criteria.day）」配上该日程原本的时分。
    ///
    /// 确认区用它展示"将要改动的那一次"，而不是把锚点日期摆给用户
    /// （锚点日期与用户说的「明天」毫无关系，会让人不敢确认）。
    nonisolated public static func occurrenceStart(
        of event: CalendarEvent,
        on day: Date,
        calendar: Calendar = QingheCalendarContext.userCalendar
    ) -> Date {
        guard event.repeatRule != .never else { return event.startDate }
        let hm = calendar.dateComponents([.hour, .minute], from: event.startDate)
        var dc = calendar.dateComponents([.year, .month, .day], from: day)
        dc.hour = hm.hour; dc.minute = hm.minute
        return calendar.date(from: dc) ?? day
    }

    /// 只读：按条件解析**唯一**目标事件（UI 预览 / 确认步骤用；不做任何写入）。
    /// 0 条 → .notFound；多条 → .ambiguous（让用户补充时间或标题，绝不"猜一条"执行）。
    public func resolveTarget(_ criteria: AIEventCriteria) -> Result<CalendarEvent, AICommandError> {
        let matched = matches(criteria)
        let targetDescription = criteria.keyword.isEmpty ? NSLocalizedString("该时间", comment: "") : "「\(criteria.keyword)」"
        switch matched.count {
        case 0:
            return .failure(AICommandError(
                kind: .notFound,
                message: String(format: NSLocalizedString("这一天没有匹配到%@相关的日程。", comment: ""), targetDescription)
            ))
        case 1:
            return .success(matched[0])
        default:
            return .failure(AICommandError(
                kind: .ambiguous,
                message: String(format: NSLocalizedString("找到 %d 条匹配%@的日程，补充具体时间或标题再试。", comment: ""),
                                matched.count, targetDescription)
            ))
        }
    }

    // MARK: - 内部

    /// 按"日 + 可选时刻 + 标题关键词"匹配当日事件（只读）
    private func matches(_ criteria: AIEventCriteria) -> [CalendarEvent] {
        let cal = QingheCalendarContext.userCalendar
        return eventService.store.events(on: criteria.day).filter { event in
            if !criteria.keyword.isEmpty,
               !event.title.localizedStandardContains(criteria.keyword) {
                return false
            }
            if let hint = criteria.timeHint,
               let hour = hint.hour, let minute = hint.minute {
                return cal.component(.hour, from: event.startDate) == hour
                    && cal.component(.minute, from: event.startDate) == minute
            }
            return true
        }
    }
}
