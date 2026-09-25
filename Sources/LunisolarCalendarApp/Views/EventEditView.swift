#if canImport(SwiftUI)
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import LunarCore

// MARK: - 新建 / 编辑日程（iOS 27 原生化改造）
//
// 设计对齐系统「日历 / 提醒事项」：Form + insetGrouped 分组列表、
// 行内 LabeledContent + Menu（替代旧版横向 chip 按钮）、
// 原生 segmented 类型切换、toolbar 取消/保存、编辑态底部红色删除。
// 说明：EventEditView 不再自包 NavigationStack（push 场景继承外层导航；
// sheet 场景由调用方包 NavigationStack，见 DayDetailView）。

struct EventEditView: View {
    @Environment(EventStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let original: CalendarEvent?
    let defaultDate: Date
    @State private var title: String = ""
    @State private var type: EventType = .schedule
    @State private var notes: String = ""
    @State private var priority: Priority = .normal
    @State private var repeatRule: RepeatRule = .never
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date()
    @State private var isAllDay: Bool = false
    @State private var reminderEnabled: Bool = false
    @State private var reminderMinutesBefore: Int = 10
    @State private var isCompleted: Bool = false
    @State private var showDeleteConfirm = false
    private var isEditing: Bool { original != nil }
    private var gregorian: Calendar { Calendar(identifier: .gregorian) }
    /// 黄历/农历数据支持范围（1900-01-01 — 2100-12-31）。
    /// 约束 DatePicker 可选区间，防止选到范围外日期导致农历/黄历越界显示异常（假农历）。
    private var supportedDateRange: ClosedRange<Date> {
        let cal = Calendar(identifier: .gregorian)
        let start = cal.date(from: DateComponents(year: ChineseCalendar.minYear, month: 1, day: 1, hour: 0, minute: 0)) ?? Date.distantPast
        let end = cal.date(from: DateComponents(year: ChineseCalendar.maxYear, month: 12, day: 31, hour: 23, minute: 59)) ?? Date.distantFuture
        return start...end
    }
    private var reminderOptions: [Int] { [0, 5, 10, 15, 30, 60, 1440] }
    /// 节日自适应强调色（与月/日/设置页一致）
    private var accent: Color {
        let fs = FestivalManager.festivals(on: defaultDate, lunar: defaultDate.lunar)
        return fs.first.map { Color(hex: $0.accentHex) } ?? Color.appTint
    }

    init(editing: CalendarEvent?, defaultDate: Date = Date()) {
        self.original = editing
        self.defaultDate = defaultDate
        if let ev = editing {
            _title = State(initialValue: ev.title)
            _type = State(initialValue: ev.type)
            _notes = State(initialValue: ev.notes ?? "")
            _priority = State(initialValue: ev.priority)
            _repeatRule = State(initialValue: ev.repeatRule)
            _startDate = State(initialValue: ev.startDate)
            _endDate = State(initialValue: ev.endDate)
            _isAllDay = State(initialValue: ev.isAllDay)
            _reminderEnabled = State(initialValue: ev.reminderOffsetMinutes != nil)
            _reminderMinutesBefore = State(initialValue: ev.reminderOffsetMinutes ?? 10)
            _isCompleted = State(initialValue: ev.isCompleted)
        } else {
            let cal = Calendar(identifier: .gregorian)
            let start = cal.date(bySettingHour: 9, minute: 0, second: 0, of: defaultDate) ?? defaultDate
            let end = cal.date(byAdding: .hour, value: 1, to: start) ?? start
            _startDate = State(initialValue: start)
            _endDate = State(initialValue: end)
        }
    }

    var body: some View {
        Form {
            // 标题 + 类型（系统日历：无 section header 的第一组）
            Section {
                TextField("标题", text: $title, axis: .vertical)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1...3)
                    .padding(.vertical, 2)
                    .accessibilityIdentifier(AccessibilityID.editTitle)
                Picker("类型", selection: $type) {
                    ForEach(EventType.allCases) { t in
                        Text(t.uiLabel).tag(t)
                    }
                }
                .pickerStyle(.segmented)
            }

            // 时间
            Section("时间") {
                if type != .note {
                    Toggle("全天", isOn: $isAllDay)
                    DatePicker("开始", selection: $startDate, in: supportedDateRange,
                               displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                        .environment(\.calendar, gregorian)
                        .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
                        .datePickerStyle(.compact)
                    DatePicker("结束", selection: $endDate, in: supportedDateRange,
                               displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                        .environment(\.calendar, gregorian)
                        .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
                        .datePickerStyle(.compact)
                        .onChange(of: startDate, initial: false) { _, newVal in
                            if endDate < newVal { endDate = newVal }
                        }
                } else {
                    DatePicker("日期", selection: $startDate, in: supportedDateRange, displayedComponents: [.date])
                        .environment(\.calendar, gregorian)
                        .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
                        .datePickerStyle(.compact)
                }
                if type != .note {
                    // 「提醒」类型本身到点就要响，语义上不存在「无」→ 不提供该选项，
                    // 未选提前量时按「准时」处理（与 save() 存的 0 一致）。
                    LabeledContent("提醒") {
                        Menu {
                            if type != .reminder {
                                Button {
                                    reminderEnabled = false
                                } label: {
                                    if effectiveReminderOffset == nil {
                                        Label("无", systemImage: "checkmark")
                                    } else {
                                        Text("无")
                                    }
                                }
                                Divider()
                            }
                            ForEach(reminderOptions, id: \.self) { m in
                                Button {
                                    reminderEnabled = true
                                    reminderMinutesBefore = m
                                } label: {
                                    if effectiveReminderOffset == m {
                                        Label(reminderLabel(m), systemImage: "checkmark")
                                    } else {
                                        Text(reminderLabel(m))
                                    }
                                }
                            }
                        } label: {
                            menuValueLabel(effectiveReminderOffset.map(reminderLabel) ?? NSLocalizedString("无", comment: ""))
                        }
                    }
                }
            }

            // 重复 + 优先级（Menu 行替代旧 chip 横排）
            Section("重复与优先级") {
                LabeledContent("重复") {
                    Menu {
                        ForEach(repeatOptions) { rule in
                            Button {
                                withAnimation(AppTheme.Motion.pressInOut) { repeatRule = rule }
                            } label: {
                                if repeatRule == rule {
                                    Label(rule.uiLabel, systemImage: "checkmark")
                                } else {
                                    Text(rule.uiLabel)
                                }
                            }
                        }
                    } label: {
                        menuValueLabel(repeatRule.uiLabel)
                    }
                }
                LabeledContent("优先级") {
                    Menu {
                        ForEach(Priority.allCases) { p in
                            Button {
                                withAnimation(AppTheme.Motion.pressInOut) { priority = p }
                            } label: {
                                if priority == p {
                                    Label(p.uiLabel, systemImage: "checkmark")
                                } else {
                                    Text(p.uiLabel)
                                }
                            }
                        }
                    } label: {
                        menuValueLabel(priority.uiLabel)
                    }
                }
            }

            // 备注
            Section("备注") {
                TextField("备注内容（可选）", text: $notes, axis: .vertical)
                    .font(.body)
                    .lineLimit(3...8)
                    .frame(minHeight: 88, alignment: .top)
            }

            // 状态（仅编辑态）
            if isEditing {
                Section("状态") {
                    Toggle("已完成", isOn: $isCompleted)
                        .tint(.green)
                    if let ev = original {
                        LabeledContent("创建时间", value: formatStamp(ev.createdAt))
                            .font(.caption)
                        LabeledContent("更新时间", value: formatStamp(ev.updatedAt))
                            .font(.caption)
                    }
                }
            }
        }
        .navigationTitle(isEditing ? String(format: NSLocalizedString("编辑%@", comment: ""), type.uiLabel) : String(format: NSLocalizedString("新建%@", comment: ""), type.uiLabel))
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .platformTopBarLeading) {
                Button("取消") { dismiss() }
                    .font(.subheadline.weight(.medium))
            }
            ToolbarItem(placement: .platformTopBarTrailing) {
                Button(isEditing ? NSLocalizedString("保存", comment: "") : NSLocalizedString("添加", comment: "")) { save() }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier(AccessibilityID.editSave)
            }
        }
        .tint(accent)
        // 编辑态底部红色删除（系统日历同款布局）
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isEditing {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Text(String(format: NSLocalizedString("删除此%@", comment: ""), type.uiLabel))
                        .font(.body.weight(.medium))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .background(.bar)
                .accessibilityIdentifier(AccessibilityID.editDelete)
            }
        }
        .alert("确认删除", isPresented: $showDeleteConfirm) {
            Button("删除", role: .destructive) {
                if let ev = original { EventService.shared.removeEvent(ev, flush: true) }
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(String(format: NSLocalizedString("确定要删除这个%@吗？删除后无法恢复。", comment: ""), type.uiLabel))
        }
    }

