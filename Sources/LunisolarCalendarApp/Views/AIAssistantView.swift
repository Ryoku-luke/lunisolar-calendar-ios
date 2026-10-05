#if canImport(SwiftUI)
import SwiftUI
import Foundation

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
    /// 刚创建的事件落在**非今天**时的那个日期（用于补「去看看」按钮）。
    /// nil = 当天，或本次操作不是创建。与 `completedMessage` 同生命周期。
    @State private var completedOffDay: Date?
    /// 行内失败提示（UI_DESIGN_REVIEW P0-3）：原先是「无法解析 → 好」的模态 alert。
    /// 解析失败往往只需改几个字重试，模态要点两次才回到输入框，故与成功提示同区呈现。
    @State private var inlineError: String?
    @State private var inputFocused: Bool = false

    /// 把三个提示相关的 @State 映射成一个状态（P4-2 ②：让提示条只依赖一个入参）
    private var inlineNoticeState: AIInlineNoticeState {
        if let inlineError { return .error(inlineError) }
        if let completedMessage { return .success(completedMessage, offDay: completedOffDay) }
        return .none
    }
    var body: some View {
        NavigationStack {
            List {
                // 行内提示区：成功与失败同一位置，替代模态 alert（少两次点击，也不打断连续输入）
                AIInlineNotice(state: inlineNoticeState)

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
                                        .font(.system(size: 20)) // N-9-exempt: SF Symbol 图标固定方框（豁免①）
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
                        AIParseButton(onParse: { parse() })
                    .accessibilityIdentifier(AccessibilityID.aiParse)
                }

                if let d = draft {
                    Section {
                        AIPreviewRows(draft: d,
                                       onCancel: { draft = nil; inputFocused = true },
                                       onCreate: { create($0) })
                    } header: {
                        Text(NSLocalizedString("预览 · 确认后入库", comment: ""))
                    }
                }

                // P1-6b：查询意图的结果（只读快照，直接展示，无确认步骤）
                if let results = queryResults {
                    Section {
                        AIQueryResultRows(results: results)
                    } header: {
                        Text(String(format: NSLocalizedString("查询结果 · %@", comment: "AI助手"),
                                    queryDate?.formatted(date: .abbreviated, time: .omitted) ?? ""))
                    }
                }

                // P1-6c：删除 / 修改的确认区（破坏性操作未确认不执行）
                if let target = destructiveTarget, let label = destructiveLabel {
                    Section {
                        AIDestructiveConfirmRows(
                            title: target.title,
                            occurrence: occurrenceText(for: target),
                            repeatLabel: target.repeatRule == .never ? nil : target.repeatRuleLabel,
                            onConfirm: { confirmDestructive() },
                            onCancel: {
                                destructiveTarget = nil
                                destructiveLabel = nil
                                pendingCommand = nil
                            })
                    } header: {
                        Text(label)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("AI 日历助手", comment: ""))
            // N-6：外接键盘 ⌘+Return = 解析提交（与键盘「解析」等价）。
            // 普通 Return 已由 AutoFocusTextView 的 shouldChangeTextIn 提交，
            // ⌘+Return 在此兜底（焦点不在输入框时也可用）。
            .onKeyPress { press in
                if press.modifiers.contains(.command), press.key == .return {
                    parse()
                    return .handled
                }
                return .ignored
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    inputFocused = true
                }
            }
            #if canImport(UIKit)
            .inlineTitleBar()
            #endif
            .toolbar {
                if isPresented {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(NSLocalizedString("关闭", comment: "")) { dismiss() }
                    }
                }
                // 键盘弹起时，导航栏给一个**一眼可见**的收起入口。
                // 键盘工具栏上的「完成」在真机上不够显眼（用户反馈「键盘无法关闭」），
                // 导航栏按钮在键盘弹出时始终可见，是确定的兜底。
                if inputFocused {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(NSLocalizedString("完成", comment: "AI助手")) { inputFocused = false }
                            .font(.body.weight(.semibold))
                            .accessibilityIdentifier(AccessibilityID.aiDone)
                    }
                }
            }
            #if canImport(UIKit)
            .scrollDismissesKeyboard(.interactively)
            // ⚠️ 这里刻意**没有**「整页点空白处收键盘」的手势。试过三种写法，都不行：
            //   1. simultaneousGesture(TapGesture())：与子视图手势并行，点输入框**本身**也会把
            //      inputFocused 置 false → updateUIView 立刻 resignFirstResponder()，把刚点起来的
            //      键盘收掉。它与「UITextView 取得第一响应者」的先后是竞态，症状时好时坏
            //      （实测报 Neither element nor any descendant has keyboard focus）。
            //   2. onTapGesture：不抢子视图手势，但会**吞掉 List 行内按钮的点击** →
            //      「解析并预览」点了既不出现预览也不弹错误（实测）。
            //   3. SpatialTapGesture + 排除输入框区域：靠 PreferenceKey 回报输入框 frame，
            //      但该 frame 始终是 .zero（background 里的 preference 不向上传播），
            //      于是任何点击都被判成「框外」→ 焦点还是被收掉（实测两条 AI 用例同时失败）。
            // 结论：键盘收起只走**明确入口**——导航栏「完成」+ 键盘工具栏「完成」+ 滚动收起 + 回车提交。
            // 这四个都不与输入框/按钮的手势竞争，是可靠的做法。
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    // 键盘上再给一个收起入口（复用既有本地化键「完成」，四语言均已翻译）
                    Button(NSLocalizedString("完成", comment: "AI助手")) { inputFocused = false }
                    Spacer()
                    // 键盘上的「解析」：省去"先收键盘再点列表里的按钮"这一往返
                    Button(NSLocalizedString("解析", comment: "AI助手")) { parse() }
                        .font(.body.weight(.semibold))
                }
            }
            #endif
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
        // 行内提示也一起清：上一轮的红字不该继续挂在新一轮的输入旁边
        completedMessage = nil
        inlineError = nil
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

    /// 待确认命令里「用户所说的那一天」（只有删除 / 修改意图带它）
    private var criteriaDay: Date? {
        switch pendingCommand {
        case .deleteEvent(let d): return d.criteria.day
        case .updateEvent(let d): return d.criteria.day
        default: return nil
        }
    }

    /// 确认区「当前时间」显示的值。
    ///
    /// 重复日程的 `startDate` 只是序列**锚点**（可能是几个月前），与用户说的「明天」无关 ——
    /// 直接显示锚点日期会让人不敢确认（也可能误以为是另一条日程）。
    /// 这里改用「用户所说的那一天 + 原时分」。
    private func occurrenceText(for target: CalendarEvent) -> String {
        // 解析逻辑在服务层（AIAssistantService.occurrenceStart），这里只负责格式化
        let day = criteriaDay ?? target.startDate
        return AIAssistantService.occurrenceStart(of: target, on: day)
            .formatted(date: .abbreviated, time: .shortened)
    }

    /// 当前待确认的目标是否为重复日程（必须在 resetAfterCompletion 之前取值）
    private var wasRepeatingTarget: Bool {
        destructiveTarget?.repeatRule != .never
    }

    /// 确认执行删除 / 修改（唯一写入路径是 AIAssistantService → EventService）
    private func confirmDestructive() {
        guard let command = pendingCommand else { return }
        switch AIAssistantService.shared.execute(command) {
        case .success(.deletedEvent):
            // 重复日程删的是整条序列，回执必须说清楚（否则用户以为只删了「明天那次」）
            showSuccess(wasRepeatingTarget
                        ? NSLocalizedString("已删除整条重复日程。", comment: "AI助手")
                        : NSLocalizedString("已删除该日程。", comment: "AI助手"))
            resetAfterCompletion()
        case .success(.updatedEvent):
            showSuccess(wasRepeatingTarget
                        ? NSLocalizedString("已修改整条重复日程的时间，提醒已重建。", comment: "AI助手")
                        : NSLocalizedString("已修改时间，提醒已重建。", comment: "AI助手"))
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
        case .success(.createdEvent(let id)):
            let created = EventStore.shared.eventBy(idString: id.uuidString)
            // 落点是今天还是别的日子：决定提示文案，以及要不要给「去看看」跳转。
            // 真机反馈（2026-09-30）：「明天上午10点…」会正确建到明天，但用户在今天的
            // 日历页上只看到"没有变化"，误以为没生效。所以这里必须**说出具体哪一天**。
            let startDate = created?.startDate ?? d.startDate
            let cal = Calendar(identifier: .gregorian)
            let isOtherDay = !cal.isDate(startDate, inSameDayAs: Date())
            if isOtherDay {
                let dayText = Self.dayFormatter.string(from: startDate)
                // 「去看看」的日期必须走 showSuccess 的参数：不能再单独赋值 completedOffDay，
                // 那会被 showSuccess 清掉（按钮永远不出现——见 showSuccess 的注释）。
                showSuccess(String(format: NSLocalizedString("已加入 %@ 的日程", comment: "AI助手：日程建在其它日子"), dayText),
                            offDay: startDate)
            } else {
                showSuccess(NSLocalizedString("日程已加入日历。", comment: "AI助手"))
            }
            input = ""
            draft = nil
            inputFocused = true
        case .success:
            break
        case .failure(let error):
            present(error)
        }
    }

    /// 提示里显示的日期（跟随设备区域；如 10月1日 / Oct 1）
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    /// 行内成功提示：自动消失（不打断连续输入，也省掉模态的两次点击）
    ///
    /// `offDay` 是「去看看」跳转按钮的**唯一入口**：非 nil 才渲染该按钮。
    /// ⚠️ 所以 `completedOffDay` 必须只由本方法读写。此前 `create()` 先
    /// `completedOffDay = startDate`、再调用本方法，而本方法开头会把它清空——
    /// 结果「去看看」按钮**从未出现过**：文案对（「已加入 10月3日 的日程」），
    /// 去路是死的。这正是 2026-10-02 UI 测试 Flow 3d 抓到的真因（当时提示文案是对的，
    /// 断言 1 通过、断言 2 失败，屏幕录制里能看到提示卡片没有按钮）。
    /// 删除 / 修改走的也是本方法，`offDay` 省略即 nil，顺手清掉上一次创建留下的按钮。
    private func showSuccess(_ text: String, offDay: Date? = nil) {
        inlineError = nil
        completedOffDay = offDay
        completedMessage = text
        // 带行动按钮的提示停留更久：2 秒够读一句纯文案，但不够「读日期 → 决定 → 点按钮」。
        // 「去看看」正是那次真机反馈的补救路径，抢不到就等于没做；UI 测试也不该跟秒表赛跑。
        // 这是 UX 取值，要调只动这两个常量。
        let dwell: Duration = offDay == nil ? Self.plainSuccessDwell : Self.actionableSuccessDwell
        Task { @MainActor in
            try? await Task.sleep(for: dwell)
            if completedMessage == text {
                completedMessage = nil
                completedOffDay = nil
            }
        }
    }

    /// 纯文案提示停留时长（原行为）
    private static let plainSuccessDwell: Duration = .seconds(2)
    /// 带「去看看」按钮的提示停留时长：必须够用户读完并点中
    private static let actionableSuccessDwell: Duration = .seconds(6)

    /// 结构化错误统一展示（文案来自 AICommandError.message），行内呈现而非模态
    private func present(_ error: AICommandError) {
        inlineError = error.message
    }
}
#endif
