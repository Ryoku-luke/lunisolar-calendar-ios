import XCTest
@testable import LunisolarCalendarApp

// MARK: - 全量日程页派生管线（P3-5）
//
// 目的有两个：
// 1. **正确性**：单趟分桶必须与原实现（filter(isPast) + filter(!isPast)）等价；
// 2. **基线**：把「旧的多趟模式」与「新单趟」并排量出来，改前/改后有数字可比。

final class AllEventsDerivedTests: XCTestCase {

    private let cal = QingheCalendarContext.userCalendar
    private var todayStart: Date { cal.startOfDay(for: Date()) }

    /// 混合数据：一半已过去（无重复规则且早于今天）、一半未来
    private func makeEvents(_ count: Int) -> [CalendarEvent] {
        (0..<count).map { i in
            let offset = Double((i % 2 == 0 ? -1 : 1) * (i + 1)) * 86_400
            return CalendarEvent(title: "事件 \(i)", startDate: Date().addingTimeInterval(offset))
        }
    }

    private func isIncluded(_ event: CalendarEvent) -> Bool { true }

    // MARK: 正确性

    func testSinglePassPartitionMatchesNaiveImplementation() {
        let events = makeEvents(500)
        let derived = AllEventsDerived.compute(events: events, isIncluded: isIncluded, todayStart: todayStart)

        let naivePast = events.filter { AllEventsGrouping.isPast($0, todayStart: todayStart) }
        let naiveUpcoming = events.filter { !AllEventsGrouping.isPast($0, todayStart: todayStart) }

        XCTAssertEqual(derived.filtered.count, events.count)
        XCTAssertEqual(derived.past.map(\.id), naivePast.map(\.id))
        XCTAssertEqual(derived.upcoming.map(\.id), naiveUpcoming.map(\.id))
        XCTAssertEqual(derived.past.count + derived.upcoming.count, derived.filtered.count,
                       "两个桶必须恰好覆盖过滤后的集合")
    }

    /// `isIncluded` 为假的事件不得进入任何桶
    func testExcludedEventsNeverEnterEitherBucket() {
        let events = makeEvents(100)
        let derived = AllEventsDerived.compute(events: events,
                                               isIncluded: { _ in false },
                                               todayStart: todayStart)
        XCTAssertTrue(derived.filtered.isEmpty)
        XCTAssertTrue(derived.past.isEmpty)
        XCTAssertTrue(derived.upcoming.isEmpty)
        XCTAssertTrue(derived.upcomingGroups.isEmpty)
    }

    // MARK: 基线（旧多趟 vs 新单趟）

    private func oldMultiPass(_ events: [CalendarEvent]) {
        // 与视图原实现同构：两次链式 filter + isPast 判定两遍（重复日程还会各算一次 occurs）
        let filtered = events.filter(isIncluded).filter { !$0.isCompleted }
        let past = filtered.filter { AllEventsGrouping.isPast($0, todayStart: todayStart) }
        let upcoming = filtered.filter { !AllEventsGrouping.isPast($0, todayStart: todayStart) }
        _ = AllEventsGrouping.groups(from: upcoming, clampingTo: todayStart)
        _ = AllEventsGrouping.groups(from: past)
    }

    // 每次采样跑 5 遍：单遍虽已 30–60ms，但抖动实测 10–13%（超 measure 默认 10% 容差），
    // 会偶发判红——同一个坑上一条性能提交里已经踩过一次，这里直接按教训处理。
    func testBaselineOldMultiPass() {
        let events = makeEvents(10_000)
        measure {
            for _ in 0..<5 { oldMultiPass(events) }
        }
    }

    func testBaselineSinglePass() {
        let events = makeEvents(10_000)
        measure {
            for _ in 0..<5 {
                _ = AllEventsDerived.compute(events: events, isIncluded: isIncluded, todayStart: todayStart)
            }
        }
    }
}
