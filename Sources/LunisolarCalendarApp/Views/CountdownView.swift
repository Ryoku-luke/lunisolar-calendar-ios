#if canImport(SwiftUI)
import SwiftUI
import LunarCore
#if canImport(UIKit)
import UIKit
#endif

/// 倒数日 / 纪念日列表页
struct CountdownView: View {
    /// 深链 / Live Activity 卡片点击进来时高亮的条目（可选）
    var focusID: UUID? = nil
    /// iPad Inspector 选中态：传入后行点击变为「选中」（右栏跟随详情），不再直接弹编辑器
    var selectedID: UUID? = nil
    var onSelect: ((UUID) -> Void)? = nil

    @Environment(CountdownStore.self) private var store
    /// 编辑器目标：`nil` = 不呈现。合并自原先两个 sheet（`showingEditor` + `editingEvent`）——
    /// 两者指向同一个编辑器，状态不同步时会互相顶掉（月历页已用 `MonthEventEditSheet` 解决过同类问题）。
    @State private var editorTarget: CountdownEditorTarget?
    /// 行内「上岛」失败提示。从 `CountdownRow` 提升到列表层：
    /// 行本身是 `.accessibilityElement(children: .combine)`，把行动按钮放进行里会点不到。
    @State private var islandProblem: IslandProblem?

    private let today = Date()

    var body: some View {
        List {
            if store.events.isEmpty {
                // 统一空态（四要素：图标 + 标题 + 说明 + 行动按钮）。
                // 此前用 ContentUnavailableView，缺第四项——用户看完说明还得自己去右上角找「+」。
                QingheEmptyView(
                    icon: "hourglass",
                    title: NSLocalizedString("还没有倒数日", comment: ""),
                    message: NSLocalizedString("点击右上角添加生日、纪念日或重要日期", comment: ""),
                    actionTitle: NSLocalizedString("新建倒数日", comment: "")
                ) {
                    editorTarget = .new
                }
            } else {
                ForEach(store.events) { event in
                    CountdownRow(event: event, today: today) { islandProblem = $0 }
                        // 卡片点击深链直达 / iPad Inspector 选中：高亮对应条目，帮助用户一眼定位
                        .listRowBackground((focusID == event.id || selectedID == event.id)
                                           ? Color.appTint.opacity(0.12) : nil)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // iPad：点击 = 选中（右栏 Inspector 跟随显示详情）；
                            // iPhone：点击 = 直接编辑（保持既有行为）
                            if let onSelect { onSelect(event.id) } else { editorTarget = .existing(event) }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                // P0 收口：倒数日删除走 EventService（内部转 CountdownStore.delete，含下岛清理）
                                EventService.shared.deleteCountdown(id: event.id)
                            } label: { Label("删除", systemImage: "trash") }
                        }
                }
            }
        }
        .navigationTitle("倒数日")
        .largeTitleBar()
        .toolbar {
            ToolbarItem(placement: .platformTopBarTrailing) {
                Button { editorTarget = .new } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .touchTarget()
                .accessibilityLabel(NSLocalizedString("新建倒数日", comment: ""))
            }
        }
        .sheet(item: $editorTarget) { target in
            CountdownEditor(event: target.event)
                // P2-2：短表单不用从底缘升起的大 sheet——iPad 给中/大两档 detent
                // （与事件编辑器的 P1-8a 口径一致；iPhone 同样受益）
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        // 结果反馈不再用模态 alert（UI_DESIGN_REVIEW P0-3）：行内 toast。
        // 需要行动的场景（灵动岛未开启）在 toast 上带「去设置」按钮——不能退化成纯文案，
        // 否则就是 DEVICE_TEST_CHECKLIST §1.2 明令禁止的「静默失败」。
        .qingheToast(Binding(
            get: { islandProblem.map { toast(for: $0) } },
            set: { if $0 == nil { islandProblem = nil } }
        ))
    }

    private func toast(for problem: IslandProblem) -> ToastMessage {
        switch problem {
        case .denied(let message):
            return ToastMessage(kind: .warning, text: message,
                                actionTitle: NSLocalizedString("去设置", comment: "")) {
                islandProblem = nil
                #if canImport(UIKit)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                #endif
            }
        case .failed(let message):
            return ToastMessage(kind: .error, text: message)
        }
    }
}

/// 倒数日编辑器的目标：新建 / 编辑已有条目（一个枚举驱动一个 `.sheet(item:)`）
enum CountdownEditorTarget: Identifiable {
    case new
    case existing(CountdownEvent)
    var id: String {
        switch self {
        case .new:                 return "new"
        case .existing(let event): return event.id.uuidString
        }
    }
    /// nil = 新建
    var event: CountdownEvent? {
        switch self {
        case .new:                 return nil
        case .existing(let event): return event
        }
    }
}

