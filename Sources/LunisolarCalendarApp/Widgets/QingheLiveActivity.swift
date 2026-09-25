#if canImport(ActivityKit) && canImport(WidgetKit) && !os(macOS)
// @preconcurrency：同 CountdownActivity.swift —— iOS 26/27 SDK 中
// `Activity.activities` 传入 @concurrent 闭包时 Swift 6 严格并发需要系统框架放宽。
@preconcurrency import ActivityKit
import SwiftUI
import WidgetKit
// AppLogger 的字符串插值定义在 module `os` 内，显式引入避免 SDK 组合差异
#if canImport(os)
import os
#endif

// MARK: - 清和时间胶囊 · 通用 Live Activity（文档 #20-33）
//
// 与 CountdownActivity（倒数日/纪念日专用）的区别与分工：
// - CountdownActivityManager：用户「手动添加倒数日」后常驻灵动岛（countdown/anniversary）；
// - QingheLiveActivityManager：自动挑选「当前最值得关注的时间事件」上岛
//   （高优先级提醒、高优先级日程；节气短生命周期活动预留）。
// 两套事件域不重叠（CountdownEvent ≠ CalendarEvent），不会同时抢同一个事件。
//
// 决策链（文档 #24）：EventService → QingheActivityCoordinator →
// QingheLiveActivityManager → ActivityKit。
// EventStore 不直接调用 ActivityKit。

// MARK: - Attributes（文档 #23，适配 iOS 26/27：ContentState 必须为嵌套命名类型）

@available(iOS 16.1, *)
public struct QingheLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var phase: QingheActivityPhase
        public var title: String
        public var subtitle: String?
        public var startDate: Date?
        public var endDate: Date?
        public var eventType: QingheActivityType
        public var icon: String
        public var countdownTarget: Date?
        public var isImportant: Bool

        public init(phase: QingheActivityPhase, title: String, subtitle: String?,
                    startDate: Date?, endDate: Date?, eventType: QingheActivityType,
                    icon: String, countdownTarget: Date?, isImportant: Bool) {
            self.phase = phase
            self.title = title
            self.subtitle = subtitle
            self.startDate = startDate
            self.endDate = endDate
            self.eventType = eventType
            self.icon = icon
            self.countdownTarget = countdownTarget
            self.isImportant = isImportant
        }
    }

    public var activityID: String
    public var eventID: String?
    public var title: String
    public var createdAt: Date

    public init(activityID: String, eventID: String?, title: String, createdAt: Date) {
        self.activityID = activityID
        self.eventID = eventID
        self.title = title
        self.createdAt = createdAt
    }
}

// MARK: - 锁屏 / 配对手表卡渲染

@available(iOS 16.1, *)
struct QingheLiveActivityLockScreenView: View {
    let context: ActivityViewContext<QingheLiveActivityAttributes>

    private var state: QingheLiveActivityAttributes.ContentState { context.state }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            // 图标（纯黑圆角底，与 Countdown 一致避免液态玻璃杂色）
            // ⚠️ state.icon 是 SF Symbol 名（如 "bell.fill"），必须 Image(systemName:) 渲染——
            // 曾用 Text(state.icon) 把符号名当文字直接显示在锁屏与灵动岛上。
            Image(systemName: state.icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.black.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(state.title)
                    .font(.headline)
                    .lineLimit(1)
                if let subtitle = state.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            // 剩余时间文案统一走 LiveActivityRemainingText（<1h 系统 timer / 1–24h 目标时刻 / ≥24h N天）
            if let target = state.countdownTarget {
                LiveActivityRemainingText.view(for: target)
                    .font(.system(.title3, design: .rounded).weight(.bold))
            } else if let start = state.startDate, start > Date() {
                LiveActivityRemainingText.view(for: start)
                    .font(.system(.title3, design: .rounded).weight(.bold))
            } else if let end = state.endDate {
                Text(end.formatted(.dateTime.month().day()))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, AppTheme.Spacing.sm)
        .widgetURL(URL(string: "qinghe://event/\(context.attributes.eventID ?? "")"))
    }
}

// MARK: - 灵动岛 / 锁屏注册（WidgetBundle 成员）

