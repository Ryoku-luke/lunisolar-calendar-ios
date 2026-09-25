import XCTest
@testable import LunisolarCalendarApp

// MARK: - 全天事件跨时区（docs/ALLDAY_TIMEZONE_PLAN.md 步骤 3a）

/// 覆盖的不变量：
/// - I1 全天事件的真相是年月日，不是瞬时：同一份 payload 在任何时区解出来都是**同一天**；
/// - I2 每台设备按自己的时区把年月日物化成当地 00:00；
/// - I3 非全天事件完全不受影响（瞬时逐位不变）；
/// - 旧数据（payload 里没有年月日分量）行为与改动前完全一致。
final class AllDayTimeZoneTests: XCTestCase {

    private let shanghai = { () -> Calendar in
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }()

    private let newYork = { () -> Calendar in
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    /// 2026-09-06 00:00+08:00，也就是 UTC 的 2026-09-05T16:00Z
    private static let payloadStart = "2026-09-05T16:00:00Z"
    /// 旧实现下全天事件的兜底结束（+1 小时），故意与「当日 23:59:59」不同
    private static let payloadEnd = "2026-09-05T17:00:00Z"

    // MARK: - 造 payload

    /// 构造一份「由 UTC+8 设备写出」的 payload，并可按需增删年月日分量
    private func payload(
        startInstant: String = AllDayTimeZoneTests.payloadStart,
        endInstant: String = AllDayTimeZoneTests.payloadEnd,
        startDay: (year: Int, month: Int, day: Int)? = (2026, 9, 6),
        endDay: (year: Int, month: Int, day: Int)? = (2026, 9, 6),
        isAllDay: Bool = true
    ) throws -> Data {
        let start = ISO8601DateFormatter().date(from: startInstant)!
        let seed = CalendarEvent(title: "全天", startDate: start,
                                endDate: start.addingTimeInterval(3_600), isAllDay: isAllDay)
        var obj = try JSONSerialization.jsonObject(
            with: try SyncCoders.encoder().encode(seed)
        ) as! [String: Any]
        obj["startDate"] = startInstant
        obj["endDate"] = endInstant

        func write(_ key: String, _ value: (year: Int, month: Int, day: Int)?) {
            if let value {
                obj[key] = ["year": value.year, "month": value.month, "day": value.day]
            } else {
                obj.removeValue(forKey: key)
            }
        }
        write("startDay", startDay)
        write("endDay", endDay)
        return try JSONSerialization.data(withJSONObject: obj)
    }

    // MARK: - I2：同一份年月日在不同时区物化成「各自的当天」

    func testMaterializeAllDayKeepsSameCalendarDayAcrossTimeZones() {
        let key = CalendarDayKey(year: 2026, month: 9, day: 6)
        let inShanghai = CalendarEvent.materializeAllDay(start: key, end: key, in: shanghai)
        let inNewYork = CalendarEvent.materializeAllDay(start: key, end: key, in: newYork)

        XCTAssertEqual(CalendarDayKey(inShanghai.start, in: shanghai), key)
        XCTAssertEqual(CalendarDayKey(inNewYork.start, in: newYork), key)
        // 两台设备看到的是「同一天」，但那是两个不同的绝对瞬时：
        // 上海的 9/6 00:00 = 9/5 16:00Z，纽约的 9/6 00:00(−04 夏令时) = 9/6 04:00Z，
        // 所以上海的绝对瞬时比纽约**早** 12 小时。
        XCTAssertNotEqual(inShanghai.start, inNewYork.start)
        XCTAssertEqual(inNewYork.start.timeIntervalSince(inShanghai.start), 12 * 3600,
                       "上海(+08) 比 纽约(−04 夏令时) 早 12 小时")
    }

    /// 全天事件的结束必须落在同一天的 23:59:59（不是次日），否则 occurs 会把单日事件算成两天
    func testMaterializeAllDayEndStaysWithinSameDay() {
        let key = CalendarDayKey(year: 2026, month: 9, day: 6)
        let m = CalendarEvent.materializeAllDay(start: key, end: key, in: newYork)
        XCTAssertEqual(CalendarDayKey(m.end, in: newYork), key)
        XCTAssertEqual(m.end.timeIntervalSince(m.start), 86_399)
    }

    /// 多日全天事件：结束日按分量取，不塌缩成单日
    func testMaterializeAllDayMultiDayRange() {
        let start = CalendarDayKey(year: 2026, month: 9, day: 6)
        let end = CalendarDayKey(year: 2026, month: 9, day: 8)
        let m = CalendarEvent.materializeAllDay(start: start, end: end, in: shanghai)
        XCTAssertEqual(CalendarDayKey(m.start, in: shanghai), start)
        XCTAssertEqual(CalendarDayKey(m.end, in: shanghai), end)
    }

    /// 分量本身损坏（结束日早于开始日）→ 退回单日，且保持 endDate > startDate
    func testMaterializeAllDayRepairsInvertedRange() {
        let start = CalendarDayKey(year: 2026, month: 9, day: 6)
        let end = CalendarDayKey(year: 2026, month: 9, day: 1)
        let m = CalendarEvent.materializeAllDay(start: start, end: end, in: shanghai)
        XCTAssertGreaterThan(m.end, m.start)
        XCTAssertEqual(CalendarDayKey(m.start, in: shanghai), start)
    }

    // MARK: - I1：解码后落在同一天（这是本次修复的核心断言）

    /// 分量指的是哪天，解出来就是哪天——不论本机处于哪个时区。
    func testAllDayPayloadDecodesToIntendedDay() throws {
        let event = try SyncCoders.decoder().decode(CalendarEvent.self, from: try payload())
        let local = Calendar(identifier: .gregorian)
        XCTAssertTrue(event.isAllDay)
        XCTAssertEqual(CalendarDayKey(event.startDate, in: local),
                       CalendarDayKey(year: 2026, month: 9, day: 6),
                       "不论本机在哪个时区，都应解出 9 月 6 日")
        XCTAssertEqual(CalendarDayKey(event.endDate, in: local),
                       CalendarDayKey(year: 2026, month: 9, day: 6))
    }

    /// 真正的回归断言：分量指 9/20，而瞬时是 9/5 16:00Z。
    /// 任何时区都不可能把 9/5 16:00Z 理解成 9/20（跨时区最多 ±14h，只可能是 9/5 或 9/6），
    /// 所以这条**在旧代码上必然失败，且与跑测试的机器处于哪个时区无关**。
    func testPayloadWithWrongLocalDayIsCorrected() throws {
        let data = try payload(startDay: (2026, 9, 20), endDay: (2026, 9, 20))
        let event = try SyncCoders.decoder().decode(CalendarEvent.self, from: data)
        let local = Calendar(identifier: .gregorian)
        XCTAssertEqual(CalendarDayKey(event.startDate, in: local),
                       CalendarDayKey(year: 2026, month: 9, day: 20))
        XCTAssertEqual(CalendarDayKey(event.endDate, in: local),
                       CalendarDayKey(year: 2026, month: 9, day: 20))
        XCTAssertEqual(event.endDate.timeIntervalSince(event.startDate), 86_399)
    }

    /// 收窄爆炸半径的保证：本机日**已经对**时，瞬时原样保留，一个字节都不动。
    /// 现实意义：编辑器允许把日程切成「全天」而保留原时刻（如 14:00），
    /// 而 startDate 决定提醒触发时刻——顺手归一成 00:00 会悄悄挪动用户的提醒时间。
    func testPayloadWithMatchingLocalDayKeepsInstantsUntouched() throws {
        let local = Calendar(identifier: .gregorian)
        let strayTime = CalendarEvent.materializeAllDay(
            start: CalendarDayKey(year: 2026, month: 9, day: 6),
            end: CalendarDayKey(year: 2026, month: 9, day: 6),
            in: local
        ).start.addingTimeInterval(14 * 3_600)   // 当地 9/6 14:00
        let iso = ISO8601DateFormatter().string(from: strayTime)

        let data = try payload(startInstant: iso, endInstant: iso,
                               startDay: (2026, 9, 6), endDay: (2026, 9, 6))
        let event = try SyncCoders.decoder().decode(CalendarEvent.self, from: data)
        XCTAssertEqual(event.startDate, strayTime, "本机日一致 → 不该被改写")
        XCTAssertEqual(event.endDate, strayTime)
    }

    // MARK: - I3：非全天事件绝不被改写

    func testTimedEventIsNeverReprojected() throws {
        let data = try payload(isAllDay: false)
        let event = try SyncCoders.decoder().decode(CalendarEvent.self, from: data)
        XCTAssertFalse(event.isAllDay)
        XCTAssertEqual(event.startDate, ISO8601DateFormatter().date(from: Self.payloadStart)!,
                       "非全天事件的瞬时逐位不变")
        XCTAssertEqual(event.endDate, ISO8601DateFormatter().date(from: Self.payloadEnd)!)
    }

    // MARK: - 旧数据：没有分量时行为与改动前一致

    func testLegacyAllDayPayloadWithoutDayKeysKeepsInstants() throws {
        let data = try payload(startDay: nil, endDay: nil)
        let event = try SyncCoders.decoder().decode(CalendarEvent.self, from: data)
        XCTAssertTrue(event.isAllDay)
        XCTAssertEqual(event.startDate, ISO8601DateFormatter().date(from: Self.payloadStart)!,
                       "旧数据不反推、不改写，避免在无法复原时引入新的错位")
        XCTAssertEqual(event.endDate, ISO8601DateFormatter().date(from: Self.payloadEnd)!)
    }

    // MARK: - 编码侧：只有全天事件带分量

    func testEncodeWritesDayKeysOnlyForAllDayEvents() throws {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let allDay = CalendarEvent(title: "全天", startDate: start, isAllDay: true)
        let timed = CalendarEvent(title: "日程", startDate: start)

        func object(_ event: CalendarEvent) throws -> [String: Any] {
            try JSONSerialization.jsonObject(
                with: try SyncCoders.encoder().encode(event)
            ) as! [String: Any]
        }
        let allDayJSON = try object(allDay)
        XCTAssertNotNil(allDayJSON["startDay"], "全天事件必须带上年月日分量")
        XCTAssertNotNil(allDayJSON["endDay"])
        let timedJSON = try object(timed)
        XCTAssertNil(timedJSON["startDay"], "非全天事件不需要分量")
        XCTAssertNil(timedJSON["endDay"])
    }

    /// 编码再解码（同时区）必须幂等：分量与 startDate 不会互相漂移
    func testEncodeDecodeRoundTripIsStable() throws {
        let calendar = Calendar(identifier: .gregorian)
        let day = CalendarDayKey(year: 2026, month: 9, day: 6)
        let m = CalendarEvent.materializeAllDay(start: day, end: day, in: calendar)
        let original = CalendarEvent(title: "全天", startDate: m.start, endDate: m.end, isAllDay: true)

        let back = try SyncCoders.decoder().decode(
            CalendarEvent.self, from: try SyncCoders.encoder().encode(original)
        )
        XCTAssertEqual(back.startDate, original.startDate)
        XCTAssertEqual(back.endDate, original.endDate)
    }
}
