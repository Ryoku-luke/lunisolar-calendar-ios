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

    public init(
        date: Date,
        huangli: HuangliDay?,
        lunar: LunarDate?,
        festivals: [Festival],
        primaryFestivalHex: String,
        todaysEventsCount: Int,
        completedCount: Int,
        hasFestival: Bool
    ) {
        self.date = date
        self.huangli = huangli
        self.lunar = lunar
        self.festivals = festivals
        self.primaryFestivalHex = primaryFestivalHex
        self.todaysEventsCount = todaysEventsCount
        self.completedCount = completedCount
        self.hasFestival = hasFestival
    }

    /// 进度百分比 0...1 (用于待办小组件)
    public var progress: Double {
        guard todaysEventsCount > 0 else { return 0 }
        return min(1.0, Double(completedCount) / Double(todaysEventsCount))
    }
}

// MARK: - 通用 Timeline Provider（生成今天和未来 7 天的 Entry）

/// Provider 策略：
/// - 生成"今日午夜 + 未来 7 天"的快照（农历/黄历/节日不依赖用户数据，无需刷新太勤）
/// - policy: .afterMidnight（每天 00:00 自动换）
/// - WidgetExtension 中只需要把 EventStore 持久化结果传给 todayEventsCount
public struct LunisolarWidgetTimelineProvider: TimelineProvider {
    public typealias Entry = LunisolarWidgetEntry

    public init() {}

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
            hasFestival: !fes.isEmpty
        )
    }

    /// 单条快照（Widget Gallery 预览）
    public func getSnapshot(in context: Context, completion: @escaping (LunisolarWidgetEntry) -> Void) {
        completion(placeholder(in: context))
    }

    /// 完整 Timeline：今日 + 未来 7 天，每天一条
    public func getTimeline(in context: Context, completion: @escaping (Timeline<LunisolarWidgetEntry>) -> Void) {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())

        var entries: [LunisolarWidgetEntry] = []
        for dayOffset in 0..<8 {
            guard let d = cal.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            let r = HuangliDBProvider.resolve(date: d)
            let fes = FestivalManager.festivals(on: d)
            let hex = FestivalManager.primaryFestival(on: d)?.accentHex ?? "#C41A1A"
            entries.append(
                LunisolarWidgetEntry(
                    date: d,
                    huangli: r.huangliDay,
                    lunar: r.huangliDay?.lunar,
                    festivals: Array(fes.prefix(2)),
                    primaryFestivalHex: hex,
                    todaysEventsCount: 0,
                    completedCount: 0,
                    hasFestival: !fes.isEmpty
                )
            )
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
}

// MARK: - Widget Kind

public enum LunisolarWidgetKind: String, CaseIterable, Sendable {
    case huangliOverview      // ① 今日黄历概览（宜忌+冲煞）
    case lunarCard            // ② 农历日期卡片（月日+节日）
    case todoProgress         // ③ 今日待办进度
}
#endif
