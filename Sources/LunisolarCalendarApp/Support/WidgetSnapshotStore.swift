import Foundation

// MARK: - 主 App ⇄ Widget 共享快照模型

/// 主 App 每次 EventStore.save() 后把「今天起 N 天的待办概览」写到 App Group 共享容器：
/// Widget Extension 直接读这份 JSON，无需再启动 EventStore（小组件内存更紧张）。
///
/// ⚠️ 为什么是**多天窗口**而不是只存「今天」：
/// 小组件时间线一次生成「今天 + 后 7 天」共 8 条 entry（黄历/农历要逐日变化）。
/// 旧实现只存今天这一份、其余 7 天的计数硬编码为 0 —— 于是过了午夜小组件切到
/// 「明天」那条 entry 时（或用户整天没打开 App），会显示 `0/0` 与「今日还没安排」，
/// 与真实数据矛盾。现在窗口内每一天的统计都写进去，每条 entry 都取得到真实数据。
public struct WidgetSharedSnapshot: Codable, Sendable, Equatable {
    /// 快照生成时间（UTC iso8601）
    public let updatedAt: Date

    /// 窗口首日（= 写入当刻的「今天」，startOfDay）
    public let targetDay: Date

    /// 窗口内每一天的待办统计（首日 = 今天，逐日递增）
    public let days: [WidgetDaySnapshot]

    public init(updatedAt: Date, targetDay: Date, days: [WidgetDaySnapshot]) {
        self.updatedAt = updatedAt
        self.targetDay = targetDay
        self.days = days
    }

    /// 取窗口内某一天的桶（按「日」比较，避免时刻差异）；不在窗口内返回 nil
    public func day(for date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> WidgetDaySnapshot? {
        days.first { calendar.isDate($0.day, inSameDayAs: date) }
    }
}

/// 窗口内某一天的待办统计（小组件时间线按天取用）
public struct WidgetDaySnapshot: Codable, Sendable, Equatable {
    /// 该日（startOfDay）
    public let day: Date
    /// 当日事件数（含全天 + 日程 + 提醒）
    public let eventsCount: Int
    /// 当日已完成数
    public let completedCount: Int
    /// 当日待办标题（按优先级降序取前若干条）
    public let topTitles: [WidgetTodoTitle]

    public init(day: Date, eventsCount: Int, completedCount: Int, topTitles: [WidgetTodoTitle]) {
        self.day = day
        self.eventsCount = eventsCount
        self.completedCount = completedCount
        self.topTitles = topTitles
    }
}

/// 小组件里的待办行：标题 + 完成状态 + 优先级（用于色点）
public struct WidgetTodoTitle: Codable, Sendable, Equatable, Identifiable {
    public let id: String           // 用 UUID().uuidString
    public let title: String
    public let isCompleted: Bool
    public let priorityHex: String  // "#C41A1A"/"#D97706"/"#2563EB"/"#6B7280"

    public init(id: String, title: String, isCompleted: Bool, priorityHex: String) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.priorityHex = priorityHex
    }
}

// MARK: - 读/写入口

/// 快照文件的"约定容器"：
/// - 宿主 App 有 App Group 能力时传 appGroupID，Widget 就直接共享
/// - 未配置 App Group（SPM 本地测试 / Linux）时回退到 Documents + NSTemporaryDirectory
///   （此时 Widget 读不到真实事件，仍可用 provider 占位数据兜底，不会崩）
public enum WidgetSnapshotStore {

    /// 主 App 每次 save() 后调用：把今日统计写入 JSON
    @discardableResult
    public static func write(
        _ snapshot: WidgetSharedSnapshot,
        appGroupID: String? = nil,
        fileName: String = "widget_snapshot.json"
    ) -> Bool {
        guard let url = resolveURL(appGroupID: appGroupID, fileName: fileName) else { return false }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(snapshot)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// 快照覆盖的天数：与小组件时间线长度一致（今天 + 后 7 天）
    public static let windowDays = 8

    /// Widget Extension 的 TimelineProvider 读取整份快照；文件缺失或解码失败返回 nil
    ///
    /// ⚠️ 不再用「快照有多旧」判过期。快照是**逐日桶**，窗口本身就是有效期：
    /// 只要目标日落在窗口内，那份统计就是写入当刻对该日的真实值（该日期的日程若在那之后
    /// 有改动，App 会再次写入并重载时间线）。旧的 6h maxAge 会把一份仍然有效的窗口判成
    /// 过期，正是跨天后小组件拿不到数据的另一半原因。
    public static func read(
        appGroupID: String? = nil,
        fileName: String = "widget_snapshot.json"
    ) -> WidgetSharedSnapshot? {
        guard let url = resolveURL(appGroupID: appGroupID, fileName: fileName),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(WidgetSharedSnapshot.self, from: data)
        } catch {
            return nil
        }
    }

    /// 读取指定日期的待办桶；不在窗口内（含无快照 / 解码失败）返回 nil
    public static func daySnapshot(
        for day: Date,
        appGroupID: String? = nil,
        fileName: String = "widget_snapshot.json"
    ) -> WidgetDaySnapshot? {
        read(appGroupID: appGroupID, fileName: fileName)?.day(for: day)
    }

    // MARK: 路径解析

    private static func resolveURL(appGroupID: String?, fileName: String) -> URL? {
        // 1. App Group（真正主 App + Widget 共享场景）——只在 iOS/macOS 等支持的平台存在
        #if canImport(Darwin)
        if let id = appGroupID, !id.isEmpty,
           let groupURL = FileManager.default
               .containerURL(forSecurityApplicationGroupIdentifier: id) {
            return groupURL.appendingPathComponent("Library/Caches/\(fileName)")
        }
        #endif
        // 2. Documents（SPM iOS 宿主里单机测，Widget 拿不到但至少主 App 能写）
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        if let docs { return docs.appendingPathComponent(fileName) }
        // 3. Linux 兜底：/tmp
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName)
    }
}

// MARK: - EventStore → WidgetSharedSnapshot 组装

extension Priority {
    /// 小组件色点：红/橙/蓝/灰，同主 App 语义色保持一致
    public var widgetHex: String {
        switch self {
        case .urgent:  return "#C41A1A"
        case .high:    return "#D97706"
        case .normal:  return "#2563EB"
        case .low:     return "#6B7280"
        }
    }
}
