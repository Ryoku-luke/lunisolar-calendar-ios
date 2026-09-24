#if canImport(ActivityKit) && canImport(WidgetKit) && !os(macOS)
// @preconcurrency：iOS 26 SDK 中 Activity 类型实例（来自 @MainActor 的
// `Activity.activities`）传给 @concurrent 的 `end(_:dismissalPolicy:)` 时，
// Swift 6 严格并发会报 "Sending 'activity' risks causing data races"。
// 该类型为系统框架类型且生命周期由系统托管，@preconcurrency import 是
// Swift 6 迁移对系统框架的标准放宽手段。
@preconcurrency import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - 灵动岛 · 倒计时 Live Activity
//
// iOS 16.1+ Live Activities：把「倒数日 / 纪念日」挂到灵动岛与锁屏。
// 剩余时间用系统原生 `Text(date, style: .timer)` 渲染，由系统每秒自动刷新，
// App 无需常驻计时器（零后台耗电、零 Timer 泄漏）。
//
// ⚠️ iOS 26/27 SDK（Xcode 26+）API 变更适配：
// 1. `ActivityAttributes.ContentState` 必须直接命名为嵌套类型 `ContentState`，
//    不能再通过 `typealias ContentState = XxxContentState` 满足协议（否则
//    "does not conform to protocol 'ActivityAttributes'"）。
// 2. `ActivityConfiguration` 新签名 `for:content:dynamicIsland:`——第一个闭包
//    是锁屏/配对手表卡（label: `content`），第二个是 `dynamicIsland:` 闭包，
//    返回 `DynamicIsland { } compactLeading: { } compactTrailing: { } minimal: { }`；
//    旧的独立 `lockScreen:` 标签已被移除。
//
// 本文件位于 Widgets/ 共享目录，主 App target 与 Widget 扩展 target 同时编译：
// - Widget 扩展：注册 ActivityConfiguration 负责灵动岛/锁屏渲染
// - 主 App：CountdownActivityManager 负责开启 / 结束 / 恢复活动

@available(iOS 16.1, *)
public struct CountdownActivityAttributes: ActivityAttributes {
    /// 渲染状态：结束时间（倒计时终点）；系统按 staleDate 提示刷新
    public struct ContentState: Codable, Hashable, Sendable {
        public var endDate: Date
        public init(endDate: Date) { self.endDate = endDate }
    }

    public var eventID: UUID
    public var title: String
    public var emoji: String

    public init(eventID: UUID, title: String, emoji: String) {
        self.eventID = eventID
        self.title = title
        self.emoji = emoji
    }
}

// MARK: - 锁屏 / 配对手表卡渲染

@available(iOS 16.1, *)
struct CountdownLiveActivityView: View {
    let context: ActivityViewContext<CountdownActivityAttributes>

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            // 自定义 emoji 图标：独创性 —— 用户选择的倒数日图标直接上岛
            Text(context.attributes.emoji)
                .font(.system(size: 26, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(Color.themeQuaternaryFill)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(String(format: NSLocalizedString("倒计时 · %@", comment: ""), context.state.endDate.formatted(.dateTime.month().day())))
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }

            Spacer(minLength: 8)

            // 系统原生倒计时样式：每秒自动刷新、monospaced 防跳动
            Text(context.state.endDate, style: .timer)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
        }
        .padding(.horizontal)
        .padding(.vertical, AppTheme.Spacing.sm)
        // P1：点锁屏卡 → 打开 App 直达该倒数日
        .widgetURL(URL(string: "qinghe://event/\(context.attributes.eventID.uuidString)"))
    }
}

/// 灵动岛 / 锁屏注册（WidgetBundle 成员）
@available(iOS 16.1, *)
public struct CountdownLiveActivityWidget: Widget {
    public let kind: String = "CountdownLiveActivity"

    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: CountdownActivityAttributes.self) { context in
            // 锁屏完整卡片 / 配对手表 macOS（iOS 26 的 content 闭包）
            CountdownLiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // 展开态：点击空白处也深链到对应倒数日
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.emoji)
                        .font(.system(size: 22, weight: .semibold))
                        .padding(7)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.9))
                        )
                        .widgetURL(URL(string: "qinghe://event/\(context.attributes.eventID.uuidString)"))
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text(context.state.endDate.formatted(.dateTime.month(.twoDigits).day(.twoDigits)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .widgetURL(URL(string: "qinghe://event/\(context.attributes.eventID.uuidString)"))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    // 系统原生倒计时：每秒自动刷新、monospaced 防跳动
                    Text(context.state.endDate, style: .timer)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .widgetURL(URL(string: "qinghe://event/\(context.attributes.eventID.uuidString)"))
                }
            } compactLeading: {
                // 紧凑态（左侧）：emoji + 纯黑圆角底，边缘干净不露液态玻璃杂色
                Text(context.attributes.emoji)
                    .font(.system(size: 18, weight: .semibold))
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black.opacity(0.9))
                    )
            } compactTrailing: {
                // 紧凑态（右侧）：仅剩余时间（灵动岛紧凑区建议"一元素一数字"）
                Text(context.state.endDate, style: .timer)
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .monospacedDigit()
            } minimal: {
                // 最小态（与其他活动并排时）：仅 emoji 图标
                Text(context.attributes.emoji)
                    .font(.system(size: 16, weight: .semibold))
                    .padding(3)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.black.opacity(0.9))
                    )
            }
            .keylineTint(Color(red: 0.30, green: 0.55, blue: 0.52))
        }
        // ⚠️ 不调用 .contentMarginsDisabled()：iOS 26 液态玻璃灵动岛默认自带
        // 安全边距，内容贴边反而显得更宽更满；保留边距让展开态观感更克制。
    }
}

