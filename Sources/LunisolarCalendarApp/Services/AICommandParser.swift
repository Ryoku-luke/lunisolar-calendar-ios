import Foundation
import LunarCore

// MARK: - AI 命令解析器（P2-1）
//
// 把自然语言解析成 ParsedIntent（标题 + 开始时间 + 重复规则）。
// AIAssistantView 只负责 UI，解析逻辑全部走本类，可单测。

public struct AIParsedIntent: Sendable {
    public let title: String
    public let startDate: Date
    public let repeatRule: RepeatRule
    public init(title: String, startDate: Date, repeatRule: RepeatRule) {
        self.title = title
        self.startDate = startDate
        self.repeatRule = repeatRule
    }
}

public enum AICommandParser {

    /// 解析用户输入，失败返回 nil 并填 errorMessage。
    public static func parse(_ input: String, baseDate: Date = Date()) -> (intent: AIParsedIntent?, error: String?) {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return (nil, "输入为空") }

        let cal = Calendar(identifier: .gregorian)
        var base = cal.startOfDay(for: baseDate)
        var consumedDate = ""

        // 1. 日期：今天/明天/后天/具体日期/周几
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
                    base = date < cal.startOfDay(for: Date()) ? cal.date(byAdding: .month, value: 1, to: date) ?? date : date
                    consumedDate = seg
                }
            }
        } else if let r = s.range(of: #"(周|星期)([一二三四五六日天])"#, options: .regularExpression) {
            let seg = String(s[r])
            let map: [Character: Int] = ["一":2,"二":3,"三":4,"四":5,"五":6,"六":7,"日":1,"天":1]
            if let ch = seg.last, let target = map[ch] {
                for delta in 1...7 {
                    if let d = cal.date(byAdding: .day, value: delta, to: base),
                       cal.component(.weekday, from: d) == target {
                        base = d; consumedDate = seg; break
                    }
                }
            }
        }

        // 2. 时间
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

        // 3. 标题
        var title = s
        for w in [consumedDate, consumedTime, "提醒我", "提醒", "帮我", "我要", "记得"] where !w.isEmpty {
            title = title.replacingOccurrences(of: w, with: "")
        }
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: " ，,。.!！"))

        if title.isEmpty { return (nil, "没识别到日程标题") }

        var c = cal.dateComponents([.year, .month, .day], from: base)
        c.hour = hour; c.minute = minute
        guard let start = cal.date(from: c) else { return (nil, "时间格式无法识别") }

        // 4. 重复规则
        var ruleProbe = s
        if !consumedDate.isEmpty {
            ruleProbe = ruleProbe.replacingOccurrences(of: consumedDate, with: "")
        }
        var rule: RepeatRule = .never
        if ruleProbe.contains("每天") || ruleProbe.contains("每日") { rule = .daily }
        else if ruleProbe.contains("工作日") { rule = .workday }
        else if ruleProbe.contains("每周") || ruleProbe.contains("星期") || ruleProbe.contains("周几") { rule = .weekly }
        else if ruleProbe.contains("每月") { rule = .monthly }

        return (AIParsedIntent(title: title, startDate: start, repeatRule: rule), nil)
    }
}
