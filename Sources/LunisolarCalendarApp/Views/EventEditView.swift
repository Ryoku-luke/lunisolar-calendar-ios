#if canImport(SwiftUI)
import SwiftUI

// MARK: - 日程/记事 编辑界面

struct EventEditView: View {
    @Environment(EventStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let editing: CalendarEvent?
    let defaultDate: Date

    // 表单状态
    @State private var title: String
    @State private var type: EventType
    @State private var date: Date
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var isAllDay: Bool
    @State private var location: String
    @State private var notes: String
    @State private var repeatRule: RepeatRule
    @State private var priority: Priority
    @State private var isCompleted: Bool

    @State private var showDeleteConfirm = false

    init(editing: CalendarEvent?, defaultDate: Date) {
        self.editing = editing
        self.defaultDate = defaultDate

        let cal = Calendar.current
        let defaultStart: Date
        let defaultEnd: Date
        if let e = editing {
            defaultStart = e.startDate
            defaultEnd = e.endDate
        } else {
            let startComps = cal.dateComponents([.year,.month,.day], from: defaultDate)
            var sComps = startComps
            sComps.hour = 9; sComps.minute = 0
            defaultStart = cal.date(from: sComps) ?? defaultDate
            var eComps = startComps
            eComps.hour = 10; eComps.minute = 0
            defaultEnd = cal.date(from: eComps) ?? defaultStart.addingTimeInterval(3600)
        }

        _title = State(initialValue: editing?.title ?? "")
        _type = State(initialValue: editing?.type ?? .schedule)
        _date = State(initialValue: Calendar.current.startOfDay(for: defaultStart))
        _startTime = State(initialValue: defaultStart)
        _endTime = State(initialValue: defaultEnd)
        _isAllDay = State(initialValue: editing?.isAllDay ?? false)
        _location = State(initialValue: editing?.location ?? "")
        _notes = State(initialValue: editing?.notes ?? "")
        _repeatRule = State(initialValue: editing?.repeatRule ?? .never)
        _priority = State(initialValue: editing?.priority ?? .normal)
        _isCompleted = State(initialValue: editing?.isCompleted ?? false)
    }

    var isEditing: Bool { editing != nil }

    var body: some View {
        NavigationStack {
            Form {
                // 标题 + 类型
                titleSection

                // 时间
                timeSection

                // 重复 + 优先级
                repeatAndPrioritySection

                // 地点 + 备注
                detailsSection

                // 状态 (编辑时显示)
                if isEditing {
                    statusSection
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "编辑\(type.title)" : "新建\(type.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "保存" : "添加") {
                        save()
                    }
                    .font(.headline.weight(.bold))
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if isEditing {
                    ToolbarItem(placement: .bottomBar) {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("删除此\(type.title)", systemImage: "trash.fill")
                                .foregroundStyle(Color.systemRed)
                        }
                    }
                }
            }
            .alert("确认删除", isPresented: $showDeleteConfirm) {
                Button("删除", role: .destructive, action: delete)
                Button("取消", role: .cancel) {}
            } message: {
                Text("删除后将无法恢复此\(type.title)。")
            }
        }
    }

    // MARK: - 表单区块

