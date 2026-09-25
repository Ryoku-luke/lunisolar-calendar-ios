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
    @Binding var focused: Bool
    /// 回车（Return）提交：与键盘工具栏的「解析」等价，省去"先收键盘再点按钮"
    let onSubmit: () -> Void

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.font = .preferredFont(forTextStyle: .body)
        tv.backgroundColor = .secondarySystemBackground
        tv.layer.cornerRadius = 12
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        tv.delegate = context.coordinator
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        // 组字中（拼音 / 听写的 marked text）绝不插手文本 —— 程序化改写会中断听写与联想。
        // 其余情况按"文本是否一致"同步：正常输入时两者恒等（delegate 已回写），
        // 只有程序化清空/恢复才会走到回写分支（若额外用 isFirstResponder 门挡掉，
        // 一键清空后字段会停留在旧文本）。
        if uiView.markedTextRange == nil, uiView.text != text {
            uiView.text = text
        }
        if focused && !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !focused && uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// 只做「文本 / 焦点」双向同步。
    ///
    /// 占位文案已移出本类，改由 SwiftUI 侧 overlay 渲染。历史实现把 placeholder
    /// 直接写进 UITextView 并在清空时重新填回，导致：
    /// - 编辑中清空后，占位串被当作输入内容（下一次按键会拼在占位串后面）；
    /// - 文本颜色在 .placeholderText / .label 之间来回切换，状态难以自洽。
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: AutoFocusTextView
        init(_ p: AutoFocusTextView) { parent = p }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.focused = true
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            // 回车 = 解析。多行文本里回车默认是换行；本页只收"一句话"，
            // 用回车提交可省掉「先收键盘 → 再点按钮」这一步（真机反馈交互拖沓的主因）
            if text == "\n" {
                parent.focused = false
                parent.onSubmit()
                return false
            }
            return true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.focused = false
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
    /// P1-6b：查询意图的结果（只读快照）与被查询日期
    @State private var queryResults: [CalendarEvent]?
    @State private var queryDate: Date?
    /// P1-6c：破坏性操作（删除 / 修改）的确认状态
    @State private var destructiveTarget: CalendarEvent?
    @State private var destructiveLabel: String?
    @State private var pendingCommand: AIStructuredCommand?
    /// 行内成功提示（创建 / 删除 / 修改完成）：2 秒后自动消失，替代模态 alert
    @State private var completedMessage: String?
    @State private var showError = false
    @State private var errorText = ""
    @State private var inputFocused: Bool = false

    var body: some View {
        NavigationStack {
            List {
                // 行内成功提示：替代「已创建 → 好」这类模态 alert（少两次点击，也不打断连续输入）
                if let completedMessage {
                    Section {
                        Label(completedMessage, systemImage: "checkmark.circle.fill")
                            .font(AppTheme.Font.subheadline.weight(.semibold))
                            .foregroundStyle(Color.appTint)
                    }
                }

                Section {
                    #if canImport(UIKit)
                    AutoFocusTextView(text: $input, focused: $inputFocused, onSubmit: { parse() })
                        .frame(minHeight: 100)
                        // 占位文案在 SwiftUI 侧渲染：不写进 UITextView，避免被当成用户输入
                        // （对齐 UITextView 的 textContainerInset 12 + 行内 padding 5）
                        .overlay(alignment: .topLeading) {
                            if input.isEmpty {
                                Text(NSLocalizedString("例如：明天下午3点提醒我开会", comment: "AI助手占位"))
                                    .font(AppTheme.Font.body)
                                    .foregroundStyle(Color.tertiaryLabel)
                                    .padding(.top, 12)
                                    .padding(.leading, 16)
                                    .allowsHitTesting(false)
                            }
                        }
                        // 一键清空：改词或取消重来（此前只能逐字删除）
                        .overlay(alignment: .topTrailing) {
                            if !input.isEmpty {
                                Button {
                                    input = ""
                                    inputFocused = true
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(Color.tertiaryLabel)
                                        .frame(width: 32, height: 32)
                                        .contentShape(Rectangle())
                                }
                                // List 行内的按钮需显式样式，否则点击会被整行吞掉
                                .buttonStyle(.borderless)
                                .accessibilityLabel(NSLocalizedString("清空输入", comment: "AI助手"))
                                .padding(.top, 4)
                                .padding(.trailing, 4)
                            }
                        }
                    #endif
                } header: {
                    Text(NSLocalizedString("用一句话描述", comment: "AI助手"))
                } footer: {
                    Text(NSLocalizedString("创建：「今天/明天/后天」或「M月D日」+「X点X分」+ 标题；查询：「今天/明天有什么安排」。本地解析，不上传数据。", comment: "AI助手说明"))
                }

                Section {
                    // 不做 disabled：空输入时点击会走 parse() 并给出明确提示；
                    // 否则按钮静默不可点，用户感受为「点了没反应」。
                    // 整行可点 + 加粗居中，减少"这个按钮在哪/要不要点"的犹豫
                    Button {
                        parse()
                    } label: {
                        Text(NSLocalizedString("解析并预览", comment: "AI助手"))
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }

                if let d = draft {
                    Section {
                        LabeledContent(NSLocalizedString("标题", comment: ""), value: d.title)
                        LabeledContent(NSLocalizedString("时间", comment: ""), value: d.startDate.formatted(date: .abbreviated, time: .shortened))
                        HStack {
                            Button(role: .cancel) {
                                // 取消只收起预览并保留原文（此前会清空输入，用户得重新打一遍）；
                                // 焦点还给输入框，方便直接改词后重新解析
                                draft = nil
                                inputFocused = true
                            } label: {
                                Label(NSLocalizedString("取消", comment: ""), systemImage: "xmark.circle")
                            }
                            // List 行内多按钮必须显式样式：默认样式下整行会抢走点击 →
                            // 两个按钮都点不动（真机反馈「点确认取消也不起作用」）
                            .buttonStyle(.borderless)
                            Spacer()
                            Button {
                                create(d)
                            } label: {
                                Label(NSLocalizedString("确认创建", comment: "AI助手"), systemImage: "checkmark.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .tint(Color.appTint)
                        }
                    } header: {
                        Text(NSLocalizedString("预览 · 确认后入库", comment: ""))
                    }
                }

                // P1-6b：查询意图的结果（只读快照，直接展示，无确认步骤）
                if let results = queryResults {
                    Section {
                        if results.isEmpty {
                            Text(NSLocalizedString("这一天没有安排。", comment: "AI助手"))
                                .foregroundStyle(Color.secondary)
                        } else {
                            ForEach(results) { ev in
                                HStack(spacing: AppTheme.Spacing.sm) {
                                    Text(ev.isAllDay
                                         ? NSLocalizedString("全天", comment: "")
                                         : ev.startDate.formatted(date: .omitted, time: .shortened))
                                        .font(AppTheme.Font.caption)
                                        .foregroundStyle(Color.secondaryLabel)
                                        .frame(width: 52, alignment: .leading)
                                    Text(ev.title)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    } header: {
                        Text(String(format: NSLocalizedString("查询结果 · %@", comment: "AI助手"),
                                    queryDate?.formatted(date: .abbreviated, time: .omitted) ?? ""))
                    }
                }

                // P1-6c：删除 / 修改的确认区（破坏性操作未确认不执行）
                if let target = destructiveTarget, let label = destructiveLabel {
                    Section {
                        LabeledContent(NSLocalizedString("日程", comment: ""), value: target.title)
                        LabeledContent(
                            NSLocalizedString("当前时间", comment: ""),
                            value: target.startDate.formatted(date: .abbreviated, time: .shortened)
                        )
                        HStack {
                            Button(role: .cancel) {
                                destructiveTarget = nil
                                destructiveLabel = nil
                                pendingCommand = nil
                            } label: {
                                Label(NSLocalizedString("取消", comment: ""), systemImage: "xmark.circle")
                            }
                            // 同上：List 行内多按钮需要显式样式，否则整行抢点击
                            .buttonStyle(.borderless)
                            Spacer()
                            Button {
                                confirmDestructive()
                            } label: {
                                Label(NSLocalizedString("确认", comment: ""), systemImage: "checkmark.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .tint(Color.appTint)
                        }
                    } header: {
                        Text(label)
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
                    // 键盘上的「解析」：省去"先收键盘再点列表里的按钮"这一往返
                    Button(NSLocalizedString("解析", comment: "AI助手")) { parse() }
                        .font(.body.weight(.semibold))
                }
            }
            #endif
            .alert(NSLocalizedString("无法解析", comment: "AI助手"), isPresented: $showError) {
                Button(NSLocalizedString("好", comment: ""), role: .cancel) {}
            } message: {
                Text(errorText)
            }
        }
    }

    // MARK: - 解析 / 校验 / 执行（docs #35：View 只做 UI）
    //
    // P1-6：解析逻辑此前在本视图内重复实现（约 115 行，与 AICommandParser 双份维护），
    // 现已收口为 Parser → Validator → AIAssistantService 三层；本视图只保留「预览 + 确认」。

    /// 解析 → 校验 → 预览（创建）/ 立即执行（查询）/ 确认（删除、修改）
    private func parse() {
        // 新一轮解析：清掉上一轮的预览 / 结果 / 待确认操作
        draft = nil
        queryResults = nil
        queryDate = nil
        destructiveTarget = nil
        destructiveLabel = nil
        pendingCommand = nil

        // 收起键盘：否则预览 / 结果区被键盘挡在屏幕下方，用户会以为「点了没反应」
        inputFocused = false

        switch AICommandParser.parse(input) {
        case .failure(let error):
            present(error)

        case .success(let command):
            switch command {
            case .queryAgenda(let range):
                // 只读查询：无需确认步骤，直接执行并展示结果
                switch AIAssistantService.shared.execute(command) {
                case .success(.queried(let events)):
                    queryResults = events
                    queryDate = range.baseDate
                case .success:
                    break // 查询路径不会出现其他结果类型
                case .failure(let error):
                    present(error)
                }

            case .createEvent:
                // 预览前先校验：让用户在「确认创建」之前就看到问题（如时间已过去）
                switch AICommandValidator.validate(command) {
                case .failure(let error):
                    present(error)
                case .success(.createEvent(let validated)):
                    draft = validated
                case .success:
                    break
                }

            case .deleteEvent, .updateEvent:
                // 破坏性操作：先校验，再解析出**唯一**目标，进入确认步骤（未确认不执行）
                switch AICommandValidator.validate(command) {
                case .failure(let error):
                    present(error)
                case .success(let validated):
                    guard let criteria = destructiveCriteria(of: validated) else { return }
                    switch AIAssistantService.shared.resolveTarget(criteria) {
                    case .failure(let error):
                        present(error)
                    case .success(let target):
                        destructiveTarget = target
                        pendingCommand = validated
                        destructiveLabel = destructiveLabel(for: validated)
                    }
                }
            }
        }
    }

    /// 删除 / 修改命令共用的定位条件
    private func destructiveCriteria(of command: AIStructuredCommand) -> AIEventCriteria? {
        switch command {
        case .deleteEvent(let draft): return draft.criteria
        case .updateEvent(let draft): return draft.criteria
        default: return nil
        }
    }

    /// 确认区标题（区分删除与修改，并显示将改到的时间）
    private func destructiveLabel(for command: AIStructuredCommand) -> String {
        switch command {
        case .deleteEvent:
            return NSLocalizedString("确认删除 · 不可撤销", comment: "AI助手")
        case .updateEvent(let draft):
            let when = draft.newStartDate.formatted(date: .abbreviated, time: .shortened)
            return String(format: NSLocalizedString("确认修改 · 改到 %@", comment: "AI助手"), when)
        default:
            return ""
        }
    }

    /// 确认执行删除 / 修改（唯一写入路径是 AIAssistantService → EventService）
    private func confirmDestructive() {
        guard let command = pendingCommand else { return }
        switch AIAssistantService.shared.execute(command) {
        case .success(.deletedEvent):
            showSuccess(NSLocalizedString("已删除该日程。", comment: "AI助手"))
            resetAfterCompletion()
        case .success(.updatedEvent):
            showSuccess(NSLocalizedString("已修改时间，提醒已重建。", comment: "AI助手"))
            resetAfterCompletion()
        case .success:
            break
        case .failure(let error):
            present(error)
        }
    }

    private func resetAfterCompletion() {
        input = ""
        draft = nil
        destructiveTarget = nil
        destructiveLabel = nil
        pendingCommand = nil
    }

    /// 确认创建：唯一写入路径是 AIAssistantService → EventService（AI 不直连数据层）
    private func create(_ d: AICreateEventDraft) {
        switch AIAssistantService.shared.execute(.createEvent(d)) {
        case .success:
            // 行内提示替代「已创建 → 好」模态；清空输入并把焦点还给输入框，便于连续录入
            showSuccess(NSLocalizedString("日程已加入日历。", comment: "AI助手"))
            input = ""
            draft = nil
            inputFocused = true
        case .failure(let error):
            present(error)
        }
    }

    /// 行内成功提示：2 秒后自动消失（不打断连续输入，也省掉模态的两次点击）
    private func showSuccess(_ text: String) {
        completedMessage = text
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if completedMessage == text { completedMessage = nil }
        }
    }

    /// 结构化错误统一展示（文案来自 AICommandError.message）
    private func present(_ error: AICommandError) {
        errorText = error.message
        showError = true
    }
}
#endif