/// 通用时间胶囊 Live Activity：自动上岛（高优先级提醒/日程，节气短活动预留）。
@available(iOS 16.1, *)
public struct QingheLiveActivityWidget: Widget {
    public let kind: String = "QingheLiveActivity"

    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: QingheLiveActivityAttributes.self) { context in
            QingheLiveActivityLockScreenView(context: context)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                // 展开态：左侧图标 | 中部标题+副题 | 右侧时间
                DynamicIslandExpandedRegion(.leading) {
                    // SF Symbol 必须 Image(systemName:)；黑底 → 显式白色保证对比度
                    Image(systemName: state.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(7)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.9))
                        )
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        if let subtitle = state.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else if let end = state.endDate {
                            Text(end.formatted(.dateTime.month(.twoDigits).day(.twoDigits)))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    // docs #26：右侧只放"时间"一类信息，不重复中心的日期。
                    // 剩余时间文案统一走 LiveActivityRemainingText（同目录）：
                    // <1h 系统 timer、1–24h 显示目标时刻、≥24h 显示「N天」——既简短又不会过期。
                    if let target = state.countdownTarget {
                        LiveActivityRemainingText.view(for: target)
                            .font(.system(.title2, design: .rounded).weight(.bold))
                    } else if let start = state.startDate, start > Date() {
                        LiveActivityRemainingText.view(for: start)
                            .font(.system(.title2, design: .rounded).weight(.bold))
                    } else if let end = state.endDate {
                        // 进行中：显示结束时刻
                        Text(end.formatted(.dateTime.hour().minute()))
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .monospacedDigit()
                    }
                }
                // docs #26：展开态给出显式动作（查看日历 / 稍后提醒）
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: AppTheme.Spacing.lg) {
                        if let eventID = context.attributes.eventID {
                            Text(NSLocalizedString("打开日历 ›", comment: "Live Activity 动作"))
                                .font(.caption2.weight(.semibold))
                                .widgetURL(URL(string: "qinghe://event/\(eventID)"))
                        }
                        Spacer(minLength: 0)
                        if #available(iOS 17.0, *), let eventID = context.attributes.eventID {
                            // LiveActivityIntent 在主 App 进程执行：挂一条 10 分钟后的一次性通知
                            Button(intent: SnoozeReminderIntent(eventID: eventID)) {
                                Text(NSLocalizedString("稍后提醒", comment: "Live Activity 动作"))
                                    .font(.caption2.weight(.semibold))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    // iOS 26 展开态底部区域紧贴灵动岛圆角：不内缩时首尾字符会被圆角裁掉
                    // （真机现象：首字与末字各缺一半）
                    .padding(.horizontal, 16)
                }
            } compactLeading: {
                // 紧凑态（左侧）：图标 + 纯黑圆角底（SF Symbol → Image）
                Image(systemName: state.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black.opacity(0.9))
                    )
            } compactTrailing: {
                // 紧凑态（右侧）：只放"剩余时间"（docs #26），统一走 LiveActivityRemainingText
                if let target = state.countdownTarget {
                    LiveActivityRemainingText.view(for: target)
                        .font(.system(.caption, design: .rounded).weight(.bold))
                } else if let start = state.startDate, start > Date() {
                    LiveActivityRemainingText.view(for: start)
                        .font(.system(.caption, design: .rounded).weight(.bold))
                } else if let end = state.endDate {
                    Text(end.formatted(.dateTime.hour().minute()))
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .monospacedDigit()
                }
            } minimal: {
                // 最小态：仅图标（SF Symbol → Image）
                Image(systemName: state.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(3)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.black.opacity(0.9))
                    )
            }
            .keylineTint(Color(red: 0.30, green: 0.55, blue: 0.52))
        }
    }
}

// MARK: - 主 App 侧管理（开启 / 更新 / 结束 / 恢复）

@available(iOS 16.1, *)
@MainActor
public enum QingheLiveActivityManager {
    /// 时间胶囊当前活动 ID 的存储键（全局单例：同一时间只维护一个主要时间胶囊）
    private static let idsKey = "Lunisolar.timeCapsule.activityID"

    /// 类型 → SF Symbol 图标（文档 #26：compactLeading 只显示图标）
    public static func icon(for type: QingheActivityType) -> String {
        switch type {
        case .event:       return "calendar.badge.exclamationmark"
        case .reminder:    return "bell.fill"
        case .countdown:   return "hourglass"
        case .anniversary: return "gift.fill"
        case .solarTerm:   return "sun.horizon.fill"
        }
    }

