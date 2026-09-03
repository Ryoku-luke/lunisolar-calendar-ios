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

    /// 纪念日的下次周年日期（非闰年 2/29 会落到 2/28，避免闰日生日跳过 2-3 年）
    public func nextAnniversary(from today: Date) -> Date? {
        guard kind == .anniversary else { return nil }
        let cal = Calendar(identifier: .gregorian)
        let nowComps = cal.dateComponents([.year, .month, .day], from: today)
        let origComps = cal.dateComponents([.month, .day], from: date)
        let yearNow = nowComps.year ?? 2026

        func resolve(year: Int) -> Date? {
            var c = DateComponents()
            c.month = origComps.month
            c.day   = origComps.day
            c.year  = year
            if let d = cal.date(from: c) { return d }
            // 闰日 2/29 在非闰年返回 nil → 退到 2/28
            if origComps.month == 2 && origComps.day == 29 {
                var fallback = DateComponents()
                fallback.month = 2
                fallback.day   = 28
                fallback.year  = year
                return cal.date(from: fallback)
            }
            return nil
        }

        if let thisYear = resolve(year: yearNow),
           thisYear >= cal.startOfDay(for: today) {
            return thisYear
        }
        return resolve(year: yearNow + 1)
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
    /// - 使用 Swift Concurrency Task（而非 DispatchWorkItem）保证 @MainActor 隔离，
    ///   符合 Swift 6 严格并发模式；避免 DispatchQueue.main 闭包
    ///   非 actor 隔离却访问 events 导致的编译警告/数据风险。
    private var pendingSaveTask: Task<Void, Never>?
    private let saveDebounceNs: UInt64 = 500_000_000  // 0.5s

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
        pendingSaveTask?.cancel()
        let ns = saveDebounceNs
        pendingSaveTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: ns) }
            catch { return }  // CancellationError 等 → 静默退出（新的 save 已接手）
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func saveNow() {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
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
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        saveNow()
    }
}
