import XCTest
@testable import LunisolarCalendarApp

// MARK: - 导出格式与文档（D6）
//
// 导出入口是 UI，但**格式 → 内容 / 类型 / 文件名**的映射是纯函数，这里直接测：
// 入口接错了、格式串错了、文件名丢了扩展名，都会在这里红。

final class DataExportTests: XCTestCase {

    private func events() -> [CalendarEvent] {
        [CalendarEvent(title: "导出测试会", startDate: Date(timeIntervalSince1970: 1_800_000_000)),
         CalendarEvent(title: "第二个", startDate: Date(timeIntervalSince1970: 1_800_086_400))]
    }

    /// 三种格式的内容必须**与 DataPortability 的输出逐字节一致**——
    /// 入口只是换个壳，不允许在壳里二次加工。
    func testEachFormatMatchesDataPortabilityOutput() {
        let list = events()
        XCTAssertEqual(ExportFormat.ics.makeText(from: list), DataPortability.exportICS(from: list))
        XCTAssertEqual(ExportFormat.json.makeText(from: list), DataPortability.exportJSON(from: list))
        XCTAssertEqual(ExportFormat.csv.makeText(from: list), DataPortability.exportCSV(from: list))
    }

    func testFileExtensionsAndContentTypes() {
        XCTAssertEqual(ExportFormat.ics.fileExtension, "ics")
        XCTAssertEqual(ExportFormat.json.fileExtension, "json")
        XCTAssertEqual(ExportFormat.csv.fileExtension, "csv")
        // csv/json 应有明确的系统类型（ics 系统没有，允许退化）
        XCTAssertEqual(ExportFormat.json.contentType, .json)
        XCTAssertEqual(ExportFormat.csv.contentType, .commaSeparatedText)
    }

    func testDefaultFilenameHasNoExtensionAndCarriesTheDate() {
        let cal = Calendar(identifier: .gregorian)
        let day = cal.date(from: DateComponents(year: 2026, month: 10, day: 4))!
        let name = ExportFormat.ics.defaultFilename(now: day)
        XCTAssertEqual(name, "qinghe-events-20261004")
        XCTAssertFalse(name.contains("."), "扩展名应由 fileExporter 按 contentType 决定，不能写进文件名")
    }

    /// 文档包装必须原样带回内容（壳里丢数据是最隐蔽的一种坏）
    func testDocumentCarriesPayloadUnchanged() {
        let payload = Data("标题,类型\n导出测试会,schedule".utf8)
        XCTAssertEqual(DataExportDocument(data: payload).data, payload)
    }
}
