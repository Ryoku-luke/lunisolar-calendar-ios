import Foundation

/// `AllEventsView` 的派生结果：**一次遍历**分出「已过去 / 未过去」，两部分各自分组。
///
/// 为什么抽出来（执行计划 P3-5）：视图里这些是**计算属性**——`filteredEvents` 被
/// `pastEvents` / `upcomingGroups` / `visibleEvents` / 无障碍文案各访问一次，每次都重跑
/// 链式 filter 与 `filter(isPast)`；读码数出来每次 body 要扫 **6–10 遍**全量事件，
/// 且随事件数线性增长（全量日程页对重度用户最明显）。
///
/// 抽成纯函数后：**一遍过滤 + 一遍分桶**（分组在桶内做），并且可单独测、单独量。
/// 注意：本类型只解决"每条事件被扫几遍"；要真正省掉重复求值，调用方需**每次 body 只算一次**
/// 并把结果往下传（视图重接是下一步，见计划）。
struct AllEventsDerived {
    let filtered: [CalendarEvent]
    let past: [CalendarEvent]
    let upcoming: [CalendarEvent]
    let upcomingGroups: [(day: Date, events: [CalendarEvent])]
    /// 当前可见行（已过去折叠时不计入）——与原视图 `visibleEvents` 同义，
    /// 由 `showPast` 决定是否把已过去拼在后面
    let visible: [CalendarEvent]
    let pastGroups: [(day: Date, events: [CalendarEvent])]

    static let empty = AllEventsDerived(filtered: [], past: [], upcoming: [],
                                        upcomingGroups: [], visible: [], pastGroups: [])

    /// - Parameters:
    ///   - events: 已由 `store.search(query:)` 过滤过的候选集
    ///   - isIncluded: 类型筛选 + 「是否显示已完成」合并成的单一谓词
    ///   - todayStart: 今天 0 点（已过去判定与组头都用它）
    static func compute(events: [CalendarEvent],
                        isIncluded: (CalendarEvent) -> Bool,
                        todayStart: Date,
                        showPast: Bool,
                        calendar: Calendar = QingheCalendarContext.userCalendar) -> AllEventsDerived {
        var filtered: [CalendarEvent] = []
        var past: [CalendarEvent] = []
        var upcoming: [CalendarEvent] = []
        filtered.reserveCapacity(events.count)

        for event in events where isIncluded(event) {
            filtered.append(event)
            // 一次判定，两个桶里各放一份——原实现是 filter(isPast) + filter { !isPast }（判定两遍）
            if AllEventsGrouping.isPast(event, todayStart: todayStart, calendar: calendar) {
                past.append(event)
            } else {
                upcoming.append(event)
            }
        }

        return AllEventsDerived(
            filtered: filtered,
            past: past,
            upcoming: upcoming,
            upcomingGroups: AllEventsGrouping.groups(from: upcoming, clampingTo: todayStart),
            visible: showPast ? upcoming + past : upcoming,
            pastGroups: AllEventsGrouping.groups(from: past)
        )
    }
}
