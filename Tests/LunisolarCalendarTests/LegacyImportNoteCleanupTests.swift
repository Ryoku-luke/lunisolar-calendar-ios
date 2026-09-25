import XCTest
import LunarCore
@testable import LunisolarCalendarApp

// MARK: - 旧版 ICS 导入遗留备注的清理（一次性）
//
// 旧 importICS 不识别子块，`BEGIN:VALARM` 里的 `DESCRIPTION:提醒`（英文导出为 `Reminder`）
// 会被当成事件备注写入 —— 事件自身备注被整段覆盖。子块泄漏本身已修，但**已被污染的数据**
// 不会自愈，因此提供一次性清理。
//
// 判定必须保守，三个条件同时满足才动手：
// ① 备注含 `[ICS-UID]` 标记（证明来源是 ICS 导入）；
// ② 首行恰为「提醒」/「Reminder」（忽略大小写与空白）；
// ③ 该行是独立段落（下一行为空）——否则那行是用户自己写的。

final class LegacyImportNoteCleanupTests: XCTestCase {

    // MARK: 会清理

    func testClearsNoteThatOnlyHeldThePlaceholder() throws {
        let r = try XCTUnwrap(DataPortability.cleanupLegacyImportNotes("提醒\n\n[ICS-UID]abc-123"))
        XCTAssertNil(r.cleanedNotes, "原备注已无法找回，不应留下只有 UID 标记的空壳")
    }

    func testEnglishPlaceholderIsAlsoCleaned() throws {
        for placeholder in ["Reminder", "REMINDER", "reminder"] {
            let r = try XCTUnwrap(
                DataPortability.cleanupLegacyImportNotes("\(placeholder)\n\n[ICS-UID]x"),
                "\(placeholder) 应被识别为 VALARM 占位文案"
            )
            XCTAssertNil(r.cleanedNotes)
        }
    }

    func testKeepsContentBelowThePlaceholder() throws {
        let r = try XCTUnwrap(
            DataPortability.cleanupLegacyImportNotes("提醒\n\n真正的备注\n[ICS-UID]abc"))
        XCTAssertEqual(r.cleanedNotes, "真正的备注\n[ICS-UID]abc")
    }

    func testToleratesSurroundingWhitespace() throws {
        let r = try XCTUnwrap(DataPortability.cleanupLegacyImportNotes("  提醒  \n\n[ICS-UID]a"))
        XCTAssertNil(r.cleanedNotes)
    }

    // MARK: 不清理（宁漏一条，不误删用户写的字）

    func testUserNoteStartingWithTheWordReminderIsUntouched() {
        XCTAssertNil(DataPortability.cleanupLegacyImportNotes("提醒我买牛奶\n\n[ICS-UID]a"),
                     "首行并非恰好等于占位文案")
        XCTAssertNil(DataPortability.cleanupLegacyImportNotes("提醒\n要带伞\n\n[ICS-UID]a"),
                     "「提醒」后面紧跟用户内容 → 这行是用户自己写的，不能删")
    }

    func testNonImportedEventIsUntouched() {
        XCTAssertNil(DataPortability.cleanupLegacyImportNotes("提醒"),
                     "没有 [ICS-UID] 标记 → 无法证明来自导入")
        XCTAssertNil(DataPortability.cleanupLegacyImportNotes("会议纪要\n[ICS-UID]a"))
    }

    func testNilAndEmptyAreUntouched() {
        XCTAssertNil(DataPortability.cleanupLegacyImportNotes(nil))
        XCTAssertNil(DataPortability.cleanupLegacyImportNotes(""))
    }

    // MARK: 端到端（隔离 store）

    @MainActor
    func testEventServiceCleansPollutedEventsAndIsIdempotent() throws {
        let store = makeIsolatedEventStore()
        let service = EventService(store: store)
        _ = store.clearAll(skipSync: true)

        var polluted = CalendarEvent(title: "季度评审", startDate: Date().addingTimeInterval(3600))
        polluted.notes = "提醒\n\n[ICS-UID]abc-123"
        var userNote = CalendarEvent(title: "自己的日程", startDate: Date().addingTimeInterval(7200))
        userNote.notes = "记得带伞"
        store.add(polluted, skipSync: true)
        store.add(userNote, skipSync: true)

        XCTAssertEqual(service.cleanUpLegacyImportNotes(), 1, "只应清理被污染的那一条")

        let cleaned = try XCTUnwrap(store.events.first { $0.id == polluted.id })
        XCTAssertNil(cleaned.notes, "污染备注应被清空")
        XCTAssertEqual(store.events.first { $0.id == userNote.id }?.notes, "记得带伞",
                       "用户自己写的备注不得被改动")

        XCTAssertEqual(service.cleanUpLegacyImportNotes(), 0, "幂等：再跑一次不应有改动")
    }
}
