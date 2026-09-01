#if canImport(SwiftUI)
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var isWide: Bool { hSizeClass == .regular }
    private var isEditing: Bool { original != nil }
    private var gregorian: Calendar { Calendar(identifier: .gregorian) }
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
            _startDate = State(initialValue: ev.start)
            _endDate = State(initialValue: ev.end)
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
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.section) {
                    titleBlock
                    timeBlock
                    repeatBlock
                    priorityBlock
                    detailBlock
                    if isEditing { statusBlock }
                    Color.clear.frame(height: AppTheme.Spacing.xxl)
                }
                .padding(.horizontal, isWide ? AppTheme.Spacing.xxl : AppTheme.Spacing.lg)
                .padding(.top, AppTheme.Spacing.lg)
                .frame(maxWidth: isWide ? 760 : .infinity)
                .frame(maxWidth: .infinity)
            }
            .festiveWallpaper(accent: accent)
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomActions }
            .navigationTitle(isEditing ? "编辑\(type.uiLabel)" : "新建\(type.uiLabel)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.navBar, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .font(.subheadline.weight(.medium))
                        .touchTarget(min: AppTheme.Touch.minTarget)
                }
            }
            .tint(accent)
            .alert("确认删除", isPresented: $showDeleteConfirm) {
                Button("删除", role: .destructive) {
                    if let ev = original { store.delete(eventID: ev.id) }
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("确定要删除这个\(type.uiLabel)吗？删除后无法恢复。")
            }
        }
    }

    private var bottomActions: some View {
        let accent = self.accent
        return VStack(spacing: AppTheme.Spacing.sm) {
            if isEditing {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("删除此\(type.uiLabel)", systemImage: "trash.fill")
                        .font(AppTheme.Font.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: AppTheme.Touch.minTarget)
                        .background(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                            .fill(Color.systemRed.opacity(0.10)))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                                .stroke(Color.systemRed.opacity(0.30), lineWidth: AppTheme.Stroke.hair)
                        )
                        .overlay(alignment: .top) {
                            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                                .fill(LinearGradient(colors: [Color.white.opacity(0.18), .clear],
                                                     startPoint: .top, endPoint: .bottom))
                                .frame(height: 22).allowsHitTesting(false).offset(y: 2)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
                        }
                        .foregroundStyle(Color.systemRed)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).pressableFeedback()
            }
            Button { save() } label: {
                Label(isEditing ? "保存修改" : "添加\(type.uiLabel)", systemImage: "checkmark.circle.fill")
                    .font(AppTheme.Font.bodyBold).frame(maxWidth: .infinity)
                    .frame(minHeight: AppTheme.Touch.minTarget)
                    .background {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                            .fill(LinearGradient(colors: [accent, accent.opacity(0.82)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                        RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                            .stroke(Color.white.opacity(0.24), lineWidth: AppTheme.Stroke.hair)
                    }
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                            .fill(LinearGradient(colors: [Color.white.opacity(0.22), .clear],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(height: 22).allowsHitTesting(false).offset(y: 2)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
                    }
                    .foregroundStyle(.white)
                    .shadow(color: accent.opacity(0.30), radius: 12, x: 0, y: 5)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).pressableFeedback()
             .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
             .opacity(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.top, AppTheme.Spacing.md)
        .padding(.bottom, AppTheme.Spacing.lg)
        .background(
            UnevenRoundedRectangle(cornerRadii: .init(topLeading: 24, topTrailing: 24))
                .fill(.ultraThinMaterial).ignoresSafeArea(edges: .bottom)
        )
        .overlay(
            UnevenRoundedRectangle(cornerRadii: .init(topLeading: 24, topTrailing: 24))
                .stroke(Color.separator.opacity(0.22), lineWidth: AppTheme.Stroke.hair)
        )
    }

    private var titleBlock: some View {
        _EditSectionCard(
            header: sectionHeader("内容", icon: "pencil.and.scribble", tint: accent),
            tint: accent
        ) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                TextField("请输入标题", text: $title, axis: .vertical)
                    .font(AppTheme.Font.title2.weight(.semibold))
                    .lineLimit(1...3)
                    .frame(minHeight: 36)
                FlexibleGrid(horizontalSpacing: AppTheme.Spacing.sm, verticalSpacing: AppTheme.Spacing.sm) {
                    ForEach(EventType.allCases) { t in
                        Button { withAnimation(AppTheme.Motion.pressInOut) { type = t } } label: {
                            HStack(spacing: 6) {
                                Image(systemName: t.iconName).font(AppTheme.Font.caption.weight(.semibold))
                                Text(t.uiLabel).font(AppTheme.Font.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(type == t ? .white : Color.label)
                            .padding(.horizontal, AppTheme.Spacing.md)
                            .frame(minHeight: AppTheme.Touch.chipHeight)
                            .background(RoundedRectangle(cornerRadius: AppTheme.Radius.pill, style: .continuous)
                                .fill(type == t ? t.tintColor : Color.quaternarySystemFill))
                            .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.pill, style: .continuous)
                                .stroke(type == t ? t.tintColor.opacity(0.5) : .clear,
                                        lineWidth: AppTheme.Stroke.hair))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain).pressableFeedback()
                    }
                }
            }
        }
    }

    private var timeBlock: some View {
        _EditSectionCard(
            header: sectionHeader("时间", icon: "clock.fill", tint: Color.systemOrange),
            tint: Color.systemOrange
        ) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                if type != .note {
                    Toggle(isOn: $isAllDay) {
                        Label("全天", systemImage: "sun.max").font(AppTheme.Font.bodyBold)
                    }.tint(accent)
                    DatePicker(selection: $startDate,
                               displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute]) {
                        Label("开始", systemImage: "calendar.badge.clock").font(AppTheme.Font.body)
                    }.environment(\.calendar, gregorian).datePickerStyle(.compact)
                    DatePicker(selection: $endDate,
                               displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute]) {
                        Label("结束", systemImage: "clock.badge.checkmark").font(AppTheme.Font.body)
                    }.environment(\.calendar, gregorian).datePickerStyle(.compact)
                        .onChange(of: startDate) { newVal in
                            if endDate < newVal { endDate = newVal }
                        }
                } else {
                    DatePicker(selection: $startDate, displayedComponents: [.date]) {
                        Label("记事日期", systemImage: "calendar").font(AppTheme.Font.body)
                    }.environment(\.calendar, gregorian).datePickerStyle(.compact)
                }
                if type != .note {
                    Toggle(isOn: $reminderEnabled) {
                        Label("开启提醒", systemImage: "bell.badge.fill").font(AppTheme.Font.bodyBold)
                    }.tint(Color.systemOrange)
                    if reminderEnabled {
                        HStack(alignment: .center, spacing: AppTheme.Spacing.md) {
                            ZStack {
                                RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                                    .fill(Color.systemOrange.opacity(0.14))
                                Image(systemName: "timer")
                                    .font(AppTheme.Font.caption.weight(.semibold))
                                    .foregroundStyle(Color.systemOrange)
                            }
                            .frame(width: 24, height: 24)
                            Text("提前").font(AppTheme.Font.body)
                            Spacer()
                            Picker("提前", selection: $reminderMinutesBefore) {
                                Text("准时").tag(0); Text("5 分钟").tag(5)
                                Text("10 分钟").tag(10); Text("15 分钟").tag(15)
                                Text("30 分钟").tag(30); Text("1 小时").tag(60)
                                Text("1 天").tag(1440)
                            }.pickerStyle(.menu).tint(Color.systemOrange)
                        }
                        .padding(AppTheme.Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                                .fill(Color.quaternarySystemFill)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                                .stroke(Color.separator.opacity(0.18), lineWidth: AppTheme.Stroke.hair)
                        )
                    }
                }
            }
        }
    }

    private var repeatBlock: some View {
        _EditSectionCard(
            header: sectionHeader("重复规则", icon: "repeat", tint: Color.systemPurple),
            tint: Color.systemPurple
        ) {
            FlexibleGrid(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(repeatOptions) { rule in
                    Button { withAnimation(AppTheme.Motion.pressInOut) { repeatRule = rule } } label: {
                        Text(rule.uiLabel)
                            .font(AppTheme.Font.subheadline.weight(.semibold))
                            .foregroundStyle(repeatRule == rule ? .white : Color.label)
                            .padding(.horizontal, AppTheme.Spacing.md)
                            .frame(minHeight: AppTheme.Touch.chipHeight)
                            .background(RoundedRectangle(cornerRadius: AppTheme.Radius.pill, style: .continuous)
                                .fill(repeatRule == rule ? accent : Color.quaternarySystemFill))
                            .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.pill, style: .continuous)
                                .stroke(repeatRule == rule ? accent.opacity(0.5) : .clear,
                                        lineWidth: AppTheme.Stroke.hair))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).pressableFeedback()
                }
            }
        }
    }

    private var repeatOptions: [RepeatRule] {
        var base: [RepeatRule] = [.never, .daily, .weekly, .monthly, .yearly]
        if type != .note { base.append(.lunarAnnually) }
        return base
    }

    private var priorityBlock: some View {
        _EditSectionCard(
            header: sectionHeader("优先级", icon: "exclamationmark.3", tint: Color.systemRed),
            tint: Color.systemRed
        ) {
            FlexibleGrid(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(Priority.allCases) { p in
                    Button { withAnimation(AppTheme.Motion.pressInOut) { priority = p } } label: {
                        HStack(spacing: 5) {
                            Image(systemName: p == .urgent ? "exclamationmark.octagon.fill" :
                                            p == .high ? "flame.fill" :
                                            p == .normal ? "flag.fill" : "flag")
                                .font(AppTheme.Font.caption)
                            Text(p.uiLabel).font(AppTheme.Font.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(priority == p ? .white : p.tintColor)
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .frame(minHeight: AppTheme.Touch.chipHeight)
                        .background(RoundedRectangle(cornerRadius: AppTheme.Radius.pill, style: .continuous)
                            .fill(priority == p ? p.tintColor : p.tintColor.opacity(0.10)))
                        .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.pill, style: .continuous)
                            .stroke(priority == p ? p.tintColor.opacity(0.45) : .clear,
                                    lineWidth: AppTheme.Stroke.hair))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain).pressableFeedback()
                }
            }
        }
    }

    private var detailBlock: some View {
        _EditSectionCard(
            header: sectionHeader("备注", icon: "note.text", tint: Color.systemTeal),
            tint: Color.systemTeal
        ) {
            TextField("备注内容（可选）", text: $notes, axis: .vertical)
                .font(AppTheme.Font.body).lineLimit(3...8)
                .frame(minHeight: 96, alignment: .top)
                .padding(AppTheme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .fill(Color.quaternarySystemFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .stroke(Color.separator.opacity(0.20), lineWidth: AppTheme.Stroke.hair)
                )
        }
    }

    private var statusBlock: some View {
        _EditSectionCard(
            header: sectionHeader("状态", icon: "checkmark.circle.trianglebadge.exclamationmark", tint: Color.systemGreen),
            tint: Color.systemGreen
        ) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Toggle(isOn: $isCompleted) {
                    Label("已完成", systemImage: "checkmark.seal.fill").font(AppTheme.Font.bodyBold)
                }.tint(Color.systemGreen)
                if let ev = original {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("创建时间：\(formatStamp(ev.createdAt))")
                            .font(AppTheme.Font.caption).foregroundStyle(Color.tertiaryLabel)
                        Text("更新时间：\(formatStamp(ev.updatedAt))")
                            .font(AppTheme.Font.caption).foregroundStyle(Color.tertiaryLabel)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                    .fill(tint.opacity(0.14))
                Image(systemName: icon)
                    .font(AppTheme.Font.caption.weight(.semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 24, height: 24)
            Text(title).font(AppTheme.Font.subheadline.weight(.semibold)).foregroundStyle(Color.secondaryLabel)
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var end = endDate
        if type == .note { end = startDate }
        if end < startDate { end = startDate }
        let reminderOffset: Int? = reminderEnabled ? reminderMinutesBefore : nil
        let now = Date()
        if let ev = original {
            var copy = ev
            copy.title = trimmed; copy.type = type; copy.notes = notes.isEmpty ? nil : notes
            copy.priority = priority; copy.repeatRule = repeatRule
            copy.start = startDate; copy.end = end; copy.isAllDay = isAllDay
            copy.reminderOffsetMinutes = reminderOffset; copy.isCompleted = isCompleted
            copy.updatedAt = now
            store.update(copy)
        } else {
            let ev = CalendarEvent(title: trimmed, type: type, start: startDate, end: end,
                isAllDay: isAllDay, repeatRule: repeatRule, priority: priority,
                notes: notes.isEmpty ? nil : notes, reminderOffsetMinutes: reminderOffset,
                createdAt: now, updatedAt: now)
            store.add(ev)
        }
        Task { await NotificationManager.shared.rescheduleAllReminders(in: store) }
        dismiss()
    }

    private func formatStamp(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        return fmt.string(from: date)
    }
}

private struct FlexibleGrid<Content: View>: View {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8
    @ViewBuilder var content: () -> Content
    var body: some View {
        FlowLayout(spacing: horizontalSpacing, lineSpacing: verticalSpacing, content: content)
    }
}

/// 编辑页通用分区卡：液态玻璃 + 顶部 section header + tint 浸染
private struct _EditSectionCard<Header: View, Content: View>: View {
    let header: Header
    let tint: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            header
            content()
        }
        .padding(AppTheme.Spacing.lg)
        .liquidCard(radius: AppTheme.Radius.xl,
                    material: .thinMaterial,
                    tint: tint,
                    shadow: AppTheme.Shadow.card,
                    highlight: 0.09)
    }
}

extension Priority {
    var uiLabel: String {
        switch self {
        case .low:    return "低"
        case .normal: return "中"
        case .high:   return "高"
        case .urgent: return "紧急"
        }
    }
}

#endif
