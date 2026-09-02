import Foundation

// MARK: - 倒数日 / 纪念日模型

/// 倒数日事件类型
public enum CountdownKind: String, Codable, CaseIterable, Sendable {
    case countdown   // 倒数日（未来某天，如考试、婚礼）
    case anniversary // 纪念日（每年重复，如生日、结婚纪念）

    public var label: String {
        switch self {
        case .countdown: return "倒数日"
        case .anniversary: return "纪念日"
        }
    }

    public var icon: String {
        switch self {
        case .countdown: return "hourglass"
        case .anniversary: return "heart"
        }
    }
}

/// 倒数日 / 纪念日事件
public struct CountdownEvent: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var date: Date          // 目标日期
    public var kind: CountdownKind
    public var emoji: String       // 自定义图标
    public var note: String?

    public init(id: UUID = UUID(), title: String, date: Date, kind: CountdownKind,
                emoji: String = "📅", note: String? = nil) {
        self.id = id
        self.title = title
        self.date = date
        self.kind = kind
        self.emoji = emoji
        self.note = note
    }

    /// 距今天的天数（正数=未来，负数=已过）
    public func daysFrom(today: Date) -> Int {
        let cal = Calendar(identifier: .gregorian)
        let t = cal.startOfDay(for: today)
        let d = cal.startOfDay(for: date)
        return cal.dateComponents([.day], from: t, to: d).day ?? 0
    }

    /// 显示文案：如"还有 30 天" / "已过 5 天" / "今天"
    public func displayText(today: Date) -> String {
        let days = daysFrom(today: today)
        if days == 0 { return "就是今天" }
        if days > 0 { return "还有 \(days) 天" }
        return "已过 \(-days) 天"
    }

    /// 纪念日的下次周年日期
    public func nextAnniversary(from today: Date) -> Date? {
        guard kind == .anniversary else { return nil }
        let cal = Calendar(identifier: .gregorian)
        let nowComps = cal.dateComponents([.year, .month, .day], from: today)
        let origComps = cal.dateComponents([.month, .day], from: date)
        var nextComps = DateComponents()
        nextComps.month = origComps.month
        nextComps.day = origComps.day
        nextComps.year = nowComps.year
        if let next = cal.date(from: nextComps), next >= cal.startOfDay(for: today) {
            return next
        }
        nextComps.year = (nowComps.year ?? 2026) + 1
        return cal.date(from: nextComps)
    }
}

// MARK: - 倒数日存储

#if canImport(Observation)
import Observation
#endif

/// 倒数日数据持久化（JSON 文件，与 EventStore 同目录）。
#if canImport(Observation)
@Observable
#endif
@MainActor
public final class CountdownStore {

    @MainActor public static let shared = CountdownStore()

    public private(set) var events: [CountdownEvent] = []

    private let fileURL: URL

    /// P5 防抖写入：合并 0.5s 内连续 CRUD 的磁盘写入
    private var pendingSaveWorkItem: DispatchWorkItem?
    private let saveDebounceInterval: TimeInterval = 0.5

    @MainActor
    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        fileURL = docs.appendingPathComponent("countdowns.json")
        // 确保父目录存在（iOS 首次安装、沙盒重置等场景下 Documents 可能为空或不存在）
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        load()
    }

    // MARK: - CRUD

    public func add(_ event: CountdownEvent) {
        events.append(event)
        events.sort { $0.date < $1.date }
        save()
    }

    public func update(_ event: CountdownEvent) {
        guard let idx = events.firstIndex(where: { $0.id == event.id }) else { return }
        events[idx] = event
        events.sort { $0.date < $1.date }
        save()
    }

    public func delete(id: UUID) {
        events.removeAll { $0.id == id }
        save()
    }

    // MARK: - 持久化

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            events = try JSONDecoder().decode([CountdownEvent].self, from: data)
        } catch {
            // 损坏隔离：同 EventStore 的策略，避免下一次 saveNow 原子写默默覆盖掉用户手编辑/导入的数据
            let backup = fileURL.deletingLastPathComponent()
                .appendingPathComponent("\(fileURL.lastPathComponent).corrupt.\(Int64(Date().timeIntervalSince1970 * 1000))")
            try? FileManager.default.copyItem(at: fileURL, to: backup)
            AppLogger.app.error("倒数日数据加载失败: \(error.localizedDescription)，已隔离备份到 \(backup.lastPathComponent)")
            events = []
        }
    }

    private func save() {
        pendingSaveWorkItem?.cancel()
        let wi = DispatchWorkItem { [weak self] in
            self?.saveNow()
        }
        pendingSaveWorkItem = wi
        DispatchQueue.main.asyncAfter(deadline: .now() + saveDebounceInterval, execute: wi)
    }

    private func saveNow() {
        pendingSaveWorkItem?.cancel()
        pendingSaveWorkItem = nil
        do {
            let data = try JSONEncoder().encode(events)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            AppLogger.app.error("倒数日数据保存失败: \(error.localizedDescription)")
        }
    }

    /// 测试用：强制把挂起的防抖落盘立即执行
    @MainActor
    public func _testFlushSave() {
        saveNow()
    }
}
