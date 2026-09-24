import Foundation
// LiveActivityIntent 仅 iOS 17+ 可用（macOS/watchOS/tvOS 均标记 unavailable），
// 因此整份文件按平台守卫。
#if canImport(AppIntents) && !os(macOS)
import AppIntents

// MARK: - 灵动岛「稍后提醒」动作（docs #26）
//
// 展开态按钮：Button(intent:) + LiveActivityIntent。
// LiveActivityIntent 的 perform() 在**主 App 进程**执行（不是扩展进程），
// 因此可以直接调用 NotificationManager：挂一条 10 分钟后触发的一次性通知，
// **不修改事件本身的时间**（避免"稍后提醒"把用户日程挪走）。
//
// 约束：本类型由主 App 与 Widget 扩展共同编译（扩展负责渲染按钮、解析 intent），
// 因此不得引用仅 App 侧才存在的运行时状态。

@available(iOS 17.0, *)
public struct SnoozeReminderIntent: LiveActivityIntent {
    // 用 static let 满足 AppIntent 的 { get } 要求，同时避免 Swift 6
    // 对"nonisolated 可变全局状态"的诊断（static var 会报 MutableGlobalVariable）
    public static let title: LocalizedStringResource = "稍后提醒"
    public static let description: IntentDescription? = IntentDescription("10 分钟后再提醒一次")

    @Parameter(title: "事件 ID")
    public var eventID: String

    public init() {}

    public init(eventID: String) {
        self.eventID = eventID
    }

    public func perform() async throws -> some IntentResult {
        // 失败（事件已不存在 / 无通知权限）时不抛错——灵动岛按钮失败不应造成系统级报错，
        // 具体原因由 NotificationManager 记入日志。
        _ = await NotificationManager.shared.snoozeReminder(eventID: eventID)
        return .result()
    }
}

#endif