    /// 与目标内容同步灵动岛：决策 → 执行（start / update / end / none）。
    /// 调用方（EventService 事件变更后 / App 启动与回到前台）传入
    /// `EventService.timeCapsuleCandidate()` 与事件展示信息。
    @discardableResult
    public static func sync(target: QingheTimeCapsuleDisplay?) -> Result<String, Error> {
        let current = currentDisplay()

        switch QingheLiveActivityLifecycle.decision(current: current, target: target) {
        case .none:
            if let eventID = current?.eventID {
                return .success(eventID.uuidString)
            }
            return .failure(NSError(domain: "QingheLiveActivity", code: 0))
        case .end:
            // ⚠️ 不能只下岛：决策为 .end 有两种来源——target 为 nil（确实没有候选了），
            // 或 current/target 是**不同事件**（切换候选）。后者的契约由
            // QingheLiveActivityLifecycle 写明「调用方负责撤掉旧活动」，
            // 此前只 end 就返回，新候选被静默丢弃 → 岛上留空白直到下一次 refresh()
            // （用户把当前上岛的提醒标记完成 / 改期后，看不到下一个该上岛的日程）。
            guard let target else {
                endCurrent()
                return .failure(NSError(domain: "QingheLiveActivity", code: 1,
                                        userInfo: [NSLocalizedDescriptionKey: "ended"]))
            }
            // 切换候选走「先上新、后撤旧」，与 CountdownActivityManager.start 的既定顺序一致。
            // 反过来做（先撤旧再上新）时旧的 end 是异步的，新活动 request 会落进「旧活动仍然存活」
            // 的窗口里：轻则两颗活动短暂并存，重则 request 被系统拒绝 → 用户看到「切换后不上岛」。
            // 旧 id 必须先留一手：start 成功后会把记录覆盖成新 id，之后就没法再定位旧活动了。
            let previousID = UserDefaults.standard.string(forKey: idsKey)
            let result = start(display: target)
            // 只有新活动确实起来了才撤旧的。request 失败则旧活动原样保留（记录也没被改写），
            // 避免出现「旧的撤了、新的没上」的空岛。
            if case .success(let newID) = result, let previousID, previousID != newID {
                end(id: previousID)
            }
            return result
        case .start:
            return start(display: target!)
        case .update:
            guard let target else { return .failure(NSError(domain: "QingheLiveActivity", code: 2)) }
            return update(display: target)
        }
    }

    /// 新建时间胶囊活动。成功返回 activityID。
    private static func start(display: QingheTimeCapsuleDisplay) -> Result<String, Error> {
        let attrs = QingheLiveActivityAttributes(
            activityID: UUID().uuidString,
            eventID: display.eventID.uuidString,
            title: display.title,
            createdAt: Date()
        )
        let state = state(from: display)
        let content = ActivityContent(state: state, staleDate: staleDate(for: display))
        do {
            let activity = try Activity<QingheLiveActivityAttributes>.request(
                attributes: attrs,
                content: content
            )
            UserDefaults.standard.set(activity.id, forKey: idsKey)
            return .success(activity.id)
        } catch {
            return .failure(error)
        }
    }

    /// 同事件内容变化 → 就地更新（不重建，避免闪烁）。
    private static func update(display: QingheTimeCapsuleDisplay) -> Result<String, Error> {
        guard let id = UserDefaults.standard.string(forKey: idsKey),
              let activity = Activity<QingheLiveActivityAttributes>.activities
                .first(where: { $0.id == id && LiveActivityOccupancy.isShowing($0) }) else {
            // 记录里的活动已经不在岛上（系统收走 / 用户划掉）→ 更新它等于更新一个
            // 空气：屏幕上什么都不出现，却返回成功。必须改为重建。
            return start(display: display)
        }
        let state = state(from: display)
        let content = ActivityContent(state: state, staleDate: staleDate(for: display))
        Task {
            await activity.update(content)
        }
        return .success(id)
    }

    /// 结束当前时间胶囊活动（立即撤离灵动岛）。
    /// 会同时清掉记录——只有「确实不要任何时间胶囊了」才用它。
    /// 切换候选请用 `end(id:)`：那边必须先把新活动立起来再撤旧的。
    public static func endCurrent() {
        guard let id = UserDefaults.standard.string(forKey: idsKey) else { return }
        UserDefaults.standard.removeObject(forKey: idsKey)
        end(id: id)
    }

