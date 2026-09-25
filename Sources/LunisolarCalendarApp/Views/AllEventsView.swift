#if canImport(SwiftUI)
import SwiftUI
import LunarCore

// MARK: - 全部日程（统一管理页）
//
// 入口：日历工具栏菜单（iPhone）/ iPad 侧栏「全部日程」。
// 能力：关键词搜索（标题 / 地点 / 备注）、类型筛选、显示已完成开关、
//       按日期分组、点按编辑、滑动删除、长按菜单（完成 / 删除）。
// 读走 EventStore 的只读查询（search / events），写一律经 EventService。

struct AllEventsView: View {
    @Environment(EventStore.self) private var store

    @State private var query = ""
    @State private var typeFilter: TypeFilter = .all
    @State private var showCompleted = false
    @State private var editing: CalendarEvent?

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

    private var filteredEvents: [CalendarEvent] {
        store.search(query: query)
            .filter { typeFilter.matches($0.type) }
            .filter { showCompleted || !$0.isCompleted }
    }

    /// 按天分组（EventStore 内部按 startDate 升序，分组顺序天然有序）
    private var groupedEvents: [(day: Date, events: [CalendarEvent])] {
        let cal = QingheCalendarContext.userCalendar
        var result: [(day: Date, events: [CalendarEvent])] = []
        for event in filteredEvents {
            let day = cal.startOfDay(for: event.startDate)
            if let last = result.last, last.day == day {
                result[result.count - 1].events.append(event)
            } else {
                result.append((day, [event]))
            }
        }
        return result
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

            ForEach(groupedEvents, id: \.day) { group in
                Section {
                    ForEach(group.events) { event in
                        row(event)
                    }
                } header: {
                    Text(dayHeader(group.day))
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
    }

    @ViewBuilder
    private func row(_ event: CalendarEvent) -> some View {
        EventRow(event: event)
            .contentShape(Rectangle())
            // 行内完成圆圈是独立按钮（.plain），点其余区域进编辑
            .onTapGesture { editing = event }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    EventService.shared.removeEvent(event, flush: true)
                } label: {
                    Label(NSLocalizedString("删除", comment: ""), systemImage: "trash")
                }
            }
            .eventQuickActions(event)
    }

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