    private var titleSection: some View {
        Section {
            TextField("标题", text: $title, prompt: Text("例如：产品评审会议"))
                .font(.headline)

            Picker("类型", selection: $type) {
                ForEach(EventType.allCases) { t in
                    Label(t.title, systemImage: t.systemIcon).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: type) { _, newValue in
                // 切换类型时调整默认值
                if newValue == .note {
                    isAllDay = true
                }
            }
        } header: {
            Text("基本信息")
        } footer: {
            Text("不同类型可帮助你区分日程、提醒和备忘事项")
        }
    }

    private var timeSection: some View {
        Section {
            Toggle("全天事件", isOn: $isAllDay)
                .tint(Color.systemGreen)

            DatePicker("日期", selection: $date, displayedComponents: .date)
                .datePickerStyle(.compact)

            if !isAllDay {
                DatePicker("开始时间", selection: $startTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.compact)

                DatePicker("结束时间", selection: $endTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.compact)
            }
        } header: {
            Text("时间")
        } footer: {
            Text(isAllDay ? "全天事件将在日历上占满整天。" : "精确设定起止时间以便提醒你按时到场。")
        }
    }

    private var repeatAndPrioritySection: some View {
        Section {
            Picker("重复", selection: $repeatRule) {
                ForEach(RepeatRule.allCases) { r in
                    Text(r.title).tag(r)
                }
            }

            Picker("优先级", selection: $priority) {
                ForEach(Priority.allCases) { p in
                    Label(p.title, systemImage: "flag.fill")
                        .foregroundStyle(p.tintColor)
                        .tag(p)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("重复 & 优先级")
        }
    }

    private var detailsSection: some View {
        Section {
            HStack {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(Color.systemRed)
                    .frame(width: 22)
                TextField("地点（选填）", text: $location, prompt: Text("例如：3号会议室"))
            }

            HStack(alignment: .top) {
                Image(systemName: "note.text")
                    .foregroundStyle(Color.systemIndigo)
                    .frame(width: 22)
                    .padding(.top, 4)
                TextField("备注（选填）", text: $notes, prompt: Text("可以写一些补充信息…"), axis: .vertical)
                    .lineLimit(3...6)
            }
        } header: {
            Text("地点 & 备注")
        }
    }

    private var statusSection: some View {
        Section {
            Toggle("\(type.title)已完成", isOn: $isCompleted)
                .tint(Color.systemGreen)
            HStack {
                Text("创建于")
                Spacer()
                Text(editing?.createdAt.formatted(date: .abbreviated, time: .shortened) ?? "")
                    .foregroundStyle(Color.secondaryLabel)
            }
            HStack {
                Text("最近更新")
                Spacer()
                Text(editing?.updatedAt.formatted(date: .abbreviated, time: .shortened) ?? "")
                    .foregroundStyle(Color.secondaryLabel)
            }
        } header: {
            Text("状态")
        }
    }

    // MARK: - 操作

    private func buildEventDate() -> (start: Date, end: Date) {
        let cal = Calendar.current
        // 将 date + startTime 合成
        let dc = cal.dateComponents([.year,.month,.day], from: date)
        let stDC = cal.dateComponents([.hour,.minute,.second], from: startTime)
        let etDC = cal.dateComponents([.hour,.minute,.second], from: endTime)
        var sc = DateComponents()
        sc.year = dc.year; sc.month = dc.month; sc.day = dc.day
        sc.hour = isAllDay ? 0 : stDC.hour
        sc.minute = isAllDay ? 0 : stDC.minute
        sc.second = 0
        var ec = sc
        ec.hour = isAllDay ? 23 : etDC.hour
        ec.minute = isAllDay ? 59 : etDC.minute
        ec.second = isAllDay ? 59 : 0

        let s = cal.date(from: sc) ?? startTime
        var e = cal.date(from: ec) ?? endTime
        if e <= s {
            e = s.addingTimeInterval(isAllDay ? 86399 : 3600)
        }
        return (s, e)
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let (s, e) = buildEventDate()

        if let editing = editing {
            var updated = editing
            // 如果开始时间或类型变了，重置通知状态并取消旧通知
            if updated.startDate != s || updated.type != type {
                updated.isNotified = false
                NotificationManager.shared.cancelNotification(for: updated)
            }
            updated.title = trimmed
            updated.type = type
            updated.startDate = s
            updated.endDate = e
            updated.isAllDay = isAllDay
            updated.location = location.isEmpty ? nil : location
            updated.notes = notes.isEmpty ? nil : notes
            updated.repeatRule = repeatRule
            updated.priority = priority
            updated.isCompleted = isCompleted
            store.update(updated)

            // 如果是提醒且未通知，重新调度
            if updated.type == .reminder && !updated.isNotified {
                Task {
                    _ = await NotificationManager.shared.requestAuthorization()
                    await NotificationManager.shared.scheduleNotification(for: updated)
                }
            }
        } else {
            let event = CalendarEvent(
                title: trimmed,
                type: type,
                startDate: s,
                endDate: e,
                isAllDay: isAllDay,
                location: location.isEmpty ? nil : location,
                notes: notes.isEmpty ? nil : notes,
                repeatRule: repeatRule,
                priority: priority,
                isCompleted: false
            )
            store.add(event)

            // 如果是提醒，申请权限并调度通知
            if event.type == .reminder {
                Task {
                    _ = await NotificationManager.shared.requestAuthorization()
                    await NotificationManager.shared.scheduleNotification(for: event)
                }
            }
        }
        dismiss()
    }

    private func delete() {
        guard let editing = editing else { return }
        // 删除前取消关联的通知
        NotificationManager.shared.cancelNotification(for: editing)
        store.delete(editing)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        EventEditView(editing: nil, defaultDate: Date())
            .environment(EventStore.shared)
    }
}

#endif
