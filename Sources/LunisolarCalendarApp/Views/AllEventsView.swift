#if canImport(SwiftUI)
import SwiftUI
import LunarCore

// MARK: - 全部日程（统一管理页）
//
// 入口：日历工具栏菜单（iPhone）/ iPad 侧栏「全部日程」。
// 能力：
//   - 关键词搜索（标题 / 地点 / 备注）、类型筛选、显示已完成开关
//   - 排序：今天起优先（重复日程视为持续有效），已过去的一次性日程折叠在末尾
//   - 单条：点按编辑、左滑删除、长按菜单（完成 / 删除）
//   - 多选：批量标记完成 / 批量删除（批量删除有二次确认）
// 读走 EventStore 的只读查询，写一律经 EventService。

struct AllEventsView: View {
    @Environment(EventStore.self) private var store

    @State private var query = ""
    @State private var typeFilter: TypeFilter = .all
    @State private var showCompleted = false
    @State private var showPast = false
    @State private var editing: CalendarEvent?

    // 多选
    @State private var isSelecting = false
    @State private var selection = Set<UUID>()
    @State private var confirmBulkDelete = false

    enum TypeFilter: String, CaseIterable, Identifiable {
        case all, schedule, reminder, note

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return NSLocalizedString("全部", comment: "")
            case .schedule: return NSLocalizedString("日程", comment: "")
            case .reminder: return NSLocalizedString("提醒", comment: "")
            case .note: return NSLocalizedString("记事", comment: "")
            }
        }

        func matches(_ type: EventType) -> Bool {
            switch self {
            case .all: return true
            case .schedule: return type == .schedule
            case .reminder: return type == .reminder
            case .note: return type == .note
            }
        }
    }

    var body: some View {
        List {
            Section {
                Picker(NSLocalizedString("类型", comment: ""), selection: $typeFilter) {
                    ForEach(TypeFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)

                Toggle(isOn: $showCompleted) {
                    Label(NSLocalizedString("显示已完成", comment: ""), systemImage: "checkmark.circle")
                }
                .tint(Color.appTint)
            } footer: {
                Text(summaryText)
            }

            if filteredEvents.isEmpty {
                // 空态由 overlay 呈现，这里不占位
                EmptyView()
            } else if upcomingGroups.isEmpty {
                Section {
                    Label(NSLocalizedString("没有即将到来的日程。", comment: ""), systemImage: "checkmark.circle")
                        .foregroundStyle(Color.secondaryLabel)
                        .font(AppTheme.Font.subheadline)
                }
            }

            ForEach(upcomingGroups, id: \.day) { group in
                Section {
                    rows(group.events)
                } header: {
                    Text(dayHeader(group.day))
                }
            }

            // 已过去（一次性且早于今天）：默认折叠，避免历史日程把当前安排压到屏幕外
            if pastCount > 0 {
                Section {
                    Toggle(isOn: $showPast) {
                        Label(String(format: NSLocalizedString("显示已过去（%d 条）", comment: ""), pastCount),
                              systemImage: "clock.arrow.circlepath")
                    }
                    .tint(Color.appTint)
                }
                if showPast {
                    ForEach(pastGroups, id: \.day) { group in
                        Section {
                            rows(group.events)
                        } header: {
                            Text(dayHeader(group.day))
                        }
                    }
                }
            }
        }
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #else
        // macOS 无 insetGrouped；产品目标为 iOS，macOS 仅作 SPM 单测宿主
        .listStyle(.automatic)
        #endif
        .searchable(text: $query, prompt: Text(NSLocalizedString("搜索标题 / 地点 / 备注", comment: "")))
        .navigationTitle(NSLocalizedString("全部日程", comment: ""))
        .inlineTitleBar()
        .toolbar {
            ToolbarItem(placement: .platformTopBarTrailing) {
                Button(isSelecting
                       ? NSLocalizedString("完成", comment: "")
                       : NSLocalizedString("选择", comment: "")) {
                    withAnimation(AppTheme.Motion.screen) {
                        isSelecting.toggle()
                        if !isSelecting { selection.removeAll() }
                    }
                }
                .disabled(filteredEvents.isEmpty)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting { selectionBar }
        }
        .overlay {
            if filteredEvents.isEmpty {
                ContentUnavailableView(
                    NSLocalizedString("没有符合条件的日程", comment: ""),
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text(emptyHint)
                )
            }
        }
        .sheet(item: $editing) { event in
            NavigationStack {
                EventEditView(editing: event, defaultDate: event.startDate).environment(store)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        // 与管理页既有危险操作确认保持一致：alert + 破坏性按钮 + 取消（不用 confirmationDialog，
        // 后者的底部弹出样式与本 App 其他确认框风格不一致）
        .alert(String(format: NSLocalizedString("删除选中的 %d 条日程？", comment: ""), selection.count),
               isPresented: $confirmBulkDelete) {
            Button(NSLocalizedString("删除", comment: ""), role: .destructive) { bulkDelete() }
            Button(NSLocalizedString("取消", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("此操作不可恢复。重复日程会删除整条重复规则。", comment: ""))
        }
        // 筛选变化时清空选择：避免"看不见的行也被批量操作"
        .onChange(of: query) { _, _ in exitSelection() }
        .onChange(of: typeFilter) { _, _ in exitSelection() }
        .onChange(of: showCompleted) { _, _ in exitSelection() }
    }

    // MARK: - 行

    @ViewBuilder
    private func rows(_ events: [CalendarEvent]) -> some View {
        ForEach(events) { event in
            if isSelecting {
                Button {
                    toggleSelection(event)
                } label: {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        Image(systemName: selection.contains(event.id) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(selection.contains(event.id) ? Color.appTint : Color.tertiaryLabel)
                        EventRow(event: event, showsCompleteToggle: false)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(event.title)
                .accessibilityAddTraits(selection.contains(event.id) ? [.isSelected] : [])
            } else {
                // 整行是一个 Button（List 行内需显式 buttonStyle，否则点击被行吞掉）；
                // 按压反馈用 .pressableFeedback()（simultaneousGesture，不会抢走点击）
                Button {
                    editing = event
                } label: {
                    EventRow(event: event)
                }
                .buttonStyle(.plain)
                .pressableFeedback()
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        EventService.shared.removeEvent(event, flush: true)
                    } label: {
                        Label(NSLocalizedString("删除", comment: ""), systemImage: "trash")
                    }
                }
                .eventQuickActions(event)
            }
        }
    }

    /// 多选操作条：沿用月历底部悬浮胶囊的视觉语言（.ultraThinMaterial + Capsule + 细描边 + 轻阴影），
    /// 不再用"全宽材质条 + 分隔线"（在列表里显得突兀）。
    /// 两个动作都做了"选中为空时降级为次要色"的处理，避免禁用态看起来像坏掉。
    private var selectionBar: some View {
        HStack(spacing: AppTheme.Spacing.lg) {
            Button {
                bulkSetCompleted()
            } label: {
                Label(String(format: NSLocalizedString("完成 %d 项", comment: ""), selection.count),
                      systemImage: "checkmark.circle")
                    .font(AppTheme.Font.subheadline.weight(.semibold))
                    .foregroundStyle(selection.isEmpty ? Color.tertiaryLabel : Color.appTint)
            }
            .buttonStyle(.plain)
            .pressableFeedback()
            .disabled(selection.isEmpty)

            Rectangle()
                .fill(Color.separator)
                .frame(width: AppTheme.Stroke.hair, height: 18)

            Button {
                confirmBulkDelete = true
            } label: {
                Label(String(format: NSLocalizedString("删除 %d 项", comment: ""), selection.count),
                      systemImage: "trash")
                    .font(AppTheme.Font.subheadline.weight(.semibold))
                    .foregroundStyle(selection.isEmpty ? Color.tertiaryLabel : Color.systemRed)
            }
            .buttonStyle(.plain)
            .pressableFeedback()
            .disabled(selection.isEmpty)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().stroke(Color.separator.opacity(0.5), lineWidth: AppTheme.Stroke.hair))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 3)
        .padding(.bottom, AppTheme.Spacing.sm)
    }

    // MARK: - 数据

    private var todayStart: Date {
        QingheCalendarContext.userCalendar.startOfDay(for: Date())
    }

    private var filteredEvents: [CalendarEvent] {
        store.search(query: query)
            .filter { typeFilter.matches($0.type) }
            .filter { showCompleted || !$0.isCompleted }
    }

    /// 已过去 = 一次性日程且开始时间早于今天。
    /// 重复日程会继续发生，故归入"今天起"，不随历史起点沉底。
    private func isPast(_ event: CalendarEvent) -> Bool {
        event.repeatRule == .never && event.startDate < todayStart
    }

    private var pastEvents: [CalendarEvent] { filteredEvents.filter(isPast) }
    private var pastCount: Int { pastEvents.count }
    private var upcomingGroups: [(day: Date, events: [CalendarEvent])] {
        groups(from: filteredEvents.filter { !isPast($0) })
    }
    private var pastGroups: [(day: Date, events: [CalendarEvent])] {
        groups(from: pastEvents)
    }

    /// 按天分组（EventStore 内部按 startDate 升序，分组顺序天然有序）
    private func groups(from events: [CalendarEvent]) -> [(day: Date, events: [CalendarEvent])] {
        let cal = QingheCalendarContext.userCalendar
        var result: [(day: Date, events: [CalendarEvent])] = []
        for event in events {
            let day = cal.startOfDay(for: event.startDate)
            if let last = result.last, last.day == day {
                result[result.count - 1].events.append(event)
            } else {
                result.append((day, [event]))
            }
        }
        return result
    }

    // MARK: - 多选操作

    private func toggleSelection(_ event: CalendarEvent) {
        if selection.contains(event.id) {
            selection.remove(event.id)
        } else {
            selection.insert(event.id)
        }
    }

    private func exitSelection() {
        if !selection.isEmpty { selection.removeAll() }
    }

    /// 批量标记完成：逐条经 EventService（通知/同步各自处理），最后统一落盘一次
    private func bulkSetCompleted() {
        let targets = store.events.filter { selection.contains($0.id) }
        for event in targets {
            EventService.shared.setCompleted(event, flush: false)
        }
        EventService.shared.flushPendingSave()
        withAnimation(AppTheme.Motion.screen) {
            selection.removeAll()
            isSelecting = false
        }
    }

    /// 批量删除（已二次确认）：同样逐条经 EventService，最后统一落盘
    private func bulkDelete() {
        let targets = store.events.filter { selection.contains($0.id) }
        for event in targets {
            EventService.shared.removeEvent(event, flush: false)
        }
        EventService.shared.flushPendingSave()
        withAnimation(AppTheme.Motion.screen) {
            selection.removeAll()
            isSelecting = false
        }
    }

    // MARK: - 文案

    private func dayHeader(_ day: Date) -> String {
        let text = day.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted,
                                                  locale: Locale(identifier: "zh_Hans_CN")))
        return QingheCalendarContext.userCalendar.isDateInToday(day) ? "\(text)（今天）" : text
    }

    private var summaryText: String {
        String(format: NSLocalizedString("共 %d 条日程，当前显示 %d 条", comment: ""),
               store.events.count, filteredEvents.count)
    }

    private var emptyHint: String {
        showCompleted
            ? NSLocalizedString("换个关键词，或调整类型筛选。", comment: "")
            : NSLocalizedString("换个关键词，或打开「显示已完成」。", comment: "")
    }
}
#endif
