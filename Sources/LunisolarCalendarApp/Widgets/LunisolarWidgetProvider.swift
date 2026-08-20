#if canImport(WidgetKit)
import WidgetKit
import SwiftUI
import Foundation

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
    public let snapshotUpdatedAt: Date?   // 共享快照生成时间（供调试文案）

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
        snapshotUpdatedAt: Date? = nil
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
        self.snapshotUpdatedAt = snapshotUpdatedAt
    }

    /// 进度百分比 0...1 (用于待办小组件)
    public var progress: Double {
        guard todaysEventsCount > 0 else { return 0 }
        return min(1.0, Double(completedCount) / Double(todaysEventsCount))
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
        let fes = FestivalManager.festivals(on: now)
        let hex = FestivalManager.primaryFestival(on: now)?.accentHex ?? "#C41A1A"
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
                    title: ["晨读 30 分钟", "提交周报", "给妈妈打电话"][i],
                    isCompleted: i == 0,
                    priorityHex: ["#C41A1A", "#2563EB", "#D97706"][i]
                )
            }
        )
    }

    /// 单条快照（Widget Gallery 预览）
    public func getSnapshot(in context: Context, completion: @escaping (LunisolarWidgetEntry) -> Void) {
        completion(makeEntry(for: Date(), useSharedSnapshot: true))
    }

    /// 完整 Timeline：今日 + 未来 7 天，每天一条
    public func getTimeline(in context: Context, completion: @escaping (Timeline<LunisolarWidgetEntry>) -> Void) {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())

        var entries: [LunisolarWidgetEntry] = []
        for dayOffset in 0..<8 {
            guard let d = cal.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            // 仅"今天"尝试从主 App 共享快照读真实数据
            entries.append(makeEntry(for: d, useSharedSnapshot: dayOffset == 0))
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

    private func makeEntry(for day: Date, useSharedSnapshot: Bool) -> LunisolarWidgetEntry {
        let r = HuangliDBProvider.resolve(date: day)
        let fes = FestivalManager.festivals(on: day)
        let hex = FestivalManager.primaryFestival(on: day)?.accentHex ?? "#C41A1A"

        if useSharedSnapshot,
           let snap = WidgetSnapshotStore.read(appGroupID: appGroupID) {
            return LunisolarWidgetEntry(
                date: day,
                huangli: r.huangliDay,
                lunar: r.huangliDay?.lunar,
                festivals: Array(fes.prefix(2)),
                primaryFestivalHex: hex,
                todaysEventsCount: snap.todaysEventsCount,
                completedCount: snap.todaysCompletedCount,
                hasFestival: !fes.isEmpty,
                topTitles: snap.topTitles,
                snapshotUpdatedAt: snap.updatedAt
            )
        }
        return LunisolarWidgetEntry(
            date: day,
            huangli: r.huangliDay,
            lunar: r.huangliDay?.lunar,
            festivals: Array(fes.prefix(2)),
            primaryFestivalHex: hex,
            todaysEventsCount: 0,
            completedCount: 0,
            hasFestival: !fes.isEmpty
        )
    }
}

// MARK: - Widget Kind

public enum LunisolarWidgetKind: String, CaseIterable, Sendable {
    case huangliOverview      // ① 今日黄历概览（宜忌+冲煞）
    case lunarCard            // ② 农历日期卡片（月日+节日）
    case todoProgress         // ③ 今日待办进度
}
#endif
