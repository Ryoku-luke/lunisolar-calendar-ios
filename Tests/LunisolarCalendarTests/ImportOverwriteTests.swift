import XCTest
@testable import LunisolarCalendarApp

// MARK: - 导入的时间戳语义（"重复导入会不会静默盖掉本地编辑"）
//
// 背景（执行计划 P2-3）：`importICS` 是**构造**事件而不是解码事件，
// 走的是 `CalendarEvent(...)` 构造器 → `createdAt/updatedAt` 被写成**导入那一刻**。
// 于是 `.keepLatest`（默认策略，比较 updatedAt）在重复导入同一份 .ics 时必然判定
// 「导入的更新」→ 把用户的本地编辑盖回去，而设置页仍然提示「导入成功」。
//
// 判据：源文件里的 `DTSTAMP`（创建）与 `LAST-MODIFIED`（最后修订，RFC 5545 §3.8.7.3）
// 才是这条记录在**源日历**里的时间。导入必须带上它们，否则 .ics 这条路
// 永远学不会「谁更新」。

final class ImportOverwriteTests: XCTestCase {

    private func ics(_ body: String) -> String {
        """
        BEGIN:VCALENDAR\r
        VERSION:2.0\r
        \(body)\r
        END:VCALENDAR\r
        """
    }

    /// 一份「没被改过」的 .ics：LAST-MODIFIED == DTSTAMP == 9/1
    private let original = """
        BEGIN:VEVENT\r
        UID:review-1\r
        SUMMARY:季度评审\r
        DTSTART:20261001T100000Z\r
        DTEND:20261001T110000Z\r
        DTSTAMP:20260901T000000Z\r
        LAST-MODIFIED:20260901T000000Z\r
        LOCATION:3 号会议室\r

        """

    private func content(_ body: String) -> String { ics(body) }

    // MARK: - 验收用例（执行计划 P2-3 的原文口径）

    @MainActor
    func testReimportingUnchangedICSDoesNotOverwriteLocalEdit() {
        let store = makeIsolatedEventStore()
        let text = content(original)

        let first = store.merge(DataPortability.importICS(text))
        XCTAssertEqual(first.added, 1, "首次导入应新增 1 条")
        guard let imported = store.events.first(where: { $0.title == "季度评审" }) else {
            return XCTFail("首次导入后应能找到该事件")
        }

        // 本地编辑：改标题（`update` 会把 updatedAt 顶到「现在」）
        var edited = imported
        edited.title = "季度评审（我改过）"
        store.update(edited)

        // 再次导入**同一份**文件（源日历没变过）
        let second = store.merge(DataPortability.importICS(text))
        XCTAssertEqual(second.updated, 0,
                       "同一份 .ics 重复导入不该被判成「更新」——源文件的修订时间没有变")
        XCTAssertEqual(second.skipped, 1, "应保留本地版本")
        XCTAssertEqual(store.events.first(where: { $0.id == imported.id })?.title,
                       "季度评审（我改过）",
                       "本地编辑被重复导入静默盖掉了（P2-3 的原始缺陷）")
    }

    // MARK: - 反向：源日历真的更新了，导入必须赢（别把导入做成永远输）

    @MainActor
    func testICSWithNewerLastModifiedStillWins() {
        let store = makeIsolatedEventStore()
        // UID/标题/起止都不变，只改地点 + 修订时间 → 伪 UID 相同，走「同 id 冲突」分支
        _ = store.merge(DataPortability.importICS(content(original)))

        let revised = original.replacingOccurrences(of: "LOCATION:3 号会议室", with: "LOCATION:5 号会议室")
            .replacingOccurrences(of: "LAST-MODIFIED:20260901T000000Z", with: "LAST-MODIFIED:20260902T000000Z")
        let result = store.merge(DataPortability.importICS(content(revised)))

        XCTAssertEqual(result.updated, 1, "源日历的修订时间更新时，导入应覆盖")
        XCTAssertEqual(store.events.first(where: { $0.title == "季度评审" })?.location, "5 号会议室")
    }

    // MARK: - 导出侧：不带修订时间，往返就还是学不会

    func testExportedICSCarriesLastModifiedSoRevisionSurvivesRoundTrip() {
        var event = CalendarEvent(title: "带修订时间的事件",
                                  startDate: Date(timeIntervalSince1970: 1_800_000_000))
        let revision = Date(timeIntervalSince1970: 1_790_000_000)
        event.updatedAt = revision

        let text = DataPortability.exportICS(from: [event])
        XCTAssertTrue(text.contains("LAST-MODIFIED:"),
                      "导出必须写出 LAST-MODIFIED，否则这份文件重新导入时判断不出新旧")

        let back = DataPortability.importICS(text).first
        XCTAssertEqual(back?.updatedAt.timeIntervalSince1970 ?? 0,
                       revision.timeIntervalSince1970,
                       accuracy: 1,
                       "DTSTAMP/LAST-MODIFIED 往返后应保住原修订时间（ICS 精度到秒）")
    }

    /// DTSTAMP 是「创建时间」：导入后事件的历史应保留，而不是被写成导入那一刻
    func testDTSTAMPBecomesCreatedAt() {
        let event = DataPortability.importICS(content(original)).first
        XCTAssertEqual(event?.createdAt.timeIntervalSince1970 ?? 0,
                       Date(timeIntervalSince1970: 1_788_220_800).timeIntervalSince1970,  // 2026-09-01T00:00:00Z
                       accuracy: 1)
    }

    /// 反向守卫：源文件确实没带任何时间戳时，退回「导入时刻」——
    /// 不能因为"怕覆盖"就把它设成远古时间（那样导入永远不生效）。
    func testICSWithoutAnyStampFallsBackToImportTime() {
        let before = Date()
        let noStamp = """
            BEGIN:VEVENT\r
            UID:no-stamp\r
            SUMMARY:无时间戳事件\r
            DTSTART:20261001T100000Z\r
            DTEND:20261001T110000Z\r

            """
        let event = DataPortability.importICS(content(noStamp)).first
        XCTAssertNotNil(event)
        XCTAssertGreaterThanOrEqual(event?.updatedAt ?? .distantPast,
                                    before.addingTimeInterval(-1),
                                    "没有 DTSTAMP/LAST-MODIFIED 时应退回导入时刻")
    }
}
