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
        /// 修改/删除：指令里既没有标题关键词也没有时间提示，无法定位目标
        case missingTarget
        /// 修改/删除：该条件下没有匹配到任何日程
        case notFound
        /// 修改/删除：匹配到多条，需要用户补充时间或标题
        case ambiguous
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

/// 定位某条既有事件的检索条件（删除 / 修改共用）
public struct AIEventCriteria: Equatable, Sendable {
    /// 目标日（用户日历日界）
    public let day: Date
    /// 可选的时刻提示（hour/minute），用于区分同一天的多条日程
    public let timeHint: DateComponents?
    /// 标题关键词（已剔除日期 / 时间 / 动词；可为空 → 需靠 timeHint 区分）
    public let keyword: String

    public init(day: Date, timeHint: DateComponents?, keyword: String) {
        self.day = day
        self.timeHint = timeHint
        self.keyword = keyword
    }
}

/// 删除日程草稿（P1-6c）
public struct AIDeleteEventDraft: Equatable, Sendable {
    public let criteria: AIEventCriteria
    public init(criteria: AIEventCriteria) {
        self.criteria = criteria
    }
}

/// 修改日程草稿（P1-6c）。当前只支持改时间（含日期），标题改写留待后续。
public struct AIUpdateEventDraft: Equatable, Sendable {
    public let criteria: AIEventCriteria
    /// 新的开始时间；时长沿用原事件
    public let newStartDate: Date

    public init(criteria: AIEventCriteria, newStartDate: Date) {
        self.criteria = criteria
        self.newStartDate = newStartDate
    }
}

/// 结构化命令：校验通过后由 AIAssistantService 执行
public enum AIStructuredCommand: Equatable, Sendable {
    /// 创建日程（第一阶段已实现）
    case createEvent(AICreateEventDraft)
    /// 查询某一天的日程（只读，不写数据层）
    case queryAgenda(AIQueryRange)
    /// 删除日程（需先定位到唯一一条，确认后执行）
    case deleteEvent(AIDeleteEventDraft)
    /// 修改日程时间（需先定位到唯一一条，确认后执行）
    case updateEvent(AIUpdateEventDraft)