// MARK: - 主 App 侧管理（开启 / 结束 / 恢复）

@available(iOS 16.1, *)
@MainActor
public enum CountdownActivityManager {
    /// [eventID.uuidString : activityID]，跨启动恢复用
    private static let idsKey = "Lunisolar.liveActivity.ids"

    /// 为某个倒数日启动灵动岛活动（新建/编辑保存时自动调用）。
    /// 幂等：事件已在岛上且标题/图标/日期都未变 → 直接复用，不重启（避免编辑时活动闪烁）。
    /// 重建时「先上新、后撤旧」：新活动 request 成功后再结束旧活动，
    /// 避免旧活动先行消失导致的上岛失败窗口与视觉抖动。
    @discardableResult
    public static func start(event: CountdownEvent) -> Result<String, Error> {
        // 幂等复用：关键内容未变 → 保持现有活动原样
        if let oldID = activeActivityID(for: event.id),
           let old = Activity<CountdownActivityAttributes>.activities.first(where: { $0.id == oldID }),
           old.attributes.title == event.title,
           old.attributes.emoji == event.emoji,
           old.content.state.endDate == event.date {
            return .success(oldID)
        }
        let attrs = CountdownActivityAttributes(eventID: event.id,
                                                title: event.title,
                                                emoji: event.emoji)
        let state = CountdownActivityAttributes.ContentState(endDate: event.date)
        let content = ActivityContent(state: state, staleDate: event.date)
        do {
            let activity = try Activity<CountdownActivityAttributes>.request(
                attributes: attrs,
                content: content
            )
            // 新活动已上岛 → 再撤同事件旧活动（若有）
            if let oldID = UserDefaults.standard.dictionary(forKey: idsKey)?[event.id.uuidString] as? String,
               oldID != activity.id {
                end(id: oldID)
            }
            save(activityID: activity.id, for: event.id)
            return .success(activity.id)
        } catch {
            // request 失败时旧活动原样保留，不丢失
            return .failure(error)
        }
    }

    /// 结束指定活动（立即撤离灵动岛）
    public static func end(id: String) {
        guard let activity = Activity<CountdownActivityAttributes>.activities
            .first(where: { $0.id == id }) else { return }
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// 当前是否已有该事件的活跃活动
    public static func activeActivityID(for eventID: UUID) -> String? {
        let dict = UserDefaults.standard.dictionary(forKey: idsKey) as? [String: String] ?? [:]
        guard let id = dict[eventID.uuidString] else { return nil }
        // 若系统已结束该活动（用户从灵动岛手动移除等），清除记录
        if Activity<CountdownActivityAttributes>.activities.contains(where: { $0.id == id }) {
            return id
        } else {
            remove(eventID: eventID)
            return nil
        }
    }

    /// 结束某事件对应的活动（若在岛上）
    public static func end(for eventID: UUID) {
        if let id = activeActivityID(for: eventID) {
            end(id: id)
        }
        remove(eventID: eventID)
    }

    /// 启动兜底：清理「事件已不存在但活动仍在岛上」的孤儿活动。
    /// 覆盖所有删除路径（即使某处删除时漏调 end，下次启动也会自动下岛）。
    public static func cleanupOrphans(validEventIDs: Set<UUID>) {
        var dict = UserDefaults.standard.dictionary(forKey: idsKey) as? [String: String] ?? [:]
        for (idString, activityID) in dict {
            guard let eventID = UUID(uuidString: idString) else {
                // 单条记录损坏：只删这一条，不影响其他正常上岛的倒数日
                dict.removeValue(forKey: idString)
                continue
            }
            // 事件已删除，或系统已结束该活动 → 清理记录
            if !validEventIDs.contains(eventID)
                || !Activity<CountdownActivityAttributes>.activities.contains(where: { $0.id == activityID }) {
                if !validEventIDs.contains(eventID) {
                    end(id: activityID)  // 结束幽灵活动
                }
                dict.removeValue(forKey: idString)
            }
        }
        UserDefaults.standard.set(dict, forKey: idsKey)
    }

    // MARK: 内部

    private static func save(activityID: String, for eventID: UUID) {
        var dict = UserDefaults.standard.dictionary(forKey: idsKey) as? [String: String] ?? [:]
        dict[eventID.uuidString] = activityID
        UserDefaults.standard.set(dict, forKey: idsKey)
    }

    private static func remove(eventID: UUID) {
        var dict = UserDefaults.standard.dictionary(forKey: idsKey) as? [String: String] ?? [:]
        dict.removeValue(forKey: eventID.uuidString)
        UserDefaults.standard.set(dict, forKey: idsKey)
    }
}

#endif
