import XCTest
@testable import LunisolarCalendarApp

// MARK: - 时间胶囊协调器 Golden Tests（文档 #25）

final class QingheActivityCoordinatorTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)  // 2027-01-09 附近

    private func candidate(
        _ id: String,
        type: QingheActivityType = .reminder,
        priority: QingheActivityPriority,
        startOffset: TimeInterval,
        endOffset: TimeInterval? = nil
    ) -> QingheTimeCapsuleCandidate {
        let start = now.addingTimeInterval(startOffset)
        return QingheTimeCapsuleCandidate(
            eventID: UUID(uuidString: id)!,
            type: type,
            priority: priority,
            startDate: start,
            endDate: endOffset.map { start.addingTimeInterval($0) },
            isAllDay: false
        )
    }

    /// 进行中的紧急提醒优先于未来的重要事项
    func testLiveUrgentBeatsUpcomingImportant() {
        let liveUrgent = candidate("10000000-0000-0000-0000-000000000001",
                                   priority: .urgent, startOffset: -600, endOffset: 3600)
        let upcomingImportant = candidate("10000000-0000-0000-0000-000000000002",
                                          priority: .important, startOffset: 3600, endOffset: 1800)
        XCTAssertEqual(QingheActivityCoordinator.pickForIsland(from: [upcomingImportant, liveUrgent], now: now),
                       liveUrgent)
    }

    /// 24h 内开始的重要事项被选中
    func testImportantWithinWindowSelected() {
        let important = candidate("20000000-0000-0000-0000-000000000001",
                                  priority: .important, startOffset: 60 * 60 * 12, endOffset: 3600)
        XCTAssertEqual(QingheActivityCoordinator.pickForIsland(from: [important], now: now), important)
    }

    /// 普通优先级 24h 内的提醒也能进入（无更高优先级时）
    func testNormalWithinWindowSelectedWhenAlone() {
        let normal = candidate("30000000-0000-0000-0000-000000000001",
                               priority: .normal, startOffset: 60 * 60 * 6, endOffset: 1800)
        XCTAssertEqual(QingheActivityCoordinator.pickForIsland(from: [normal], now: now), normal)
    }

    /// 超出 24h 窗口的未来事件不进入时间胶囊
    func testBeyondWindowIgnored() {
        let far = candidate("40000000-0000-0000-0000-000000000001",
                            priority: .urgent, startOffset: 60 * 60 * 25, endOffset: 3600)
        XCTAssertNil(QingheActivityCoordinator.pickForIsland(from: [far], now: now))
    }

    /// 已结束的事件不进入
    func testEndedEventIgnored() {
        let ended = candidate("50000000-0000-0000-0000-000000000001",
                              priority: .urgent, startOffset: -7200, endOffset: -3600)
        XCTAssertNil(QingheActivityCoordinator.pickForIsland(from: [ended], now: now))
    }

    /// 同优先级：进行中的优先；都进行中时先开始的优先
    func testSamePriorityPreferLiveThenEarlier() {
        let live = candidate("60000000-0000-0000-0000-000000000001",
                             priority: .important, startOffset: -600, endOffset: 1800)
        let upcoming = candidate("60000000-0000-0000-0000-000000000002",
                                 priority: .important, startOffset: 600, endOffset: 1800)
        XCTAssertEqual(QingheActivityCoordinator.pickForIsland(from: [upcoming, live], now: now), live)

        let liveEarlier = candidate("60000000-0000-0000-0000-000000000003",
                                    priority: .important, startOffset: -1800, endOffset: 1800)
        let liveLater = candidate("60000000-0000-0000-0000-000000000004",
                                  priority: .important, startOffset: -600, endOffset: 1800)
        XCTAssertEqual(QingheActivityCoordinator.pickForIsland(from: [liveLater, liveEarlier], now: now),
                       liveEarlier)
    }

    /// 空候选集 → nil
    func testEmptyCandidatesNil() {
        XCTAssertNil(QingheActivityCoordinator.pickForIsland(from: [], now: now))
    }
    func testSolarTermRemainsEligibleForTwoHoursAfterTransition() {
        let term = SolarTermProvider.termDate(year: 2026, index: 17)! // 秋分
        let after = term.addingTimeInterval(90 * 60)
        let candidate = QingheActivityCoordinator.nextSolarTermCandidate(now: after)
        XCTAssertNotNil(candidate)
        XCTAssertEqual(candidate?.type, .solarTerm)
        XCTAssertEqual(candidate?.startDate, term)
        XCTAssertEqual(candidate?.endDate, term.addingTimeInterval(2 * 3600))
    }

    func testSolarTermCandidateIDIsStable() {
        let term = SolarTermProvider.termDate(year: 2026, index: 17)!
        let first = QingheActivityCoordinator.nextSolarTermCandidate(now: term.addingTimeInterval(-30 * 60))
        let second = QingheActivityCoordinator.nextSolarTermCandidate(now: term.addingTimeInterval(-15 * 60))
        XCTAssertEqual(first?.eventID, second?.eventID)
    }

}