    public var kind: AIIntentKind {
        switch self {
        case .createEvent: return .createEvent
        case .queryAgenda: return .queryAgenda
        case .deleteEvent: return .deleteEvent
        case .updateEvent: return .updateEvent
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

        // 2.5 修改 / 删除意图（P1-6c）
        //     先按"日 + 可选时刻 + 标题关键词"定位目标；修改还需解析"改到"之后的新时间。
        let timeHint: DateComponents? = consumedTime.isEmpty
            ? nil
            : DateComponents(hour: hour, minute: minute)

        if let marker = firstMarker(in: s, among: ["删掉", "删除", "取消"]) {
            let keyword = cleanedKeyword(from: s, removing: [consumedDate, consumedTime, marker])
            return .success(.deleteEvent(AIDeleteEventDraft(
                criteria: AIEventCriteria(day: base, timeHint: timeHint, keyword: keyword)
            )))
        }

        if let range = firstMarkerRange(in: s, among: ["改到", "改为", "改成", "推迟到", "提前到", "挪到"]) {
            let head = String(s[s.startIndex..<range.lowerBound])
            let tail = String(s[range.upperBound...])
            // 新时刻：优先取"改到"之后的时刻；没有则沿用头部时刻
            let clock = parseClock(in: tail) ?? (hour, minute)
            let newDay = parseShortDayWord(in: tail, defaultDay: base)
            var comps = cal.dateComponents([.year, .month, .day], from: newDay)
            comps.hour = clock.0; comps.minute = clock.1
            guard let newStart = cal.date(from: comps) else {
                return .failure(AICommandError(kind: .badTime, message: "没识别到要改到的时间。"))
            }
            // 定位关键词取自"改到"之前的定位部分
            let keyword = cleanedKeyword(from: head, removing: [consumedDate, consumedTime])
            return .success(.updateEvent(AIUpdateEventDraft(
                criteria: AIEventCriteria(day: base, timeHint: timeHint, keyword: keyword),
                newStartDate: newStart
            )))
        }

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

    // MARK: - 修改 / 删除意图的解析辅助

    /// 返回第一个命中的标记词（删除意图）
    static func firstMarker(in s: String, among markers: [String]) -> String? {
        markers.first { s.contains($0) }
    }

    /// 返回最早命中的标记词范围（修改意图：需要切分"定位部分"与"新时间部分"）
    static func firstMarkerRange(in s: String, among markers: [String]) -> Range<String.Index>? {
        var best: Range<String.Index>?
        for m in markers {
            guard let r = s.range(of: m) else { continue }
            if best == nil || r.lowerBound < best!.lowerBound {
                best = r
            }
        }
        return best
    }

    /// 从文本解析时刻（与主解析器同一套规则：14:30 / 下午3点 / 晚上7点）
    static func parseClock(in s: String) -> (hour: Int, minute: Int)? {
        var hour = 0, minute = 0
        var isPM = false
        if let r = s.range(of: #"(\d{1,2}):(\d{2})"#, options: .regularExpression) {
            let nums = String(s[r]).components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
            guard nums.count == 2 else { return nil }
            hour = nums[0]; minute = nums[1]
        } else if let r = s.range(of: #"([上下]午|晚上)?\s*(\d{1,2})\s*[点时](\d{1,2})?分?"#, options: .regularExpression) {
            let seg = String(s[r])
            let nums = seg.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
            guard !nums.isEmpty else { return nil }
            hour = nums[0]
            if nums.count > 1 { minute = nums[1] }
            if seg.hasPrefix("下午") || seg.hasPrefix("晚上") { isPM = true }
        } else {
            return nil
        }
        if isPM && hour < 12 { hour += 12 }
        return (hour, minute)
    }

    /// "改到"之后只识别 今天/明天/后天 三种日期词；其余情况沿用定位日（避免过度推断）
    static func parseShortDayWord(in s: String, defaultDay: Date) -> Date {
        let cal = Calendar(identifier: .gregorian)
        if s.contains("后天") { return cal.date(byAdding: .day, value: 2, to: defaultDay) ?? defaultDay }
        if s.contains("明天") { return cal.date(byAdding: .day, value: 1, to: defaultDay) ?? defaultDay }
        return defaultDay
    }

    /// 关键词清洗：剔除日期 / 时间 / 动词残留，并去掉首尾的口语字（把、的、了、帮我…）
    static func cleanedKeyword(from s: String, removing tokens: [String]) -> String {
        var result = s
        for token in tokens where !token.isEmpty {
            result = result.replacingOccurrences(of: token, with: "")
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: " ，,。.!！的了把帮我"))
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

        // 中文数字 → 阿拉伯数字（只处理紧邻时间/日期单位的数字词：
        // 「两点」→「2点」、「九月二十五号」→「9月25号」；
        // 标题里的普通数字词如「两斤苹果」不受影响）
        s = normalizeChineseNumerals(s)
        // 补齐「半 / 一刻 / 三刻」的分钟（时间正则只认阿拉伯数字，故要求"点"前已有数字）
        s = s.replacingOccurrences(of: #"(?<=\d)点半"#, with: "点30分", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?<=\d)点一刻"#, with: "点15分", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?<=\d)点三刻"#, with: "点45分", options: .regularExpression)
        return s
    }

    /// 中文数字 → 阿拉伯数字：仅替换紧邻「月 / 日 / 号 / 点 / 时」的数字词
    /// （「九月二十五号」→「9月25号」、「两点」→「2点」）
    static func normalizeChineseNumerals(_ s: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "([零〇一二两三四五六七八九十]{1,3})(?=\\s*[月日号点时])") else {
            return s
        }
        let ns = s as NSString
        var result = s
        // 从后往前替换：后面的替换不会影响前面已算出的 range
        for match in regex.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed() {
            guard let range = Range(match.range, in: s),
                  let value = chineseNumberToInt(String(s[range])) else { continue }
            result.replaceSubrange(range, with: String(value))
        }
        return result
    }

    /// 中文数字 → 整数（支持 零-九 / 十 / 十一 / 十二 / 二十 / 二十四 等时刻写法）
    static func chineseNumberToInt(_ text: String) -> Int? {
        let digits: [Character: Int] = [
            "零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4,
            "五": 5, "六": 6, "七": 7, "八": 8, "九": 9
        ]
        if text == "十" { return 10 }
        if let tenIndex = text.firstIndex(of: "十") {
            let tensPart = text[text.startIndex..<tenIndex]
            let onesPart = text[text.index(after: tenIndex)...]
            let tens = tensPart.isEmpty ? 1 : (digits[tensPart.first!] ?? 1)
            let ones = onesPart.isEmpty ? 0 : (digits[onesPart.first!] ?? 0)
            return tens * 10 + ones
        }
        if text.count == 1, let char = text.first, let value = digits[char] { return value }
        return nil
    }
}
