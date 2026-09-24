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

    @State private var input: String = ""
    @State private var draft: AICreateEventDraft?
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

    // MARK: - 解析 / 校验 / 执行（docs #35：View 只做 UI）
    //
    // P1-6：解析逻辑此前在本视图内重复实现（约 115 行，与 AICommandParser 双份维护），
    // 现已收口为 Parser → Validator → AIAssistantService 三层；本视图只保留「预览 + 确认」。

    /// 解析 → 校验 → 进入预览（确认后才写入）
    private func parse() {
        switch AICommandParser.parse(input) {
        case .failure(let error):
            present(error)

        case .success(let command):
            // 预览前先校验：让用户在「确认创建」之前就看到问题（如时间已过去）
            switch AICommandValidator.validate(command) {
            case .failure(let error):
                present(error)
            case .success(.createEvent(let validated)):
                draft = validated
            }
        }
    }

    /// 确认创建：唯一写入路径是 AIAssistantService → EventService（AI 不直连数据层）
    private func create(_ d: AICreateEventDraft) {
        switch AIAssistantService.shared.execute(.createEvent(d)) {
        case .success:
            created = true
            // P1：创建成功后清空输入与预览，可继续说下一条
            input = ""
            draft = nil
        case .failure(let error):
            present(error)
        }
    }

    /// 结构化错误统一展示（文案来自 AICommandError.message）
    private func present(_ error: AICommandError) {
        errorText = error.message
        showError = true
    }
}
#endif
