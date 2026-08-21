import Foundation

// MARK: - 合并结果统计（ICS / JSON 导入都会返回）

/// 导入合并后的结果统计，用于展示 Alert 文案
public struct ImportMergeResult: Equatable, Sendable {
    /// 新增的条目数（EventStore 中不存在同 id）
    public var added: Int
    /// 按 id 覆盖更新的条目数（同 id 已存在，incoming 更「新」或策略为 overwrite）
    public var updated: Int
    /// 保留原样未动的条目数（同 id 已存在且本地 updatedAt 较新或策略为 skip）
    public var skipped: Int
    /// 解析失败或数据异常被跳过的条目
    public var invalid: Int

    public init(added: Int = 0, updated: Int = 0, skipped: Int = 0, invalid: Int = 0) {
        self.added = added
        self.updated = updated
        self.skipped = skipped
        self.invalid = invalid
    }

    /// 总处理量
    public var totalProcessed: Int { added + updated + skipped + invalid }
    /// 发生冲突（updated + skipped），用于 UI 判断"是否需要冲突提示"
    public var hasConflicts: Bool { (updated + skipped) > 0 }
}

// MARK: - 冲突策略

/// 导入时遇到同 id 事件如何处理
public enum ImportConflictPolicy: String, Codable, CaseIterable, Sendable {
    /// 谁更新时间更新就用谁（推荐）
    case keepLatest
    /// 一律保留本地（跳过 incoming）
    case keepLocal
    /// 一律用 incoming 覆盖
    case overwrite
}

// MARK: - 数据导入导出

/// 支持 .ics (iCalendar) / .csv / .json 格式的导入导出，以及合并策略与结果统计
public enum DataPortability {

    // MARK: - JSON 全量备份（推荐：字段零损失）

