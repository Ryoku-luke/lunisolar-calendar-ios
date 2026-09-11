#if canImport(EventKit)
import EventKit
import Foundation

// MARK: - 系统日历导入（EventKit.EKEvent → CalendarEvent）

/// 把系统日历事件导入本 App：
/// - 申请 `.event` 权限
/// - 默认拉取"今日往前 90 天 → 往后 365 天"的事件（用户可在调用方覆盖 dateRange）
/// - 重复事件 EKEvent 会被展开成具体实例（`events(matching:)` 已包含展开）
public struct CalendarImportProvider: SystemImportProviding, @unchecked Sendable {
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
        // iOS 17+ 用 requestFullAccessToEvents；iOS 16 及以下用 legacy requestAccess(to:)。
        // A1-1 修复：分别在各自的 availability 范围内调用，避免 iOS 17+ SDK 的
        // "'requestAccess(to:)' was deprecated in iOS 17.0" 警告。
        let granted: Bool
        if #available(iOS 17.0, *) {
            granted = (try? await store.requestFullAccessToEvents()) ?? false
        } else {
            let status = EKEventStore.authorizationStatus(for: .event)
            switch status {
            case .authorized, .fullAccess, .writeOnly:
                granted = true
            case .notDetermined:
                granted = (try? await withCheckedThrowingContinuation { cont in
                    // iOS < 17 仍然安全合法；swiftlint:disable:next legacy_hashing
                    store.requestAccess(to: .event) { g, e in
                        if let e = e { cont.resume(throwing: e) }
                        else { cont.resume(returning: g) }
                    }
                }) ?? false
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
        // EKEvent.recurrenceRules 是复数数组 [EKRecurrenceRule]?；取第一条匹配
        let rule: RepeatRule
        if let firstRR = ek.recurrenceRules?.first {
            switch firstRR.frequency {
            case .daily:   rule = .daily
            case .weekly:   rule = .weekly
            case .monthly:  rule = .monthly
            case .yearly:   rule = .yearly
            @unknown default: rule = .never
            }
        } else {
            rule = .never
        }
        return SystemImportEvent(
            sourceID: "ek:\(ek.eventIdentifier ?? ek.calendarItemIdentifier)",
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
