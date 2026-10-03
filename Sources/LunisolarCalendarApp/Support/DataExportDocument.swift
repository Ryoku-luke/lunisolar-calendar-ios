#if canImport(SwiftUI)
import SwiftUI
import UniformTypeIdentifiers

/// 导出格式（D6）。
///
/// 三种格式各有自己的扩展名与 UTType：**csv/json 有系统类型，ics 没有**——按扩展名推导，
/// 与 `ImportFileModifier` 的写法保持一致（导入/导出两侧口径对称）。
public enum ExportFormat: String, CaseIterable, Identifiable {
    case ics, json, csv

    public var id: String { rawValue }

    public var contentType: UTType {
        switch self {
        case .ics:  return UTType(filenameExtension: "ics") ?? .data
        case .json: return .json
        case .csv:  return .commaSeparatedText
        }
    }

    public var fileExtension: String { rawValue }

    /// 本地化标题（与导入侧「从 .ics 日历文件导入」对称）
    public var localizedTitle: String {
        switch self {
        case .ics:  return NSLocalizedString("导出为 .ics 日历文件", comment: "设置页：导出格式")
        case .json: return NSLocalizedString("导出为 .json 备份", comment: "设置页：导出格式")
        case .csv:  return NSLocalizedString("导出为 .csv 表格", comment: "设置页：导出格式")
        }
    }

    /// 格式 → 文本内容。**纯函数**，抽出来是为了不经过 UI 就能单测（D6 的验收基础）。
    public func makeText(from events: [CalendarEvent]) -> String {
        switch self {
        case .ics:  return DataPortability.exportICS(from: events)
        case .json: return DataPortability.exportJSON(from: events)
        case .csv:  return DataPortability.exportCSV(from: events)
        }
    }

    /// 默认文件名（不含扩展名——扩展名由 `fileExporter` 按 `contentType` 决定）
    public func defaultFilename(now: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyyMMdd"
        return "qinghe-events-\(f.string(from: now))"
    }
}

/// `fileExporter` 用的文档包装。导出量级是几百 KB 以内，内容直接放在内存里。
public struct DataExportDocument: FileDocument {
    public static var readableContentTypes: [UTType] { [.data] }

    public var data: Data

    public init(data: Data) { self.data = data }

    public init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
#endif