    /// 导出为 JSON（全字段无损，包含 id / repeatRule.lunarAnnually / isNotified / createdAt 等）
    public static func exportJSON(from events: [CalendarEvent]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let wrapper = JSONBackupWrapper(
            version: 1,
            exportedAt: Date(),
            count: events.count,
            events: events
        )
        guard let data = try? encoder.encode(wrapper),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    /// 从 JSON 字符串解析事件列表（支持本 app 导出的备份 JSON）
    public static func importJSON(_ content: String) -> [CalendarEvent] {
        guard let data = content.data(using: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // 先尝试 wrapper 格式；否则退化为直接解数组（兼容一些手工拼接）
        if let wrapper = try? decoder.decode(JSONBackupWrapper.self, from: data) {
            return wrapper.events
        }
        if let array = try? decoder.decode([CalendarEvent].self, from: data) {
            return array
        }
        return []
    }

    // MARK: - ICS 导出

    /// 导出所有事件为 .ics 格式字符串
    public static func exportICS(from events: [CalendarEvent]) -> String {
        var lines: [String] = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//LunisolarCalendar//iOS//CN",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH"
        ]

        let dfmt = DateFormatter()
        dfmt.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        dfmt.timeZone = TimeZone(identifier: "UTC")
        let dfmtAllDay = DateFormatter()
        dfmtAllDay.dateFormat = "yyyyMMdd"
        dfmtAllDay.timeZone = TimeZone(identifier: "UTC")

        for event in events {
            lines.append("BEGIN:VEVENT")
            lines.append("UID:\(event.id.uuidString)")
            lines.append("DTSTAMP:\(dfmt.string(from: event.createdAt))")

            if event.isAllDay {
                lines.append("DTSTART;VALUE=DATE:\(dfmtAllDay.string(from: event.startDate))")
                lines.append("DTEND;VALUE=DATE:\(dfmtAllDay.string(from: event.endDate))")
            } else {
                lines.append("DTSTART:\(dfmt.string(from: event.startDate))")
                lines.append("DTEND:\(dfmt.string(from: event.endDate))")
            }

            lines.append("SUMMARY:\(escapeICS(event.title))")
            if let loc = event.location, !loc.isEmpty {
                lines.append("LOCATION:\(escapeICS(loc))")
            }
            if let notes = event.notes, !notes.isEmpty {
                lines.append("DESCRIPTION:\(escapeICS(notes))")
            }

            let priorityVal: String
            switch event.priority {
            case .urgent: priorityVal = "1"
            case .high:   priorityVal = "5"
            case .normal: priorityVal = "9"
            case .low:    priorityVal = "9"
            }
            lines.append("PRIORITY:\(priorityVal)")
            lines.append("STATUS:\(event.isCompleted ? "COMPLETED" : "CONFIRMED")")

            switch event.repeatRule {
            case .never: break
            case .daily:    lines.append("RRULE:FREQ=DAILY")
            case .workday:  lines.append("RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR")
            case .weekly:   lines.append("RRULE:FREQ=WEEKLY")
            case .monthly:  lines.append("RRULE:FREQ=MONTHLY")
            case .yearly:   lines.append("RRULE:FREQ=YEARLY")
            case .lunarAnnually: break // ICS 标准不支持农历重复，跳过
            }

            lines.append("END:VEVENT")
        }

        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\r\n")
    }

    // MARK: - CSV 导出

    /// 导出所有事件为 .csv 格式字符串
    public static func exportCSV(from events: [CalendarEvent]) -> String {
        let header = "标题,类型,开始时间,结束时间,全天,地点,备注,重复规则,优先级,已完成,创建时间"
        var rows: [String] = [header]

        let dfmt = DateFormatter()
        dfmt.dateFormat = "yyyy-MM-dd HH:mm"

        for event in events {
            let row: [String] = [
                escapeCSV(event.title),
                event.type.title,
                dfmt.string(from: event.startDate),
                dfmt.string(from: event.endDate),
                event.isAllDay ? "是" : "否",
                escapeCSV(event.location ?? ""),
                escapeCSV(event.notes ?? ""),
                event.repeatRule.title,
                event.priority.title,
                event.isCompleted ? "是" : "否",
                dfmt.string(from: event.createdAt)
            ]
            rows.append(row.joined(separator: ","))
        }

        return rows.joined(separator: "\n")
    }

    // MARK: - ICS 导入

    /// 从 .ics 字符串解析事件列表
    public static func importICS(_ content: String) -> [CalendarEvent] {
        var events: [CalendarEvent] = []
        // RFC 5545: 折叠行以空格或制表符开头，需拼接到上一行末尾
        let rawLines = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        // 展开折叠行
        var lines: [String] = []
        for line in rawLines {
            if (line.hasPrefix(" ") || line.hasPrefix("\t")) && !lines.isEmpty {
                lines[lines.count - 1] += String(line.dropFirst())
            } else {
                lines.append(line)
            }
        }

        var idx = 0
        let dfmtUTC = DateFormatter()
        dfmtUTC.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        dfmtUTC.timeZone = TimeZone(identifier: "UTC")
        let dfmtLocal = DateFormatter()
        dfmtLocal.dateFormat = "yyyyMMdd'T'HHmmss"
        let dfmtAllDay = DateFormatter()
        dfmtAllDay.dateFormat = "yyyyMMdd"
        dfmtAllDay.timeZone = TimeZone(identifier: "UTC")

        while idx < lines.count {
            let line = lines[idx]
            if line.uppercased().hasPrefix("BEGIN:VEVENT") {
                idx += 1
                var title = ""
                var startDate = Date()
                var endDate = Date().addingTimeInterval(3600)
                var isAllDay = false
                var location: String? = nil
                var notes: String? = nil
                var rawUID: String? = nil
                var parsedRRULE: RepeatRule? = nil
                var hasStart = false
                var hasEnd = false

                while idx < lines.count && !lines[idx].uppercased().hasPrefix("END:VEVENT") {
                    let vline = lines[idx]
                    let parts = vline.split(separator: ":", maxSplits: 1)
                    guard parts.count == 2 else { idx += 1; continue }
                    let key = parts[0].uppercased()
                    let value = String(parts[1])

                    if key.hasPrefix("UID") {
                        rawUID = value
                    } else if key.hasPrefix("SUMMARY") {
                        title = unescapeICS(value)
                    } else if key.hasPrefix("DTSTART") {
                        if key.contains("VALUE=DATE") {
                            if let d = dfmtAllDay.date(from: value) { startDate = d; isAllDay = true; hasStart = true }
                        } else if let d = dfmtUTC.date(from: value) ?? dfmtLocal.date(from: value) {
                            startDate = d; hasStart = true
                        }
                    } else if key.hasPrefix("DTEND") {
                        if key.contains("VALUE=DATE") {
                            if let d = dfmtAllDay.date(from: value) { endDate = d; hasEnd = true }
                        } else if let d = dfmtUTC.date(from: value) ?? dfmtLocal.date(from: value) {
                            endDate = d; hasEnd = true
                        }
                    } else if key.hasPrefix("LOCATION") {
                        location = unescapeICS(value)
                    } else if key.hasPrefix("DESCRIPTION") {
                        notes = unescapeICS(value)
                    } else if key.hasPrefix("RRULE") {
                        parsedRRULE = parseRRULE(value)
                    }
                    idx += 1
                }

                if hasStart {
                    if !hasEnd { endDate = startDate.addingTimeInterval(3600) }
                    // ICS 进来的事件没有稳定主键（UID 是对方日历的UUID，且不一定存在）。
                    // 为了让「重复导入不会产生副本」，我们用 (title, start, end, isAllDay) 哈希拼伪 UID
                    // 同时保存导入源 UID 以便 merge 时去重。
                    let pseudoID = pseudoUUIDForImport(
                        uid: rawUID,
                        title: title.isEmpty ? "导入事件" : title,
                        startDate: startDate,
                        endDate: endDate,
                        isAllDay: isAllDay
                    )
                    var event = CalendarEvent(
                        id: pseudoID,
                        title: title.isEmpty ? "导入事件" : title,
                        startDate: startDate,
                        endDate: endDate,
                        isAllDay: isAllDay,
                        location: location,
                        notes: notes,
                        repeatRule: parsedRRULE ?? .never
                    )
                    // 把外部的 UID 记到 notes 末尾，便于排查（不覆盖原 notes）
                    if let uid = rawUID, !uid.isEmpty {
                        let suffix = "\n\n[ICS-UID]\(uid)"
                        event.notes = (event.notes ?? "") + suffix
                    }
                    events.append(event)
                }
            }
            idx += 1
        }

        return events
    }

    // MARK: - 文件保存

    /// 将导出内容写入临时文件，返回文件 URL
    public static func writeToTempFile(content: String, filename: String) -> URL? {
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)
        do {
            try content.write(to: tmpURL, atomically: true, encoding: .utf8)
            return tmpURL
        } catch {
            print("导出文件写入失败: \(error)")
            return nil
        }
    }

