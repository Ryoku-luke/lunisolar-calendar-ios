import Foundation

// MARK: - 无障碍标识目录（Accessibility Identifier）

/// 关键交互元素的稳定无障碍标识。
/// - VoiceOver：配合 accessibilityLabel 提供可读名称；
/// - 未来 XCUITest：用这些稳定 ID 定位元素，避免硬编码字符串漂移。
/// 命名规范：`模块.元素.动作`，全部小写、点分。
public enum AccessibilityID {
    // 月视图
    public static let monthNewEvent = "calendar.month.new"
    public static let todayJump = "calendar.month.today"
    public static let selectedSummary = "calendar.selected.summary"
    // 日详情
    public static let dayDetailNewEvent = "calendar.day.detail.new"
    // 编辑页
    public static let editSave = "event.edit.save"
    public static let editDelete = "event.edit.delete"
    public static let editTitle = "event.edit.title"
    // AI 助手
    public static let aiInput = "ai.input.draft"
    public static let aiParse = "ai.input.parse"
    public static let aiConfirm = "ai.preview.confirm"
    public static let aiCancel = "ai.preview.cancel"
    // 设置页
    public static let settingsWeekStart = "settings.week.start"
    public static let settingsSyncToggle = "settings.sync.toggle"
    public static let settingsSyncStatus = "settings.sync.status"
    // iPad 侧栏（SwiftUI 的 List(selection:) 行在 XCUITest 里未必暴露成 Button，
    // 按标识定位才不会因元素类型变化而失配）
    public static let iPadSidebarCalendar = "ipad.sidebar.calendar"
    public static let iPadSidebarYear = "ipad.sidebar.year"
    public static let iPadSidebarAgenda = "ipad.sidebar.agenda"
    public static let iPadSidebarCountdown = "ipad.sidebar.countdown"
    public static let iPadSidebarSettings = "ipad.sidebar.settings"

    /// 月历网格中的某一天（**动态**标识：同一天在网格里只有一格）。
    ///
    /// 为什么编成 `y2026m09d06` 这种单段：命名规范只允许小写字母与数字的分段
    /// （见 `AccessibilityIDTests.testAllIDsFollowNamingConvention`），
    /// 连字符（`2026-09-06`）和纯数字分段（`20260906`）都不合法。
    public static func monthDay(year: Int, month: Int, day: Int) -> String {
        String(format: "calendar.month.day.y%04dm%02dd%02d", year, month, day)
    }

    /// 全部**静态**标识（供测试校验非空 / 唯一 / 命名规范）。
    /// 动态标识（`monthDay`）无法枚举，由 `monthDayFormatIsStable` 单独锁定格式。
    public static let all: [String] = [
        monthNewEvent, todayJump, selectedSummary,
        dayDetailNewEvent,
        editSave, editDelete, editTitle,
        aiInput, aiParse, aiConfirm, aiCancel,
        settingsWeekStart, settingsSyncToggle, settingsSyncStatus,
        iPadSidebarCalendar, iPadSidebarYear, iPadSidebarAgenda,
        iPadSidebarCountdown, iPadSidebarSettings
    ]
}
