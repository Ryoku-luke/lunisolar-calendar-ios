#if canImport(SwiftUI)
import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - UITextView 桥接（绕开 iOS 27 模拟器 FocusState 不弹键盘的 bug）
#if canImport(UIKit)
struct AutoFocusTextView: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    @Binding var focused: Bool

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.font = .preferredFont(forTextStyle: .body)
        tv.backgroundColor = .secondarySystemBackground
        tv.layer.cornerRadius = 12
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        tv.delegate = context.coordinator
        tv.text = placeholder
        tv.textColor = .placeholderText
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if text.isEmpty && uiView.textColor == .placeholderText && focused == false {
            // 保持 placeholder
        } else if uiView.text != text {
            uiView.text = text
            uiView.textColor = .label
        }
        if focused && !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !focused && uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: AutoFocusTextView
        init(_ p: AutoFocusTextView) { parent = p }
        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.focused = true
            if textView.textColor == .placeholderText {
                textView.text = ""
                textView.textColor = .label
            }
        }
        func textViewDidChange(_ textView: UITextView) {
            // 用户清空文字时立即切回 placeholder 样式（不必等 endEditing）
            if textView.text.isEmpty {
                textView.text = parent.placeholder
                textView.textColor = .placeholderText
                parent.text = ""
            } else {
                parent.text = textView.text
            }
        }
        func textViewDidEndEditing(_ textView: UITextView) {
            parent.focused = false
            if textView.text.isEmpty {
                textView.text = parent.placeholder
                textView.textColor = .placeholderText
            }
        }
    }
}
#endif

