import XCTest
@testable import LunisolarCalendarApp

// MARK: - 时间胶囊同步决策（纯函数镜像测试，Linux 可跑）

/// 文档 #24：EventService → Coordinator → Manager → ActivityKit。
/// Manager 依赖 ActivityKit（真机可用），决策逻辑抽为纯函数在此覆盖。
final class QingheLiveActivityLifecycleTests: XCTestCase {

    private func display(_ id: String, _ title: String = "提醒", _ icon: String = "bell.fill",
                         phase: QingheActivityPhase = .upcoming,
                         start: Date = Date(timeIntervalSince1970: 1_800_000_000),
                         end: Date? = nil,
                         important: Bool = false) -> QingheTimeCapsuleDisplay {
        QingheTimeCapsuleDisplay(
            eventID: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(id)")!,
            type: .reminder,
            phase: phase,
            title: title,
            icon: icon,
            startDate: start,
            endDate: end,
            countdownTarget: nil,
            isImportant: important
        )
    }

    /// 无目标、岛上无活动 → 什么都不做
    func testNoTargetNoCurrentIsNone() {
        XCTAssertEqual(QingheLiveActivityLifecycle.decision(current: nil, target: nil), .none)
    }

    /// 无目标、岛上有活动 → 结束（事件已删/过期自动下岛）
    func testNoTargetWithCurrentEnds() {
        XCTAssertEqual(QingheLiveActivityLifecycle.decision(current: display("1"), target: nil), .end)
    }

    /// 有目标、岛上无活动 → 开始
    func testTargetWithNoCurrentStarts() {
        XCTAssertEqual(QingheLiveActivityLifecycle.decision(current: nil, target: display("1")), .start)
    }

    /// 同事件内容一致 → 幂等不动（避免频繁重建闪烁）
    func testSameContentIsNone() {
        let d = display("1", "提醒A")
        XCTAssertEqual(QingheLiveActivityLifecycle.decision(current: d, target: d), .none)
    }

    /// 同事件、标题变化 → 更新
    func testSameEventTitleChangeUpdates() {
        XCTAssertEqual(
            QingheLiveActivityLifecycle.decision(current: display("1", "旧标题"), target: display("1", "新标题")),
            .update
        )
    }

    /// 同事件、结束时间变化 → 更新
    func testSameEventDateChangeUpdates() {
        let old = display("1", end: Date(timeIntervalSince1970: 1_800_000_000))
        let new = display("1", end: Date(timeIntervalSince1970: 1_900_000_000))
        XCTAssertEqual(QingheLiveActivityLifecycle.decision(current: old, target: new), .update)
    }

    /// 同事件、重要度变化 → 更新
    func testSameEventImportanceChangeUpdates() {
        XCTAssertEqual(
            QingheLiveActivityLifecycle.decision(current: display("1", important: false),
                                                 target: display("1", important: true)),
            .update
        )
    }

    /// 不同事件 → 结束旧活动（调用方随后 start 新事件）
    func testDifferentEventEnds() {
        XCTAssertEqual(
            QingheLiveActivityLifecycle.decision(current: display("1"), target: display("2")),
            .end
        )
    }

    /// 阶段变化（upcoming → live）→ 更新
    func testPhaseChangeUpdates() {
        XCTAssertEqual(
            QingheLiveActivityLifecycle.decision(current: display("1", phase: .upcoming),
                                                 target: display("1", phase: .live)),
            .update
        )
    }
}
