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

    // MARK: 全天事件的隐式结束（回归：过去几天的全天高优先级日程曾长期霸占灵动岛）

    private func allDayCandidate(_ id: String,
                                 priority: QingheActivityPriority,
                                 startOffset: TimeInterval) -> QingheTimeCapsuleCandidate {
        QingheTimeCapsuleCandidate(
            eventID: UUID(uuidString: id)!,
            type: .event,
            priority: priority,
            startDate: now.addingTimeInterval(startOffset),
            endDate: nil,          // 全天事件没有具体结束钟点
            isAllDay: true
        )
    }

    /// 全天事件在「当天结束」之后即失效。
    /// 此前 endDate == nil 让 isLive 恒为真 → 过期全天事件永远"进行中"。
    func testAllDayEventExpiresAfterItsDay() {
        let today = allDayCandidate("70000000-0000-0000-0000-000000000001",
                                    priority: .urgent, startOffset: 0)
        XCTAssertNotNil(QingheActivityCoordinator.pickForIsland(from: [today], now: now),
                        "当天应入选")
        XCTAssertNil(QingheActivityCoordinator.pickForIsland(from: [today],
                                                            now: now.addingTimeInterval(25 * 3600)),
                     "次日必须失效，不得继续霸占灵动岛")
    }

    /// 回归：三天前的全天紧急日程不得盖过今天 30 分钟后的普通提醒
    func testPastAllDayUrgentDoesNotBeatUpcomingReminder() {
        let pastAllDay = allDayCandidate("70000000-0000-0000-0000-000000000002",
                                         priority: .urgent, startOffset: -3 * 24 * 3600)
        let upcoming = candidate("70000000-0000-0000-0000-000000000003",
                                 priority: .normal, startOffset: 1800, endOffset: 1800)
        XCTAssertEqual(
            QingheActivityCoordinator.pickForIsland(from: [pastAllDay, upcoming], now: now),
            upcoming
        )
    }

    /// 入选的全天候选必须带上"有效结束时刻"，否则岛上右侧剩余时间算不出来（只剩图标）
    func testSelectedAllDayCandidateCarriesResolvedEnd() throws {
        let today = allDayCandidate("70000000-0000-0000-0000-000000000004",
                                    priority: .important, startOffset: -3600)
        let picked = try XCTUnwrap(QingheActivityCoordinator.pickForIsland(from: [today], now: now))
        let end = try XCTUnwrap(picked.endDate, "入选后必须补上有效结束时刻")
        XCTAssertGreaterThan(end, now, "结束时刻应还在未来（当天 24:00）")
        XCTAssertLessThan(end.timeIntervalSince(now), 24 * 3600)
    }

    /// 非全天且没有结束时刻的候选保持原语义（effectiveEnd 为 nil = 无结束概念）
    func testNonAllDayWithoutEndKeepsNoEnd() {
        let noEnd = candidate("70000000-0000-0000-0000-000000000005",
                              priority: .normal, startOffset: -600, endOffset: nil)
        XCTAssertNil(QingheActivityCoordinator.effectiveEnd(of: noEnd))
        XCTAssertTrue(QingheActivityCoordinator.isLive(noEnd, now: now))
    }
}
