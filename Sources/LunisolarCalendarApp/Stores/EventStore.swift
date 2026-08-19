import Foundation

#if canImport(Observation)
import Observation
#endif

// MARK: - 事件存储

#if canImport(Observation)
@Observable
#endif
@MainActor
public final class EventStore {

    @MainActor public static let shared = EventStore()

    #if !canImport(Observation)
    // Fallback: Linux/非Apple平台下无需Observation
    #endif

    private(set) var events: [CalendarEvent] = []

    private let saveURL: URL

    public init() {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        var docs = paths.first
        if docs == nil || !FileManager.default.fileExists(atPath: docs!.path) {
            // Linux/沙箱环境下回退到 /tmp
            docs = URL(fileURLWithPath: NSTemporaryDirectory())
        }
        self.saveURL = docs!.appendingPathComponent("calendar_events.json")
        // 确保父目录存在（iOS 上 Documents 目录首次启动可能需要创建中间路径）
        try? FileManager.default.createDirectory(
            at: self.saveURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        load()
    }

    // MARK: - CRUD

    public func add(_ event: CalendarEvent) {
        events.append(event)
        sort()
        save()
    }

    public func update(_ event: CalendarEvent) {
        guard let idx = events.firstIndex(where: { $0.id == event.id }) else { return }
        var updated = event
        updated.updatedAt = Date()
        events[idx] = updated
        sort()
        save()
    }

    public func delete(_ event: CalendarEvent) {
        events.removeAll { $0.id == event.id }
        save()
    }

    public func toggleCompleted(_ event: CalendarEvent) {
        guard let idx = events.firstIndex(where: { $0.id == event.id }) else { return }
        events[idx].isCompleted.toggle()
        events[idx].updatedAt = Date()
        save()
    }

    /// 标记事件通知已触发（防止重复弹窗）
    public func markNotified(_ event: CalendarEvent) {
        guard let idx = events.firstIndex(where: { $0.id == event.id }) else { return }
        events[idx].isNotified = true
        events[idx].updatedAt = Date()
        save()
    }

    // MARK: - 查询

    public func events(on date: Date) -> [CalendarEvent] {
        events
            .filter { $0.occurs(on: date) }
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
                return lhs.priority > rhs.priority
            }
    }

    public func hasEvents(on date: Date) -> Bool {
        events.contains { $0.occurs(on: date) }
    }

    public func highestPriority(on date: Date) -> Priority? {
        let evs = events(on: date)
        return evs.max { $0.priority < $1.priority }?.priority
    }

    public func search(query: String) -> [CalendarEvent] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return events }
        return events.filter {
            $0.title.lowercased().contains(q) ||
            ($0.location?.lowercased().contains(q) ?? false) ||
            ($0.notes?.lowercased().contains(q) ?? false)
        }
    }

    // MARK: - 持久化

    private func sort() {
        events.sort { $0.startDate < $1.startDate }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: saveURL.path) else {
            insertSampleData()
            return
        }
        do {
            let data = try Data(contentsOf: saveURL)
            events = try JSONDecoder().decode([CalendarEvent].self, from: data)
            sort()
        } catch {
            print("加载事件失败: \(error)")
            insertSampleData()
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(events)
            try data.write(to: saveURL, options: .atomic)
        } catch {
            print("保存事件失败: \(error)")
        }
    }

    private func insertSampleData() {
        let today = Date()
        let cal = Calendar.current

        var compsTodayAllDay = cal.dateComponents([.year,.month,.day], from: today)
        compsTodayAllDay.hour = 0
        compsTodayAllDay.minute = 0
        let todayAllDayDate = cal.date(from: compsTodayAllDay) ?? today
        events.append(
            CalendarEvent(
                title: "阅读《平凡的世界》30分钟",
                type: .note,
                startDate: todayAllDayDate,
                isAllDay: true,
                notes: "今日必读，保持学习节奏",
                priority: .normal
            )
        )

        var comps1 = cal.dateComponents([.year,.month,.day], from: today)
        comps1.hour = 15; comps1.minute = 0
        let s1 = cal.date(from: comps1) ?? today
        var comps1e = comps1; comps1e.hour = 16; comps1e.minute = 30
        let e1 = cal.date(from: comps1e) ?? s1.addingTimeInterval(3600)
        events.append(
            CalendarEvent(
                title: "产品需求评审会",
                type: .schedule,
                startDate: s1,
                endDate: e1,
                location: "3号会议室",
                notes: "讨论Q4产品计划，提前准备方案",
                priority: .high
            )
        )

        var comps2 = cal.dateComponents([.year,.month,.day], from: today.addingDays(1))
        comps2.hour = 9; comps2.minute = 0
        let s2 = cal.date(from: comps2) ?? today.addingDays(1)
        events.append(
            CalendarEvent(
                title: "给妈妈打电话",
                type: .reminder,
                startDate: s2,
                notes: "问候身体情况",
                priority: .urgent
            )
        )

        var comps3 = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        comps3.weekday = 4
        comps3.hour = 20; comps3.minute = 0
        let s3 = cal.date(from: comps3) ?? today
        events.append(
            CalendarEvent(
                title: "瑜伽课",
                type: .schedule,
                startDate: s3,
                endDate: s3.addingTimeInterval(3600),
                location: "阳光健身工作室",
                repeatRule: .weekly,
                priority: .low
            )
        )

        sort()
        save()
    }
}