    /// 结束指定 id 的活动（不动 UserDefaults 记录）。
    /// 与 `start` 搭配时用于「先上新、后撤旧」：新活动已经接管记录，这里只负责撤旧实例。
    private static func end(id: String) {
        guard let activity = Activity<QingheLiveActivityAttributes>.activities
            .first(where: { $0.id == id }) else { return }
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// 从岛上活动的 attributes/content 还原当前显示快照（供 diff 决策）。
    /// 只认**仍在展示**的活动：已结束的残留若被当成 current，决策会落到 `.none`/`.update`，
    /// 于是永远不去重建 —— 屏幕上什么都没有，日志里也什么都没有。
    private static func currentDisplay() -> QingheTimeCapsuleDisplay? {
        guard let id = UserDefaults.standard.string(forKey: idsKey),
              let activity = Activity<QingheLiveActivityAttributes>.activities
                .first(where: { $0.id == id }) else {
            return nil
        }
        guard LiveActivityOccupancy.isShowing(activity) else {
            AppLogger.app.info("时间胶囊活动已不在岛上（系统收走或用户划掉），本次将重建")
            return nil
        }
        let attrs = activity.attributes
        let state = activity.content.state
        guard let eventIDString = attrs.eventID, let eventID = UUID(uuidString: eventIDString) else {
            return nil
        }
        return QingheTimeCapsuleDisplay(
            eventID: eventID,
            type: state.eventType,
            phase: state.phase,
            title: state.title,
            icon: state.icon,
            startDate: state.startDate ?? Date(),
            endDate: state.endDate,
            countdownTarget: state.countdownTarget,
            isImportant: state.isImportant
        )
    }

    /// staleDate 表示“内容可能过期”，不应设置为 upcoming 事件的 startDate，
    /// 否则事件刚开始就被系统标记为 stale。优先使用结束时间；无结束时间时给
    /// 当前活动一个保守的 2 小时生命周期。
    private static func staleDate(for display: QingheTimeCapsuleDisplay) -> Date {
        if let end = display.endDate, end > display.startDate {
            return end
        }
        return display.startDate.addingTimeInterval(2 * 3600)
    }

    private static func state(from display: QingheTimeCapsuleDisplay) -> QingheLiveActivityAttributes.ContentState {
        QingheLiveActivityAttributes.ContentState(
            phase: display.phase,
            title: display.title,
            subtitle: nil,
            startDate: display.startDate,
            endDate: display.endDate,
            eventType: display.type,
            icon: display.icon,
            countdownTarget: display.countdownTarget,
            isImportant: display.isImportant
        )
    }
}

// MARK: - Previews（Xcode 画布；iOS 17+ Widget Preview API，as: 需显式给 ActivityPreviewViewKind）

#Preview("锁屏卡 · 提醒", as: .content, using: QingheLiveActivityAttributes(
    activityID: "preview", eventID: UUID().uuidString, title: "时间胶囊", createdAt: Date()
)) {
    QingheLiveActivityWidget()
} contentStates: {
    QingheLiveActivityAttributes.ContentState(
        phase: .upcoming, title: "给妈妈打电话", subtitle: nil,
        startDate: Date().addingTimeInterval(30 * 60), endDate: Date().addingTimeInterval(60 * 60),
        eventType: .reminder, icon: "bell.fill", countdownTarget: nil, isImportant: true
    )
    QingheLiveActivityAttributes.ContentState(
        phase: .live, title: "给妈妈打电话", subtitle: "进行中",
        startDate: Date().addingTimeInterval(-5 * 60), endDate: Date().addingTimeInterval(25 * 60),
        eventType: .reminder, icon: "bell.fill", countdownTarget: nil, isImportant: true
    )
}

#Preview("灵动岛 · 提醒（紧凑）", as: .dynamicIsland(.compact), using: QingheLiveActivityAttributes(
    activityID: "preview", eventID: UUID().uuidString, title: "时间胶囊", createdAt: Date()
)) {
    QingheLiveActivityWidget()
} contentStates: {
    QingheLiveActivityAttributes.ContentState(
        phase: .upcoming, title: "给妈妈打电话", subtitle: nil,
        startDate: Date().addingTimeInterval(30 * 60), endDate: Date().addingTimeInterval(60 * 60),
        eventType: .reminder, icon: "bell.fill", countdownTarget: nil, isImportant: true
    )
}

#Preview("灵动岛 · 节气（展开）", as: .dynamicIsland(.expanded), using: QingheLiveActivityAttributes(
    activityID: "preview", eventID: UUID().uuidString, title: "时间胶囊", createdAt: Date()
)) {
    QingheLiveActivityWidget()
} contentStates: {
    QingheLiveActivityAttributes.ContentState(
        phase: .live, title: "白露已至", subtitle: nil,
        startDate: Date().addingTimeInterval(-30 * 60), endDate: Date().addingTimeInterval(90 * 60),
        eventType: .solarTerm, icon: "sun.horizon.fill",
        countdownTarget: Date().addingTimeInterval(90 * 60), isImportant: false
    )
}

#endif