// MARK: - AI 日历助手 MVP（文档 §35-36 第一阶段：自然语言创建日程）
//
// 范围：本地 Intent Parser，不调云端 AI。
// 支持：
//   "明天下午3点提醒我开会"
//   "后天 14:30 见客户"
//   "9月25日 10:00 体检"
//   "今天晚上7点 吃饭"
// 解析失败时给出提示，不静默创建。
@MainActor
struct AIAssistantView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented
    @Environment(EventStore.self) private var store

    @State private var input: String = ""
    @State private var draft: ParsedIntent?
    @State private var showError = false
    @State private var errorText = ""
    @State private var created = false
    @State private var inputFocused: Bool = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    #if canImport(UIKit)
                    AutoFocusTextView(text: $input,
                                      placeholder: NSLocalizedString("例如：明天下午3点提醒我开会", comment: "AI助手占位"),
                                      focused: $inputFocused)
                        .frame(minHeight: 100)
                    #endif
                } header: {
                    Text(NSLocalizedString("用一句话描述", comment: "AI助手"))
                } footer: {
                    Text(NSLocalizedString("支持「今天/明天/后天」或「M月D日」+「X点X分」+ 标题。本地解析，不上传数据。", comment: "AI助手说明"))
                }

                Section {
                    Button(NSLocalizedString("解析并预览", comment: "AI助手")) { parse() }
                        .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if let d = draft {
                    Section {
                        LabeledContent(NSLocalizedString("标题", comment: ""), value: d.title)
                        LabeledContent(NSLocalizedString("时间", comment: ""), value: d.startDate.formatted(date: .abbreviated, time: .shortened))
                        HStack {
                            Button(role: .cancel) {
                                // P1：取消 → 清掉预览，回到输入
                                draft = nil
                                input = ""
                            } label: {
                                Label(NSLocalizedString("取消", comment: ""), systemImage: "xmark.circle")
                            }
                            Spacer()
                            Button {
                                create(d)
                            } label: {
                                Label(NSLocalizedString("确认创建", comment: "AI助手"), systemImage: "checkmark.circle.fill")
                            }
                            .tint(Color.appTint)
                        }
                    } header: {
                        Text(NSLocalizedString("预览 · 确认后入库", comment: ""))
                    }
                }
            }
            .navigationTitle(NSLocalizedString("AI 日历助手", comment: ""))
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    inputFocused = true
                }
            }
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if isPresented {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(NSLocalizedString("关闭", comment: "")) { dismiss() }
                    }
                }
            }
            #if canImport(UIKit)
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(
                TapGesture().onEnded { _ in
                    inputFocused = false
                }
            )
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(NSLocalizedString("完成", comment: "")) { inputFocused = false }
                }
            }
            #endif
            .alert(NSLocalizedString("无法解析", comment: "AI助手"), isPresented: $showError) {
                Button(NSLocalizedString("好", comment: ""), role: .cancel) {}
            } message: {
                Text(errorText)
            }
            .alert(NSLocalizedString("已创建", comment: "AI助手"), isPresented: $created) {
                Button(NSLocalizedString("好", comment: "")) { dismiss() }
            } message: {
                Text(NSLocalizedString("日程已加入日历。", comment: "AI助手"))
            }
        }
    }

    // MARK: - 解析

    private struct ParsedIntent {
        var title: String
        var startDate: Date
        var repeatRule: RepeatRule = .never
    }

    private func parse() {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let cal = Calendar.gregorian
        let now = Date()

        // 英文/日文关键词归一化为中文
        let lower = s.lowercased()
        if lower.contains("day after tomorrow") || lower.contains("明後日") { s = s.replacingOccurrences(of: "day after tomorrow", with: "后天", options: .caseInsensitive).replacingOccurrences(of: "明後日", with: "后天") }
        else if lower.contains("tomorrow") || lower.contains("明日") { s = s.replacingOccurrences(of: "tomorrow", with: "明天", options: .caseInsensitive).replacingOccurrences(of: "明日", with: "明天") }
        else if lower.contains("today") || lower.contains("今日") { s = s.replacingOccurrences(of: "today", with: "今天", options: .caseInsensitive).replacingOccurrences(of: "今日", with: "今天") }
        s = s.replacingOccurrences(of: " AM", with: " 上午", options: .caseInsensitive)
             .replacingOccurrences(of: " PM", with: " 下午", options: .caseInsensitive)
             .replacingOccurrences(of: "am", with: "上午")
             .replacingOccurrences(of: "pm", with: "下午")

        // 1. 日期基准
        var base = cal.startOfDay(for: now)
        var consumedDate = ""
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
            // 单独"15号"→ 每月，设到本月/下月该日
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
                // 找下一个该 weekday（今天不算）
                for delta in 1...7 {
                    if let d = cal.date(byAdding: .day, value: delta, to: base),
                       cal.component(.weekday, from: d) == target {
                        base = d; consumedDate = seg; break
                    }
                }
            }
        }

        // 2. 时间：下午3点 / 14:30 / 晚上7点
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

        // 3. 标题：去掉日期时间词后的剩余
        var title = s
        for w in [consumedDate, consumedTime, "提醒我", "提醒", "帮我", "我要", "记得"] where !w.isEmpty {
            title = title.replacingOccurrences(of: w, with: "")
        }
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: " ，,。.!！") )

        if title.isEmpty {
            errorText = NSLocalizedString("没识别到日程标题，换个说法试试。", comment: "AI助手")
            showError = true
            return
        }

        var c = cal.dateComponents([.year, .month, .day], from: base)
        c.hour = hour; c.minute = minute
        guard let start = cal.date(from: c) else {
            errorText = NSLocalizedString("时间格式无法识别。", comment: "AI助手")
            showError = true
            return
        }
        // 4. 重复规则：每周/每天/每月
        // 注意：consumedDate 已经从用户输入里识别了具体日期（如"15号"），
        // 这里再 s.contains("号") 会误触发 monthly——把 consumedDate 从 s 里剔除后再判断。
        var ruleProbe = s
        if !consumedDate.isEmpty {
            ruleProbe = ruleProbe.replacingOccurrences(of: consumedDate, with: "")
        }
        var rule: RepeatRule = .never
        if ruleProbe.contains("每天") || ruleProbe.contains("每日") { rule = .daily }
        else if ruleProbe.contains("工作日") { rule = .workday }
        else if ruleProbe.contains("每周") || ruleProbe.contains("星期") || ruleProbe.contains("周几") { rule = .weekly }
        else if ruleProbe.contains("每月") { rule = .monthly }

        draft = ParsedIntent(title: title, startDate: start, repeatRule: rule)
    }

    private func create(_ d: ParsedIntent) {
        let ev = CalendarEvent(title: d.title, startDate: d.startDate, repeatRule: d.repeatRule)
        EventService.shared.upsertEvent(ev, flush: true)
        created = true
        // P1：创建成功后清空输入与预览，可继续说下一条
        input = ""
        draft = nil
    }
}
#endif
