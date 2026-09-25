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
    /// 是否已被滚动唤起：进入多选时操作条先隐藏，滚动或勾选任一行后淡入
    /// （避免一进页面就多出一条悬浮条压住列表）
    @State private var revealedByScroll = false

    /// 操作条可见性：多选中，且（已滚动过 或 已有选中项）——保证不会有"选完了却点不到删除"的死角
    private var showsSelectionBar: Bool {
        isSelecting && (revealedByScroll || !selection.isEmpty)
    }

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
        .navigationTitle(NSLocalizedString("全部日程", comment: ""))
        .inlineTitleBar()
        // ⚠️ 这里 `.searchable` 曾不渲染任何搜索入口（iOS 26 上默认的「自动」抽屉不出现搜索框，
        // 下拉也不出现；调换修饰符顺序同样无效）。修复：显式要求常驻导航栏抽屉。
        // 该 placement 是 iOS 专有（macOS 无 navigationBarDrawer），故按平台分支。
        #if canImport(UIKit)
        .searchable(text: $query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text(NSLocalizedString("搜索标题 / 地点 / 备注", comment: "")))
        #else
        .searchable(text: $query, prompt: Text(NSLocalizedString("搜索标题 / 地点 / 备注", comment: "")))
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .platformTopBarTrailing) {
                if isSelecting {
                    // 工具栏保留全选出口：操作条在"未滚动且未选中"时是隐藏的，
                    // 若全选只放在操作条里会出现"点不到"的死角
                    Button(isAllSelected
                           ? NSLocalizedString("取消全选", comment: "")
                           : NSLocalizedString("全选", comment: "")) {
                        withAnimation(AppTheme.Motion.pressInOut) { toggleSelectAll() }
                    }
                    .disabled(visibleEvents.isEmpty)
                }
                Button(isSelecting
                       ? NSLocalizedString("完成", comment: "")
                       : NSLocalizedString("选择", comment: "")) {
                    withAnimation(AppTheme.Motion.screen) {
                        isSelecting.toggle()
                        if !isSelecting { selection.removeAll() }
                        revealedByScroll = false   // 下次进入多选仍从"隐藏 → 滚动/勾选淡入"开始
                    }
                }
                // 用 visibleEvents 而不是 filteredEvents：若筛选结果全是"已过去"且当前处于
                // 折叠状态，进多选后一个可勾选的行都没有（「全选」也灰着），只能再点「完成」退出。
                .disabled(visibleEvents.isEmpty)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if showsSelectionBar {
                selectionBar
                    // 淡入 + 自下而上滑入：替代原来的"直接出现"
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(AppTheme.Motion.screen, value: showsSelectionBar)
        // 滚动即唤起操作条（simultaneousGesture：不影响点击、左滑删除与原生滚动）
        .simultaneousGesture(
            DragGesture(minimumDistance: 8).onChanged { _ in
                if isSelecting, !revealedByScroll { revealedByScroll = true }
            }
        )
        .overlay {
            if filteredEvents.isEmpty {
                // 统一空态（四要素）。第四项是「清除筛选」：搜索/筛选把列表清空时，
                // 只给一句说明，用户得自己逐项还原条件。
                QingheEmptyView(
                    icon: "calendar.badge.exclamationmark",
                    title: NSLocalizedString("没有符合条件的日程", comment: ""),
                    message: emptyHint,
                    actionTitle: hasActiveFilter ? NSLocalizedString("清除筛选", comment: "") : nil
                ) {
                    clearFilters()
                }
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
        // 「显示已过去」同样是可见性开关：折叠后那些行不再可见，而批量删除是按
        // **选中集合**执行的 → 不退出多选就会把当前看不见的行一起删掉。
        // 这也是唯一漏掉 exitSelection() 的开关（其它三个筛选都在上面）。
        .onChange(of: showPast) { _, _ in exitSelection() }
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
        HStack(spacing: AppTheme.Spacing.md) {
            Button {
                withAnimation(AppTheme.Motion.pressInOut) { toggleSelectAll() }
            } label: {
                Label(isAllSelected
                      ? NSLocalizedString("取消全选", comment: "")
                      : NSLocalizedString("全选", comment: ""),
                      systemImage: isAllSelected ? "checklist.checked" : "checklist")
                    .font(AppTheme.Font.subheadline.weight(.semibold))
                    .foregroundStyle(visibleEvents.isEmpty ? Color.tertiaryLabel : Color.label)
            }
            .buttonStyle(.plain)
            .pressableFeedback()
            .disabled(visibleEvents.isEmpty)

            Rectangle()
                .fill(Color.separator)
                .frame(width: AppTheme.Stroke.hair, height: 18)

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
        .background(AdaptiveMaterialFill(material: .ultraThinMaterial, shape: Capsule()))
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

    /// 已过去：一次性、开始日早于今天，且今天已不再发生（规则见 AllEventsGrouping）
    private func isPast(_ event: CalendarEvent) -> Bool {
        AllEventsGrouping.isPast(event, todayStart: todayStart)
    }

    private var pastEvents: [CalendarEvent] { filteredEvents.filter(isPast) }
    private var pastCount: Int { pastEvents.count }
    private var upcomingGroups: [(day: Date, events: [CalendarEvent])] {
        // 组头从「今天」起算：跨天与重复日程的 startDate 可能早于今天（重复日程的锚点
        // 甚至在半年前），直接拿它当组头会显示历史日期，与「今天起优先」的承诺矛盾
        AllEventsGrouping.groups(from: filteredEvents.filter { !isPast($0) }, clampingTo: todayStart)
    }
    private var pastGroups: [(day: Date, events: [CalendarEvent])] {
        AllEventsGrouping.groups(from: pastEvents)
    }

    // MARK: - 多选操作

    /// 当前可见行（已过去折叠时不计入）：全选只作用于此集合，
    /// 与"筛选变化即退出多选"一致——不让操作触及看不见的行
    private var visibleEvents: [CalendarEvent] {
        filteredEvents.filter { !isPast($0) } + (showPast ? pastEvents : [])
    }

    private var isAllSelected: Bool {
        !visibleEvents.isEmpty && visibleEvents.allSatisfy { selection.contains($0.id) }
    }

    private func toggleSelectAll() {
        if isAllSelected {
            selection.removeAll()
        } else {
            selection = Set(visibleEvents.map(\.id))
        }
    }

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
            // 必须用幂等的 markCompleted：选中集合里可能混有已完成项，
            // 走 setCompleted（切换语义）会把它们改回未完成，与按钮文案相反
            EventService.shared.markCompleted(event, flush: false)
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
        return QingheCalendarContext.userCalendar.isDateInToday(day)
            ? String(format: NSLocalizedString("%@（今天）", comment: ""), text)
            : text
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

    /// 是否有任何生效中的搜索/筛选条件——决定空态要不要给「清除筛选」按钮
    private var hasActiveFilter: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
            || typeFilter != .all
            || showCompleted
            || showPast
    }

    private func clearFilters() {
        query = ""
        typeFilter = .all
        showCompleted = false
        showPast = false
    }
}
#endif
