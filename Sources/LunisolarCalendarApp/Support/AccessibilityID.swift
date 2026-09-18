import Foundation

// MARK: - 无障碍标识目录（Accessibility Identifier）

/// 关键交互元素的稳定无障碍标识。
/// - VoiceOver：配合 accessibilityLabel 提供可读名称；
/// - 未来 XCUITest：用这些稳定 ID 定位元素，避免硬编码字符串漂移。
/// 命名规范：`模块.元素.动作`，全部小写、点分。
public enum AccessibilityID {
    // 月视图
    public static let monthNewEvent = "calendar.month.newEvent"
    public static let todayJump = "calendar.month.today"
    // 日详情
    public static let dayDetailNewEvent = "calendar.dayDetail.newEvent"
    // 编辑页
    public static let editSave = "eventEdit.save"
    public static let editDelete = "eventEdit.delete"
    // 设置页
    public static let settingsWeekStart = "settings.weekStart"

    /// 全部标识（供测试校验非空 / 唯一 / 命名规范）
    public static let all: [String] = [
        monthNewEvent, todayJump,
        dayDetailNewEvent,
        editSave, editDelete,
        settingsWeekStart
    ]
}
