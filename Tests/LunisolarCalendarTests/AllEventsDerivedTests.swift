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
        let derived = AllEventsDerived.compute(events: events, isIncluded: isIncluded, todayStart: todayStart, showPast: true)

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
                                               todayStart: todayStart, showPast: true)
        XCTAssertTrue(derived.filtered.isEmpty)
        XCTAssertTrue(derived.past.isEmpty)
        XCTAssertTrue(derived.upcoming.isEmpty)
        XCTAssertTrue(derived.upcomingGroups.isEmpty)
    }

    /// 分组语义：`upcomingGroups` 必须与「先取未过去、再分组」等价，
    /// `pastGroups` 必须与「先取已过去、再分组」等价——下轮视图重接只依赖这一个入口，
    /// 所以这里把它与独立调用 `AllEventsGrouping` 的结果逐组对齐。
    /// （组头日期、每组事件 id 序列都要一致；ClampingTo 的差别也是语义的一部分。）
    func testGroupsMatchDirectGroupingCalls() {
        let events = makeEvents(300)
        let derived = AllEventsDerived.compute(events: events, isIncluded: isIncluded, todayStart: todayStart, showPast: true)

        let expectedUpcoming = AllEventsGrouping.groups(from: derived.upcoming, clampingTo: todayStart)
        let expectedPast = AllEventsGrouping.groups(from: derived.past)

        XCTAssertEqual(derived.upcomingGroups.map(\.day), expectedUpcoming.map(\.day))
        XCTAssertEqual(derived.upcomingGroups.map { $0.events.map(\.id) },
                       expectedUpcoming.map { $0.events.map(\.id) })
        XCTAssertEqual(derived.pastGroups.map(\.day), expectedPast.map(\.day))
        XCTAssertEqual(derived.pastGroups.map { $0.events.map(\.id) },
                       expectedPast.map { $0.events.map(\.id) })
    }

    /// 空输入不得产生任何组（视图用 `upcomingGroups.isEmpty` 判空态，这条守住它）
    func testEmptyInputProducesNoGroups() {
        let derived = AllEventsDerived.compute(events: [], isIncluded: isIncluded, todayStart: todayStart, showPast: true)
        XCTAssertTrue(derived.filtered.isEmpty)
        XCTAssertTrue(derived.upcomingGroups.isEmpty)
        XCTAssertTrue(derived.pastGroups.isEmpty)
    }

    /// 视图的 `visibleEvents` 语义现在由这个入口承载：`showPast == false` 时可见行只有未过去，
    /// `true` 时把已过去拼在后面（与原实现 `upcoming + (showPast ? past : [])` 同义）。
    /// 重接视图后这条就是"可见行没变"的护栏。
    func testVisibleRespectsShowPast() {
        let events = makeEvents(200)
        let withoutPast = AllEventsDerived.compute(events: events, isIncluded: isIncluded,
                                                   todayStart: todayStart, showPast: false)
        let withPast = AllEventsDerived.compute(events: events, isIncluded: isIncluded,
                                                todayStart: todayStart, showPast: true)

        XCTAssertEqual(withoutPast.visible.map(\.id), withoutPast.upcoming.map(\.id),
                       "折叠已过去时，可见行 == 未过去")
        XCTAssertEqual(withPast.visible.map(\.id), withPast.upcoming.map(\.id) + withPast.past.map(\.id),
                       "展开时可见行 == 未过去 + 已过去（顺序也要一致）")
        XCTAssertGreaterThan(withPast.visible.count, withoutPast.visible.count)
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
                _ = AllEventsDerived.compute(events: events, isIncluded: isIncluded, todayStart: todayStart, showPast: true)
            }
        }
    }
}
