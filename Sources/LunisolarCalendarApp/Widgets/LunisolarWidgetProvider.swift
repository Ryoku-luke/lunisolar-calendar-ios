#if canImport(WidgetKit)
import WidgetKit
import SwiftUI
import Foundation
import LunarCore

// MARK: - 通用小组件 Entry

/// 三种小组件共用的 Entry 结构：黄历/农历卡片/待办进度都从这里取数
public struct LunisolarWidgetEntry: TimelineEntry {
    public let date: Date                 // Entry 生效时间（系统渲染用）
    public let huangli: HuangliDay?       // 当天黄历（离散库优先）
    public let lunar: LunarDate?          // 当天农历
    public let festivals: [Festival]      // 节日
    public let primaryFestivalHex: String // 主节日主题色 hex
    public let todaysEventsCount: Int     // 今日日程数
    public let completedCount: Int        // 今日完成数
    public let hasFestival: Bool          // 是否有节日（UI 换色）
    public let topTitles: [WidgetTodoTitle] // 今日前 N 条待办（Medium/Large 列表用）
    /// 这一天是否**确实取到了**主 App 写的待办统计。
    ///
    /// 为 false 的情形：该日不在共享快照窗口内（App 已超过窗口天数未运行过）。
    /// 此时计数为 0 只是「不知道」的占位，UI 必须如实显示未知，
    /// 不能谎报 `0/0` 与「今日还没安排」——那会让用户以为今天真的没有安排。
    public let hasTodoData: Bool

    public init(
        date: Date,
        huangli: HuangliDay?,
        lunar: LunarDate?,
        festivals: [Festival],
        primaryFestivalHex: String,
        todaysEventsCount: Int,
        completedCount: Int,
        hasFestival: Bool,
        topTitles: [WidgetTodoTitle] = [],
        hasTodoData: Bool = true
    ) {
        self.date = date
        self.huangli = huangli
        self.lunar = lunar
        self.festivals = festivals
        self.primaryFestivalHex = primaryFestivalHex
        self.todaysEventsCount = todaysEventsCount
        self.completedCount = completedCount
        self.hasFestival = hasFestival
        self.topTitles = topTitles
        self.hasTodoData = hasTodoData
    }

    /// 进度百分比 0...1 (用于待办小组件)
    public var progress: Double {
        guard todaysEventsCount > 0 else { return 0 }
        return min(1.0, Double(completedCount) / Double(todaysEventsCount))
    }

    /// 进度环中央的百分比文本；不知道时显示 `—%` 而不是 `0%`
    public var percentText: String {
        hasTodoData ? "\(Int(progress * 100))%" : "—%"
    }

    /// 进度环中央的「完成/总数」文本；不知道时显示 `—/—` 而不是 `0/0`
    public var countText: String {
        hasTodoData ? "\(completedCount)/\(todaysEventsCount)" : "—/—"
    }
}

// MARK: - 通用 Timeline Provider（生成今天和未来 7 天的 Entry）

/// Provider 策略：
/// - 对"今天"这条 entry，尝试用 WidgetSnapshotStore.read 读主 App 写的真实待办统计，
///   读不到则用 0 占位（仍然显示黄历/农历/节日）
/// - 未来 7 天不读快照（小组件不应该知道未来几天的用户数据），全部 0
/// - policy: .afterMidnight（每天 00:05 自动换）
/// - 宿主 Widget Extension 在初始化时可把 appGroupID 通过 Environment 注入此处
public struct LunisolarWidgetTimelineProvider: TimelineProvider {
    public typealias Entry = LunisolarWidgetEntry

    /// 宿主 Extension 可显式传入 App Group ID（为 nil 时自动回退 Documents / nil 占位）
    public let appGroupID: String?

    public init(appGroupID: String? = nil) {
        self.appGroupID = appGroupID
    }