    // MARK: - ICS 转义

    private static func escapeICS(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func unescapeICS(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    // MARK: - CSV 转义

    private static func escapeCSV(_ text: String) -> String {
        if text.contains(",") || text.contains("\"") || text.contains("\n") {
            return "\"\(text.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return text
    }

    // MARK: - ICS 辅助：解析 RRULE + 伪 UID（保证重复导入无副本）

    /// 解析常见 RRULE：FREQ=DAILY / WEEKLY;BYDAY=MO..FR / MONTHLY / YEARLY。其他返回 nil。
    private static func parseRRULE(_ value: String) -> RepeatRule? {
        let upper = value.uppercased()
        if upper.contains("FREQ=DAILY") { return .daily }
        if upper.contains("FREQ=MONTHLY") { return .monthly }
        if upper.contains("FREQ=YEARLY") { return .yearly }
        if upper.contains("FREQ=WEEKLY") {
            // 含 BYDAY=MO,TU,WE,TH,FR（且没其他）→ 工作日
            if let byDay = upper.split(separator: ";").first(where: { $0.hasPrefix("BYDAY=") }) {
                let days = String(byDay).dropFirst("BYDAY=".count)
                let workdaySet: Set<String> = ["MO","TU","WE","TH","FR"]
                let parts = Set(days.split(separator: ",").map(String.init))
                if !parts.isEmpty && parts.isSubset(of: workdaySet) {
                    return .workday
                }
            }
            return .weekly
        }
        return nil
    }

    /// 为导入的事件生成稳定伪 UUID：优先用 ics UID 做 hash + seed；否则用 (title, start, end, allDay)。
    /// 关键性质：同一 .ics 反复导入，事件的 UUID 不变，merge 会进入"同 id 冲突分支"而不是无脑新增副本。
    private static func pseudoUUIDForImport(
        uid: String?,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool
    ) -> UUID {
        var seed = "LUNISOLAR-ICS-IMPORT-V1|"
        if let uid = uid, !uid.isEmpty {
            seed += "uid:\(uid)"
        } else {
            let df = DateFormatter()
            df.dateFormat = "yyyyMMddHHmmss"
            df.timeZone = TimeZone(identifier: "UTC")
            seed += "t:\(title)|s:\(df.string(from: startDate))|e:\(df.string(from: endDate))|a:\(isAllDay ? 1 : 0)"
        }
        // 将 seed 哈希成 16 字节 → UUID
        var h = 0 as UInt64
        var l = 0 as UInt64
        for (i, ch) in seed.utf8.enumerated() {
            if i % 2 == 0 {
                h = (h &* 31) &+ UInt64(ch)
            } else {
                l = (l &* 31) &+ UInt64(ch)
            }
        }
        let bytes: [UInt8] = [
            UInt8((h >> 56) & 0xff), UInt8((h >> 48) & 0xff), UInt8((h >> 40) & 0xff), UInt8((h >> 32) & 0xff),
            UInt8((h >> 24) & 0xff), UInt8((h >> 16) & 0xff), UInt8((h >> 8) & 0xff), UInt8(h & 0xff),
            UInt8((l >> 56) & 0xff), UInt8((l >> 48) & 0xff), UInt8((l >> 40) & 0xff), UInt8((l >> 32) & 0xff),
            UInt8((l >> 24) & 0xff), UInt8((l >> 16) & 0xff), UInt8((l >> 8) & 0xff), UInt8(l & 0xff)
        ]
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

// MARK: - JSON 备份包装（带 version / exportedAt / count 元信息，方便未来升级做迁移）

/// JSON 备份顶层结构：{version, exportedAt, count, events: [...]}
public struct JSONBackupWrapper: Codable, Equatable, Sendable {
    public var version: Int
    public var exportedAt: Date
    public var count: Int
    public var events: [CalendarEvent]

    public init(version: Int, exportedAt: Date, count: Int, events: [CalendarEvent]) {
        self.version = version
        self.exportedAt = exportedAt
        self.count = count
        self.events = events
    }
}