/// 倒数日行「上岛」失败的两类原因
enum IslandProblem: Equatable {
    /// 系统「实时活动」或 App 内「时间胶囊」开关被关 → 要指引用户去开（带行动按钮）
    case denied(message: String)
    /// Activity.request 启动失败（系统预算等）→ 如实告知具体原因
    case failed(message: String)
}

// MARK: - 行

private struct CountdownRow: View {
    let event: CountdownEvent
    let today: Date
    /// 上岛失败的上报出口。呈现放在 CountdownView 那一层（理由见 `IslandProblem` 的注释）
    var onIslandProblem: (IslandProblem) -> Void
    /// 该倒数日是否已上灵动岛（Live Activity 活跃）
    @State private var isOnIsland = false

    var body: some View {
        HStack(spacing: AppTheme.Spacing.lg) {
            Text(event.emoji)
                // emoji 字形按 48×48 方框定尺寸，不是文字排版，故不走 AppTheme.Font 阶梯
                // （numeralXL 是 56，塞进这个方框会溢出）。UI_DESIGN_REVIEW P2-1 把它列为豁免。
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .frame(width: 48, height: 48)
                .background(Color.themeQuaternaryFill)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(event.title)
                    .font(AppTheme.Font.bodyBold)
                    .foregroundStyle(Color.label)
                // 不固定 locale：日期格式跟随界面语言（写死 zh_Hans_CN 会在英/日界面冒中文）
                Text(event.date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted)))
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(Color.secondaryLabel)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(event.displayText(today: today))
                    .font(AppTheme.Font.title3)
                    .foregroundStyle(abs(event.daysFrom(today: today)) <= 7 ? Color.festiveRed : Color.label)
                Text(event.kind.label)
                    .font(AppTheme.Font.caption2)
                    .foregroundStyle(Color.tertiaryLabel)
                // 灵动岛快捷开关：点一下上岛（灵动岛/锁屏实时倒计时），再点下岛
                // （原创交互，参考 iOS 17 系统灵动岛触达但不照抄；Live Activity 由系统驱动零耗电）
                Button {
                    toggleIsland()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: isOnIsland ? "liveactivity.fill" : "liveactivity")
                            .font(.caption2.weight(.bold))
                        Text(isOnIsland ? NSLocalizedString("在岛上", comment: "") : NSLocalizedString("上岛", comment: ""))
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(isOnIsland ? Color.appTint : Color.secondaryLabel)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(isOnIsland ? Color.appTint.opacity(0.12) : Color.clear))
                    .overlay(Capsule().stroke(isOnIsland ? Color.appTint.opacity(0.35) : Color.clear,
                                              lineWidth: AppTheme.Stroke.hair))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .pressableFeedback()
                .accessibilityLabel(isOnIsland
                    ? String(format: NSLocalizedString("%@ 已上灵动岛，点击下岛", comment: ""), event.title)
                    : String(format: NSLocalizedString("让 %@ 上灵动岛", comment: ""), event.title))
            }
        }
        .padding(.vertical, AppTheme.Spacing.xs)
        #if canImport(UIKit)
        // P1-2：指针悬停系统高亮（iPad 鼠标/妙控板）
        .hoverEffect(.highlight)
        #endif
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.title) \(event.displayText(today: today))")
        .onAppear { refreshIslandState() }
        .onChange(of: event) { _, _ in refreshIslandState() }
    }

    private func refreshIslandState() {
        // P0 遗留收口：岛上状态查询走 CountdownActivityController（View 不碰 ActivityKit）
        isOnIsland = CountdownActivityController.shared.isOnIsland(eventID: event.id)
    }

    private func toggleIsland() {
        // P0 遗留收口：上岛/下岛走 CountdownActivityController，View 只按结果弹 alert
        switch CountdownActivityController.shared.toggleIsland(for: event) {
        case .started:
            isOnIsland = true
        case .ended:
            isOnIsland = false
        case .systemDenied:
            // 系统「实时活动」总开关关闭（用户可在 设置→通知→清和日历 重新开启）
            onIslandProblem(.denied(message: NSLocalizedString(
                "请在「设置 → 通知 → 清和日历」中开启「实时活动」后重试。", comment: "")))
        case .appSettingDisabled:
            // App 内「时间胶囊」总开关关闭（设置 → 提醒与时间胶囊）
            onIslandProblem(.denied(message: NSLocalizedString(
                "「时间胶囊」已关闭。请在 App 内「我的 → 提醒与时间胶囊」中开启后重试。", comment: "")))
        case .failed(let message):
            // 启动失败（系统预算 / 权限窗口 / 设备限制等）：如实展示具体错误以便定位
            onIslandProblem(.failed(message: message.isEmpty
                ? NSLocalizedString("暂时无法启动实时活动，请稍后重试。", comment: "")
                : message))
        }
    }
}

// MARK: - 编辑器

