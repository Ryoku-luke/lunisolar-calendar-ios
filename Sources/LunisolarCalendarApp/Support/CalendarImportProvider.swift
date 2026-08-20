#if canImport(EventKit)
import EventKit
import Foundation

// MARK: - 系统日历导入（EventKit.EKEvent → CalendarEvent）

/// 把系统日历事件导入本 App：
/// - 申请 `.event` 权限
/// - 默认拉取"今日往前 90 天 → 往后 365 天"的事件（用户可在调用方覆盖 dateRange）
/// - 重复事件 EKEvent 会被展开成具体实例（`events(matching:)` 已包含展开）
public struct CalendarImportProvider: SystemImportProviding {
    public let source: SystemImportSource = .systemCalendar

    private let store: EKEventStore
    private let dateRange: ClosedRange<Date>

    /// - Parameters:
    ///   - dateRange: 导入的日期区间；默认今日-90d...今日+365d
    public init(
        store: EKEventStore = EKEventStore(),
        dateRange: ClosedRange<Date>? = nil
    ) {
        self.store = store
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .day, value: -90, to: today) ?? today
        let end = cal.date(byAdding: .day, value: 365, to: today) ?? today
        self.dateRange = dateRange ?? (start...end)
    }

    public func requestAuthorization() async throws -> Bool {
        // iOS 17+ 用 fullAccess；旧版用 writeOnly/legacy
        let granted: Bool
        if #available(iOS 17.0, *) {
            granted = (try? await store.requestFullAccessToEvents()) ?? false
        } else {
            let status = EKEventStore.authorizationStatus(for: .event)
            switch status {
            case .authorized:
                granted = true
            case .notDetermined:
                granted = (try? await store.requestAccess(to: .event)) ?? false
            default:
                granted = false
            }
        }
        if !granted { throw SystemImportError.unauthorized(source: source) }
        return granted
    }

    public func fetchEvents() async throws -> [SystemImportEvent] {
        let ok = try await requestAuthorization()
        guard ok else { throw SystemImportError.unauthorized(source: source) }

        let predicate = store.predicateForEvents(withStart: dateRange.lowerBound,
                                                  end: dateRange.upperBound,
                                                  calendars: nil)
        let ekEvents = store.events(matching: predicate)
        return ekEvents.map(map(_:))
    }

    // MARK: - EKEvent → SystemImportEvent

    private func map(_ ek: EKEvent) -> SystemImportEvent {
        let rule: RepeatRule
        if let r = ek.recurrenceRule {
            switch r.frequency {
            case .daily:   rule = .daily
            case .weekly:   rule = .weekly
            case .monthly:  rule = .monthly
            case .yearly:   rule = .yearly
            default:        rule = .never
            }
        } else {
            rule = .never
        }
        return SystemImportEvent(
            sourceID: "ek:\(ek.eventIdentifier)",
            title: ek.title ?? "（无标题）",
            startDate: ek.startDate,
            endDate: ek.endDate,
            isAllDay: ek.isAllDay,
            location: ek.location?.isEmpty == false ? ek.location : nil,
            notes: ek.notes?.isEmpty == false ? ek.notes : nil,
            repeatRule: rule,
            eventType: .schedule,
            priority: .normal
        )
    }
}
#endif
