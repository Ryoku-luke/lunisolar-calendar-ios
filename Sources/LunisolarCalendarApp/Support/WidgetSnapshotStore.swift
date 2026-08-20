import Foundation

// MARK: - 主 App ⇄ Widget 共享快照模型

/// 主 App 每次 EventStore.save() 后都把"今日概览"写到 App Group 共享容器：
/// Widget Extension 直接读这份 JSON，无需再启动 EventStore（小组件内存更紧张）
public struct WidgetSharedSnapshot: Codable, Sendable, Equatable {
    /// 快照生成时间（UTC iso8601）
    public let updatedAt: Date

    /// 今日公历 date（startOfDay）
    public let targetDay: Date

    /// 今日已安排事件数（含全天 + 普通日程 + 提醒）
    public let todaysEventsCount: Int

    /// 今日已完成事件数
    public let todaysCompletedCount: Int

    /// 今日前 N 条待办标题（Widget Medium/Large 列表直接用）
    public let topTitles: [WidgetTodoTitle]

    public init(
        updatedAt: Date,
        targetDay: Date,
        todaysEventsCount: Int,
        todaysCompletedCount: Int,
        topTitles: [WidgetTodoTitle]
    ) {
        self.updatedAt = updatedAt
        self.targetDay = targetDay
        self.todaysEventsCount = todaysEventsCount
        self.todaysCompletedCount = todaysCompletedCount
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

    /// Widget Extension 的 TimelineProvider 启动时先调用一次：读取今日真实待办
    /// - Returns: 失败或过旧返回 nil（provider 回退到占位）
    public static func read(
        appGroupID: String? = nil,
        fileName: String = "widget_snapshot.json",
        maxAge: TimeInterval = 6 * 3600
    ) -> WidgetSharedSnapshot? {
        guard let url = resolveURL(appGroupID: appGroupID, fileName: fileName),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snap = try decoder.decode(WidgetSharedSnapshot.self, from: data)
            // 6h 以前的快照视为过期（例如手机关机几天，昨天的快照别再显示）
            if Date().timeIntervalSince(snap.updatedAt) > maxAge { return nil }
            // 日期不匹配：快照是别的日期，也别用
            let cal = Calendar(identifier: .gregorian)
            if !cal.isDate(snap.targetDay, inSameDayAs: Date()) { return nil }
            return snap
        } catch {
            return nil
        }
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