struct CountdownEditor: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var date = Date()
    @State private var kind: CountdownKind = .countdown
    @State private var emoji = "📅"
    @State private var note = ""
    /// 越界提示（行内，不再用模态 alert；见 `save()` 的说明）
    @State private var rangeHint: String?

    private let editing: CountdownEvent?
    private let emojis = ["📅", "🎂", "💍", "🎓", "🏖️", "✈️", "🏠", "🎉", "❤️", "🎯", "📝", "🎁"]
    // 允许选择的合法日期范围（和 LunarDate 一致，避免类型=anniversary 周年时 nextAnniversary
    // 走到 Gregorian fallback 返回假农历语义；倒计时也给一致边界避免选到极端日期）。
    // P3-5 修复：cal.date(from:) 不再强制解包——1900-01-01/2100-12-31 恒合法，
    // 但为防御未来 minYear/maxYear 边界调整导致的崩溃，改为 guard 兜底。
    private let allowedDateRange: ClosedRange<Date> = {
        let cal = Calendar(identifier: .gregorian)
        var minComps = DateComponents(); minComps.year = ChineseCalendar.minYear; minComps.month = 1; minComps.day = 1
        var maxComps = DateComponents(); maxComps.year = ChineseCalendar.maxYear; maxComps.month = 12; maxComps.day = 31
        guard let min = cal.date(from: minComps), let max = cal.date(from: maxComps) else {
            // 理论不可达；兜底为"今天前后各一年"，避免空范围导致 DatePicker 崩溃
            let now = Date()
            return now.addingTimeInterval(-365 * 86400)...now.addingTimeInterval(365 * 86400)
        }
        return min...max
    }()

    init(event: CountdownEvent?) {
        editing = event
        _title = State(initialValue: event?.title ?? "")
        _date = State(initialValue: event?.date ?? Date().addingMonths(1))
        _kind = State(initialValue: event?.kind ?? .countdown)
        _emoji = State(initialValue: event?.emoji ?? "📅")
        _note = State(initialValue: event?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("标题", text: $title)
                    Picker("类型", selection: $kind) {
                        ForEach(CountdownKind.allCases, id: \.self) { k in
                            Label(k.label, systemImage: k.icon).tag(k)
                        }
                    }
                    DatePicker("日期", selection: $date, in: allowedDateRange, displayedComponents: .date)
                }
                Section {
                    Label(String(format: NSLocalizedString("支持范围：%d 年 1 月 — %d 年 12 月", comment: ""), ChineseCalendar.minYear, ChineseCalendar.maxYear),
                          systemImage: "calendar.badge.clock")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                }

                Section("图标") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                        ForEach(emojis, id: \.self) { e in
                            Text(e)
                                .font(.system(size: 28))
                                .frame(width: 44, height: 44)
                                .background(emoji == e ? Color.accentColor.opacity(0.2) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
                                .onTapGesture { emoji = e }
                        }
                    }
                }

                // 越界提示：行内文案，不再用模态 alert（UI_DESIGN_REVIEW P0-3）。
                // 这是「极不可能发生」的程序级兜底（DatePicker 已 in: range），
                // 为它弹一个需要点「好」的模态不划算。
                if let rangeHint {
                    Section {
                        Label(rangeHint, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.systemOrange)
                            .accessibilityIdentifier(AccessibilityID.stateError)
                    }
                }

                Section("备注（可选）") {
                    TextField("添加备注", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(editing == nil
                ? NSLocalizedString("新建倒数日", comment: "")
                : NSLocalizedString("编辑倒数日", comment: ""))
            .inlineTitleBar()
            .toolbar {
                ToolbarItem(placement: .platformTopBarTrailing) {
                    Button("保存") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                        .font(.body.weight(.semibold))
                }
                ToolbarItem(placement: .platformTopBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func save() {
        // 范围兜底（即使 DatePicker 已 in: range，极端场景再做一次程序级校验）
        guard allowedDateRange.contains(date) else {
            rangeHint = String(format: NSLocalizedString("请将日期调整到 %d 年 1 月 1 日 — %d 年 12 月 31 日之间。", comment: ""),
                               ChineseCalendar.minYear, ChineseCalendar.maxYear)
            return
        }
        let event = CountdownEvent(
            id: editing?.id ?? UUID(),
            title: title.trimmingCharacters(in: .whitespaces),
            date: date,
            kind: kind,
            emoji: emoji,
            note: note.isEmpty ? nil : note
        )
        // P0 收口：倒数日写操作统一走 EventService（内部按 id 是否存在决定 add/update）。
        // P2 修复语义保留：保存按钮会立刻 dismiss 并很可能进入后台/被用户上滑杀进程，
        // 0.5s saveDebounce 里的 Task.sleep 在后台不一定能按时跑完，
        // flush=true 确保这次变更一定落盘（防丢数据）。
        EventService.shared.saveCountdown(event, flush: true)
        // P0 遗留收口：保存后的自动上岛策略在 CountdownActivityController
        // （新建自动上岛；编辑且已在岛上 → 同步新内容；手动下岛过 → 不打扰）
        CountdownActivityController.shared.autoStartAfterSave(isNew: editing == nil, event: event)
        dismiss()
    }
}
#endif
