import Foundation
import LunarCore

// MARK: - AI 命令校验（docs #47 Validation）
//
// 纯函数：解析产物 → 校验/归一化 → 可执行命令。
// 与解析器分离，是为了让"能不能写进数据层"这件事有单一、可测试的判定点；
// AIAssistantService 执行前必定经过这里，任何调用路径都无法绕过。

public enum AICommandValidator {

    /// 标题长度上限（超出直接截断，避免超长标题污染列表与 Widget）
    public static let maxTitleLength = 100

    /// 校验并归一化命令。返回的命令与传入语义一致，仅做规范化（trim/截断）。
    public static func validate(
        _ command: AIStructuredCommand,
        now: Date = Date()
    ) -> Result<AIStructuredCommand, AICommandError> {
        switch command {
        case .createEvent(let draft):
            return validateCreate(draft, now: now).map { .createEvent($0) }
        case .queryAgenda(let range):
            return validateQuery(range).map { .queryAgenda($0) }
        case .deleteEvent(let draft):
            return validateCriteria(draft.criteria).map { .deleteEvent(AIDeleteEventDraft(criteria: $0)) }
        case .updateEvent(let draft):
            return validateUpdate(draft, now: now).map { .updateEvent($0) }
        }
    }

    /// 查询校验：被查询的日期须落在支持范围内（农历/黄历依赖 LunarCore 范围）。
    /// 注意：查询**允许**过去日期——回顾历史安排是合法用法（与创建意图不同）。
    static func validateQuery(_ range: AIQueryRange) -> Result<AIQueryRange, AICommandError> {
        let year = QingheCalendarContext.userCalendar.component(.year, from: range.baseDate)
        guard year >= ChineseCalendar.minYear, year <= ChineseCalendar.maxYear else {
            return .failure(AICommandError(
                kind: .outOfRange,
                message: "日期超出支持范围（\(ChineseCalendar.minYear)–\(ChineseCalendar.maxYear) 年）。"
            ))
        }
        return .success(range)
    }

    /// 定位条件校验（删除 / 修改共用）：必须有标题关键词或时间提示，
    /// 否则同一天可能匹配到多条，无法安全地执行破坏性操作。
    static func validateCriteria(_ criteria: AIEventCriteria) -> Result<AIEventCriteria, AICommandError> {
        let hasKeyword = !criteria.keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasKeyword || criteria.timeHint != nil else {
            return .failure(AICommandError(
                kind: .missingTarget,
                message: "没听清要操作哪条日程，补上标题或时间（如「删掉明天3点的例会」）。"
            ))
        }
        let year = QingheCalendarContext.userCalendar.component(.year, from: criteria.day)
        guard year >= ChineseCalendar.minYear, year <= ChineseCalendar.maxYear else {
            return .failure(AICommandError(
                kind: .outOfRange,
                message: "日期超出支持范围（\(ChineseCalendar.minYear)–\(ChineseCalendar.maxYear) 年）。"
            ))
        }
        return .success(criteria)
    }

    /// 修改校验：定位条件 + 新时间必须落在支持范围内且不在过去（改到过去多半是识别错了）。
    static func validateUpdate(
        _ draft: AIUpdateEventDraft,
        now: Date
    ) -> Result<AIUpdateEventDraft, AICommandError> {
        switch validateCriteria(draft.criteria) {
        case .failure(let error):
            return .failure(error)
        case .success(let criteria):
            let year = QingheCalendarContext.userCalendar.component(.year, from: draft.newStartDate)
            guard year >= ChineseCalendar.minYear, year <= ChineseCalendar.maxYear else {
                return .failure(AICommandError(
                    kind: .outOfRange,
                    message: "新时间超出支持范围（\(ChineseCalendar.minYear)–\(ChineseCalendar.maxYear) 年）。"
                ))
            }
            guard draft.newStartDate > now else {
                return .failure(AICommandError(
                    kind: .inThePast,
                    message: "新时间已经过去了，请确认要改到的时刻。"
                ))
            }
            return .success(AIUpdateEventDraft(criteria: criteria, newStartDate: draft.newStartDate))
        }
    }

    /// 创建日程校验规则：
    /// 1. 标题非空（解析阶段已挡一次，这里再兜一次，防止未来新增 intent 时漏判）；
    /// 2. 开始时间落在农历算法支持范围（1900–2100，超出后 LunarCore 无法给出正确农历/黄历）；
    /// 3. 一次性日程（.never）不得落在过去——用户多半说错了日期，预览阶段就应拦下。
    static func validateCreate(
        _ draft: AICreateEventDraft,
        now: Date
    ) -> Result<AICreateEventDraft, AICommandError> {
        var normalized = draft

        normalized.title = normalized.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.title.isEmpty else {
            return .failure(AICommandError(
                kind: .missingTitle,
                message: "没识别到日程标题，换个说法试试。"
            ))
        }
        if normalized.title.count > maxTitleLength {
            normalized.title = String(normalized.title.prefix(maxTitleLength))
        }

        let cal = QingheCalendarContext.userCalendar
        let year = cal.component(.year, from: normalized.startDate)
        guard year >= ChineseCalendar.minYear, year <= ChineseCalendar.maxYear else {
            return .failure(AICommandError(
                kind: .outOfRange,
                message: "日期超出支持范围（\(ChineseCalendar.minYear)–\(ChineseCalendar.maxYear) 年）。"
            ))
        }

        if normalized.repeatRule == .never, normalized.startDate < now {
            let stamp = normalized.startDate.formatted(
                Date.FormatStyle(date: .abbreviated, time: .shortened, locale: Locale(identifier: "zh_Hans_CN"))
            )
            return .failure(AICommandError(
                kind: .inThePast,
                message: "「\(stamp)」已经过去了，加上「明天」「后天」或具体日期再试。"
            ))
        }

        return .success(normalized)
    }
}