    /// 占位数据（锁屏/空状态）
    public func placeholder(in context: Context) -> LunisolarWidgetEntry {
        let now = Date()
        let resolved = HuangliDBProvider.resolve(date: now)
        // P2 优化：复用同一次农历转换，避免 festivals + primaryFestival 各转一次
        let lunar = ChineseCalendar.lunarDateSafe(from: now)
        let fes = FestivalManager.festivals(on: now, lunar: lunar)
        let hex = FestivalManager.primaryFestival(on: now, lunar: lunar)?.accentHex ?? "#C41A1A"
        return LunisolarWidgetEntry(
            date: now,
            huangli: resolved.huangliDay,
            lunar: resolved.huangliDay?.lunar,
            festivals: Array(fes.prefix(2)),
            primaryFestivalHex: hex,
            todaysEventsCount: 6,
            completedCount: 4,
            hasFestival: !fes.isEmpty,
            topTitles: (0..<3).map { i in
                WidgetTodoTitle(
                    id: UUID().uuidString,
                    title: [NSLocalizedString("晨读 30 分钟", comment: ""), NSLocalizedString("提交周报", comment: ""), NSLocalizedString("给妈妈打电话", comment: "")][i],
                    isCompleted: i == 0,
                    priorityHex: ["#C41A1A", "#2563EB", "#D97706"][i]
                )
            }
        )
    }

    /// 单条快照（Widget Gallery 预览）
    public func getSnapshot(in context: Context, completion: @escaping (LunisolarWidgetEntry) -> Void) {
        let day = Calendar(identifier: .gregorian).startOfDay(for: Date())
        completion(makeEntry(for: day,
                             daySnapshot: WidgetSnapshotStore.daySnapshot(for: day, appGroupID: appGroupID)))
    }

    /// 完整 Timeline：今日 + 未来 7 天，每天一条
    public func getTimeline(in context: Context, completion: @escaping (Timeline<LunisolarWidgetEntry>) -> Void) {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())

        // 一次读取整份快照（逐日窗口），时间线里每条 entry 都取真实数据。
        // 旧实现只让 dayOffset == 0 读快照、其余 7 天硬编码为 0 —— 过午夜小组件
        // 切到「明天」那条 entry 时就会显示 0/0 与「今日还没安排」。
        let snapshot = WidgetSnapshotStore.read(appGroupID: appGroupID)

        var entries: [LunisolarWidgetEntry] = []
        for dayOffset in 0..<WidgetSnapshotStore.windowDays {
            guard let d = cal.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            entries.append(makeEntry(for: d, daySnapshot: snapshot?.day(for: d)))
        }

        // 下一次刷新：明天 00:05（确保不跟系统午夜高峰抢）
        let nextRefresh: Date = {
            var comps = DateComponents()
            comps.day = 1
            comps.hour = 0
            comps.minute = 5
            return cal.date(byAdding: comps, to: today) ?? today.addingTimeInterval(86400)
        }()
        completion(Timeline(entries: entries, policy: .after(nextRefresh)))
    }

    // MARK: - 组装单条 Entry

    /// - Parameter daySnapshot: 该日在共享快照窗口内的待办统计；不在窗口内时（App 已超过
    ///   窗口天数没运行过）为 nil，此时待办计数回退为 0。
    private func makeEntry(for day: Date, daySnapshot: WidgetDaySnapshot?) -> LunisolarWidgetEntry {
        let r = HuangliDBProvider.resolve(date: day)
        // P2 优化：复用同一次农历转换，避免 festivals + primaryFestival 各转一次
        let lunar = ChineseCalendar.lunarDateSafe(from: day)
        let fes = FestivalManager.festivals(on: day, lunar: lunar)
        let hex = FestivalManager.primaryFestival(on: day, lunar: lunar)?.accentHex ?? "#C41A1A"

        return LunisolarWidgetEntry(
            date: day,
            huangli: r.huangliDay,
            lunar: r.huangliDay?.lunar,
            festivals: Array(fes.prefix(2)),
            primaryFestivalHex: hex,
            todaysEventsCount: daySnapshot?.eventsCount ?? 0,
            completedCount: daySnapshot?.completedCount ?? 0,
            hasFestival: !fes.isEmpty,
            topTitles: daySnapshot?.topTitles ?? [],
            // 该日不在快照窗口内（App 已超过窗口天数未运行）→ UI 如实显示未知，
            // 而不是把 nil 当 0 谎报「今日还没安排」
            hasTodoData: daySnapshot != nil
        )
    }
}
#endif