    /// Menu 右侧值：次要文字 + 上下箭头（原生样式）
    private func menuValueLabel(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }

    private var repeatOptions: [RepeatRule] {
        var base: [RepeatRule] = [.never, .daily, .weekly, .monthly, .yearly]
        if type != .note { base.append(.lunarAnnually) }
        return base
    }

    /// 提醒行当前**生效**的提前量（分钟）：nil = 不提醒。
    /// 「提醒」类型不提供「无」选项，未选提前量即 0（准时）——界面显示与落库值同源，
    /// 与 NotificationManager.shouldScheduleNotification 的判定一一对应。
    private var effectiveReminderOffset: Int? {
        if reminderEnabled { return reminderMinutesBefore }
        return type == .reminder ? 0 : nil
    }

    private func reminderLabel(_ minutes: Int) -> String {
        // String 上下文：必须显式 NSLocalizedString，否则永远显示中文
        switch minutes {
        case 0: return NSLocalizedString("准时", comment: "")
        case 5: return NSLocalizedString("5 分钟前", comment: "")
        case 10: return NSLocalizedString("10 分钟前", comment: "")
        case 15: return NSLocalizedString("15 分钟前", comment: "")
        case 30: return NSLocalizedString("30 分钟前", comment: "")
        case 60: return NSLocalizedString("1 小时前", comment: "")
        case 1440: return NSLocalizedString("1 天前", comment: "")
        default: return String(format: NSLocalizedString("%d 分钟前", comment: ""), minutes)
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var end = endDate
        if type == .note { end = startDate }
        if end < startDate { end = startDate }
        // 提醒偏移的口径（与 NotificationManager.shouldScheduleNotification 对齐）：
        // 记事不参与提醒，必须清空——否则把「日程+10分钟前」切成记事时旧偏移会残留；
        // 其余类型取界面上生效的提前量（提醒类型未选时是 0 = 准时）。
        let reminderOffset: Int? = (type == .note) ? nil : effectiveReminderOffset
        let now = Date()
        if let ev = original {
            var copy = ev
            copy.title = trimmed; copy.type = type; copy.notes = notes.isEmpty ? nil : notes
            copy.priority = priority; copy.repeatRule = repeatRule
            copy.startDate = startDate; copy.endDate = end; copy.isAllDay = isAllDay
            copy.reminderOffsetMinutes = reminderOffset; copy.isCompleted = isCompleted
            copy.updatedAt = now
            // 用户任何编辑都重置 isNotified（避免：一次性提醒 markNotified=true→用户改了日期→
            // scheduleNotification 由于 isNotified=true 直接 return，新的提醒永远不会被挂上）
            copy.isNotified = false
            EventService.shared.upsertEvent(copy)
        } else {
            let ev = CalendarEvent(title: trimmed, type: type, startDate: startDate, endDate: end,
                isAllDay: isAllDay, notes: notes.isEmpty ? nil : notes,
                repeatRule: repeatRule, priority: priority,
                reminderOffsetMinutes: reminderOffset)
            EventService.shared.upsertEvent(ev)
        }
        // 只刷新当前事件的通知：避免 O(N) 全量 cancelAll+reschedule 导致
        // badge 短暂闪烁、大事件库下保存卡顿、不必要的 UN 系统调用
        // （文档 #37：View 不直接操作 UNUserNotificationCenter，统一走 EventService）
        // 注意：upsertEvent 内部的 saveEvent 已调用 refreshNotification(for:)，
        // 此处不再重复调度（消除 cancel+schedule 双份系统调用）。
        // 用户点击保存后立即退出，主动 flush 避免防抖窗口内被系统终止导致数据回滚。
        // P0 收口：不绕过 Service 直连 store。
        EventService.shared.flushPendingSave()
        // 保存成功计入 App Store 评分引导（阈值 5 次 + 90 天冷却）
        RatingPromptCoordinator.registerMeaningfulAction()
        dismiss()
    }

    private func formatStamp(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        return fmt.string(from: date)
    }
}

#endif
