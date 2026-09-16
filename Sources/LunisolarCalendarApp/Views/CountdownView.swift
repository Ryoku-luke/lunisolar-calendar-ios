#if canImport(SwiftUI)
import SwiftUI
import LunarCore
#if canImport(UIKit)
import UIKit
#endif
#if canImport(ActivityKit)
import ActivityKit
#endif

/// 倒数日 / 纪念日列表页
struct CountdownView: View {
    @Environment(CountdownStore.self) private var store
    @State private var showingEditor = false
    @State private var editingEvent: CountdownEvent?

    private let today = Date()

    var body: some View {
        List {
            if store.events.isEmpty {
                ContentUnavailableView(
                    "还没有倒数日",
                    systemImage: "hourglass",
                    description: Text("点击右上角添加生日、纪念日或重要日期")
                )
            } else {
                ForEach(store.events) { event in
                    CountdownRow(event: event, today: today)
                        .contentShape(Rectangle())
                        .onTapGesture { editingEvent = event }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                store.delete(id: event.id)
                            } label: { Label("删除", systemImage: "trash") }
                        }
                }
            }
        }
        .navigationTitle("倒数日")
        .largeTitleBar()
        .toolbar {
            ToolbarItem(placement: .platformTopBarTrailing) {
                Button { editingEvent = nil; showingEditor = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .touchTarget()
            }
        }
        .sheet(isPresented: $showingEditor) {
            CountdownEditor(event: editingEvent)
        }
        .sheet(item: $editingEvent) { event in
            CountdownEditor(event: event)
        }
    }
}

// MARK: - 行

private struct CountdownRow: View {
    let event: CountdownEvent
    let today: Date
    /// 该倒数日是否已上灵动岛（Live Activity 活跃）
    @State private var isOnIsland = false
    /// 系统「实时活动」权限被关闭（设置→通知→清和日历）
    @State private var showLADeniedAlert = false
    /// Activity.request 启动失败（预算/系统限制等）
    @State private var showLAFailedAlert = false
    /// 启动失败的具体错误（如实展示，便于定位）
    @State private var lastLAError = ""

    var body: some View {
        HStack(spacing: AppTheme.Spacing.lg) {
            Text(event.emoji)
                // 用 AppTheme.Font.numeralXL 而非散落硬编码 size: 32
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .frame(width: 48, height: 48)
                .background(Color.themeQuaternaryFill)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(event.title)
                    .font(AppTheme.Font.bodyBold)
                    .foregroundStyle(Color.label)
                // 修复：Date.formatted(date:time:) 无 locale 参数，需用 Date.FormatStyle 显式构造
                Text(event.date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: Locale(identifier: "zh_Hans_CN"))))
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
                        Text(isOnIsland ? "在岛上" : "上岛")
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
                .accessibilityLabel(isOnIsland ? "\(event.title) 已上灵动岛，点击下岛" : "让 \(event.title) 上灵动岛")
            }
        }
        .padding(.vertical, AppTheme.Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.title) \(event.displayText(today: today))")
        .onAppear { refreshIslandState() }
        .onChange(of: event) { _, _ in refreshIslandState() }
        // 系统实时活动权限关闭：引导去设置开启
        .alert("灵动岛未开启", isPresented: $showLADeniedAlert) {
            Button("去设置") {
                #if canImport(UIKit)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                #endif
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("请在「设置 → 通知 → 清和日历」中开启「实时活动」后重试。")
        }
        // 启动失败（系统预算等）：如实告知具体原因
        .alert("上岛失败", isPresented: $showLAFailedAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text(lastLAError.isEmpty ? "暂时无法启动实时活动，请稍后重试。" : lastLAError)
        }
    }

    private func refreshIslandState() {
        #if canImport(ActivityKit)
        isOnIsland = CountdownActivityManager.activeActivityID(for: event.id) != nil
        #else
        isOnIsland = false
        #endif
    }

    private func toggleIsland() {
        #if canImport(ActivityKit)
        if isOnIsland {
            CountdownActivityManager.end(for: event.id)
            isOnIsland = false
        } else {
            // 先检查系统「实时活动」总开关（用户可在 设置→通知→清和日历 关闭）
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                showLADeniedAlert = true
                return
            }
            switch CountdownActivityManager.start(event: event) {
            case .success:
                isOnIsland = true
            case .failure(let error):
                // 启动失败（系统预算 / 权限窗口 / 设备限制等）：如实展示具体错误以便定位
                lastLAError = error.localizedDescription
                showLAFailedAlert = true
            }
        }
        #endif
    }
}

// MARK: - 编辑器

private struct CountdownEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CountdownStore.self) private var store

    @State private var title = ""
    @State private var date = Date()
    @State private var kind: CountdownKind = .countdown
    @State private var emoji = "📅"
    @State private var note = ""
    @State private var showOutOfRangeAlert = false

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
                        .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
                }
                Section {
                    Label("支持范围：\(ChineseCalendar.minYear) 年 1 月 — \(ChineseCalendar.maxYear) 年 12 月",
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
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .onTapGesture { emoji = e }
                        }
                    }
                }

                Section("备注（可选）") {
                    TextField("添加备注", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(editing == nil ? "新建倒数日" : "编辑倒数日")
            .inlineTitleBar()
            .alert("日期超出支持范围", isPresented: $showOutOfRangeAlert) {
                Button("好", role: .cancel) { }
            } message: {
                Text("请将日期调整到 \(ChineseCalendar.minYear) 年 1 月 1 日 — \(ChineseCalendar.maxYear) 年 12 月 31 日之间。")
            }
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
            showOutOfRangeAlert = true
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
        if editing != nil {
            store.update(event)
        } else {
            store.add(event)
        }
        // P2 修复：保存按钮会立刻 dismiss 并很可能进入后台/被用户上滑杀进程，
        //   0.5s saveDebounce 里的 Task.sleep 在后台不一定能按时跑完，
        //   直接 flush 确保这次 add/update 的变更一定落盘（防丢数据）。
        store.flushPendingSave()
        dismiss()
    }
}
#endif
