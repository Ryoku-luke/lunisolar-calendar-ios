import Foundation
import LunarCore

// MARK: - AI 助手：自然语言 → 结构化命令（docs #35 / #36）
//
// 强制分层（禁止 AI 直接触碰数据层）：
//   AIAssistantView → AICommandParser → AICommandValidator → AIAssistantService → EventService → EventStore
// 本文件只做"意图解析"：纯函数、无 IO、可单测；不做写入，也不引用 EventStore。

/// AI 意图类型（docs #36 第一阶段：创建 / 查询 / 修改 / 删除日程）
public enum AIIntentKind: String, Sendable, Equatable, CaseIterable {
    /// 创建日程（当前已实现）
    case createEvent
    /// 查询日程（P1-6b 预留）
    case queryAgenda
    /// 修改日程（P1-6b 预留）
    case updateEvent
    /// 删除日程（P1-6b 预留）
    case deleteEvent
}

/// 结构化错误：kind 供测试断言，message 可直接展示给用户（docs #47 Error Handling）
public struct AICommandError: Error, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case emptyInput
        case missingTitle
        case badTime
        case outOfRange
        case inThePast
        case storeFailure
    }

    public let kind: Kind
    public let message: String

    public init(kind: Kind, message: String) {
        self.kind = kind
        self.message = message
    }
}

/// 创建日程草稿：解析产物，尚未通过校验
public struct AICreateEventDraft: Equatable, Sendable {
    public var title: String
    public var startDate: Date
    public var repeatRule: RepeatRule

    public init(title: String, startDate: Date, repeatRule: RepeatRule) {
        self.title = title
        self.startDate = startDate
        self.repeatRule = repeatRule
    }
}

/// 查询某一天的日程（P1-6b）
public struct AIQueryRange: Equatable, Sendable {
    /// 被查询的日期（以"天"为粒度）
    public let baseDate: Date
    public init(baseDate: Date) {
        self.baseDate = baseDate
    }
}

/// 结构化命令：校验通过后由 AIAssistantService 执行
public enum AIStructuredCommand: Equatable, Sendable {
    /// 创建日程（第一阶段已实现）
    case createEvent(AICreateEventDraft)
    /// 查询某一天的日程（只读，不写数据层）
    case queryAgenda(AIQueryRange)

    public var kind: AIIntentKind {
        switch self {
        case .createEvent: return .createEvent
        case .queryAgenda: return .queryAgenda
        }
    }
}

// MARK: - 解析器

public enum AICommandParser {

