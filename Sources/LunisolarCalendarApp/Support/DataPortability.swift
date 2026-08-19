import Foundation

// MARK: - 数据导入导出

/// 支持 .ics (iCalendar) 和 .csv 格式的导入导出
public enum DataPortability {

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
        var lines = content.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n").map(String.init)
        lines = lines.map { $0.hasPrefix(" ") ? String($0.dropFirst()) : $0 } // 处理折叠行

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
                var hasStart = false
                var hasEnd = false

                while idx < lines.count && !lines[idx].uppercased().hasPrefix("END:VEVENT") {
                    let vline = lines[idx]
                    let parts = vline.split(separator: ":", maxSplits: 1)
                    guard parts.count == 2 else { idx += 1; continue }
                    let key = parts[0].uppercased()
                    let value = String(parts[1])

                    if key.hasPrefix("SUMMARY") {
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
                    }
                    idx += 1
                }

                if hasStart {
                    if !hasEnd { endDate = startDate.addingTimeInterval(3600) }
                    let event = CalendarEvent(
                        title: title.isEmpty ? "导入事件" : title,
                        startDate: startDate,
                        endDate: endDate,
                        isAllDay: isAllDay,
                        location: location,
                        notes: notes
                    )
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
}