    /// 自然语言 → 结构化命令。
    /// - Parameter baseDate: "今天/明天"等相对日期的基准（默认 now；测试可注入固定值）
    public static func parse(_ input: String, baseDate: Date = Date()) -> Result<AIStructuredCommand, AICommandError> {
        let s = normalize(input).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else {
            return .failure(AICommandError(
                kind: .emptyInput,
                message: "请先输入一句话，例如「明天下午3点提醒我开会」。"
            ))
        }

        let cal = Calendar(identifier: .gregorian)
        var base = cal.startOfDay(for: baseDate)
        var consumedDate = ""

        // 1. 日期：今天 / 明天 / 后天 / M月D日 / X号 / 周X
        if s.contains("后天") {
            base = cal.date(byAdding: .day, value: 2, to: base) ?? base
            consumedDate = "后天"
        } else if s.contains("明天") {
            base = cal.date(byAdding: .day, value: 1, to: base) ?? base
            consumedDate = "明天"
        } else if s.contains("今天") {
            consumedDate = "今天"
        } else if let r = s.range(of: #"(\d{1,2})月(\d{1,2})[日号]"#, options: .regularExpression) {
            let seg = String(s[r])
            let nums = seg.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
            if nums.count == 2 {
                var c = cal.dateComponents([.year, .month, .day], from: base)
                c.month = nums[0]; c.day = nums[1]
                if let d = cal.date(from: c) { base = d; consumedDate = seg }
            }
        } else if let r = s.range(of: #"(\d{1,2})[号日](?!\d)"#, options: .regularExpression) {
            let seg = String(s[r])
            let nums = seg.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
            if let d = nums.first, d >= 1 && d <= 31 {
                var c = cal.dateComponents([.year, .month, .day], from: base)
                c.day = d
                if let date = cal.date(from: c) {
                    // 该日已过 → 顺延到下月
                    base = date < cal.startOfDay(for: baseDate)
                        ? cal.date(byAdding: .month, value: 1, to: date) ?? date
                        : date
                    consumedDate = seg
                }
            }
        } else if let r = s.range(of: #"(周|星期)([一二三四五六日天])"#, options: .regularExpression) {
            // "每周一"：把前导"每"一起纳入 consumedDate，既让标题剔除干净，也是 weekly 的判定依据
            var seg = String(s[r])
            if r.lowerBound > s.startIndex, s[s.index(before: r.lowerBound)] == "每" {
                seg = "每" + seg
            }
            let weekdaySegment = String(s[r])
            let map: [Character: Int] = ["一": 2, "二": 3, "三": 4, "四": 5, "五": 6, "六": 7, "日": 1, "天": 1]
            if let ch = weekdaySegment.last, let target = map[ch] {
                for delta in 1...7 {
                    if let d = cal.date(byAdding: .day, value: delta, to: base),
                       cal.component(.weekday, from: d) == target {
                        base = d; consumedDate = seg; break
                    }
                }
            }
        }

        // 1.5 查询意图（P1-6b）："明天有什么安排 / 查一下后天日程"。
        // 命中查询短语即返回只读查询命令（不做标题提取、不走写入路径）。
        // 白名单取保守短语，避免"给我安排一下明天的会"这类创建句被误判为查询。
        if ["有什么安排", "有哪些安排", "什么安排", "有什么日程", "有哪些日程", "什么日程",
            "查一下", "查日程", "看下安排", "看看安排", "看下日程", "看看日程"].contains(where: { s.contains($0) }) {
            return .success(.queryAgenda(AIQueryRange(baseDate: base)))
        }

        // 2. 时间：14:30 / 下午3点 / 晚上7点半
        var hour = 9, minute = 0
        var consumedTime = ""
        var isPM = false
        if let r = s.range(of: #"(\d{1,2}):(\d{2})"#, options: .regularExpression) {
            let seg = String(s[r])
            let nums = seg.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
            if nums.count == 2 { hour = nums[0]; minute = nums[1]; consumedTime = seg }
        } else if let r = s.range(of: #"([上下]午|晚上)?\s*(\d{1,2})\s*[点时](\d{1,2})?分?"#, options: .regularExpression) {
            let seg = String(s[r])
            let nums = seg.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
            if !nums.isEmpty {
                hour = nums[0]
                if nums.count > 1 { minute = nums[1] }
                if seg.hasPrefix("下午") || seg.hasPrefix("晚上") { isPM = true }
                consumedTime = seg
            }
        }
        if isPM && hour < 12 { hour += 12 }

        // 3. 标题：剔除已识别的日期/时间词、重复词与口语前缀
        var title = s
        for w in [consumedDate, consumedTime, "提醒我", "提醒", "帮我", "我要", "记得",
                  "安排一下", "每天", "每日", "每周", "每月", "工作日"] where !w.isEmpty {
            title = title.replacingOccurrences(of: w, with: "")
        }
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: " ，,。.!！"))

        guard !title.isEmpty else {
            return .failure(AICommandError(
                kind: .missingTitle,
                message: "没识别到日程标题，换个说法试试。"
            ))
        }

        var c = cal.dateComponents([.year, .month, .day], from: base)
        c.hour = hour; c.minute = minute
        guard let start = cal.date(from: c) else {
            return .failure(AICommandError(kind: .badTime, message: "时间格式无法识别。"))
        }

        // 4. 重复规则：直接在原始输入上判定
        //    （曾把 consumedDate 从探针里剔除，导致"每周一"里的"每周"被一并删掉 → 误判为 .never；
        //      monthly 的判定锚点是"每月"而不是"号"，所以不需要剔除已识别的日期词）
        var rule: RepeatRule = .never
        if s.contains("每天") || s.contains("每日") { rule = .daily }
        else if s.contains("工作日") { rule = .workday }
        else if s.contains("每周") || s.contains("星期") || s.contains("周几") { rule = .weekly }
        else if s.contains("每月") { rule = .monthly }

        return .success(.createEvent(AICreateEventDraft(title: title, startDate: start, repeatRule: rule)))
    }

    /// 英/日文关键词与 AM/PM 归一化为中文日期/时段词（纯函数，便于单测）
    public static func normalize(_ input: String) -> String {
        var s = input
        let lower = input.lowercased()

        if lower.contains("day after tomorrow") || lower.contains("明後日") {
            s = s.replacingOccurrences(of: "day after tomorrow", with: "后天", options: .caseInsensitive)
                 .replacingOccurrences(of: "明後日", with: "后天")
        } else if lower.contains("tomorrow") || lower.contains("明日") {
            s = s.replacingOccurrences(of: "tomorrow", with: "明天", options: .caseInsensitive)
                 .replacingOccurrences(of: "明日", with: "明天")
        } else if lower.contains("today") || lower.contains("今日") {
            s = s.replacingOccurrences(of: "today", with: "今天", options: .caseInsensitive)
                 .replacingOccurrences(of: "今日", with: "今天")
        }

        s = s.replacingOccurrences(of: " AM", with: " 上午", options: .caseInsensitive)
             .replacingOccurrences(of: " PM", with: " 下午", options: .caseInsensitive)
             .replacingOccurrences(of: "am", with: "上午")
             .replacingOccurrences(of: "pm", with: "下午")
        return s
    }
}
