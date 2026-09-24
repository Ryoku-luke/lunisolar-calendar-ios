import Foundation
import Observation
import SwiftUI

// MARK: - 全局导航状态（P0-2）
//
// 统一管理 iPhone Tab / iPad Sidebar / 选中日期，避免两个 Root 各自维护 selectedDate
// 导致跨 Tab 不同步。后续 DeepLink / Widget / 通知 / Live Activity 都通过它跳转。

@Observable
@MainActor
public final class NavigationCoordinator {
    public static let shared = NavigationCoordinator()

    /// 当前选中日期（日历 Tab ↔ 黄历 Tab ↔ iPad detail 共享）
    public var selectedDate: Date = Date()

    /// iPhone 底部 Tab 选中
    public enum PhoneTab: Hashable { case calendar, huangli, ai, me }
    public var phoneTab: PhoneTab = .calendar

    /// iPad Sidebar 选中（List(selection:) 需要 optional binding）
    public enum iPadSection: Hashable { case calendar, year, countdown, settings }
    public var iPadSection: iPadSection? = .calendar

    /// AI 助手弹层
    public var showAI: Bool = false

    /// P1：待打开的事件详情 ID（深链 / 通知 / Live Activity 点击设置）。
    /// CalendarMonthView 监听此字段并 sheet 出 EventEditView；消费后置 nil。
    public var pendingOpenEventID: UUID?

    /// P1：待打开的倒数日 ID（倒数日 / 纪念日 Live Activity 卡片 → qinghe://countdown/<UUID>）。
    /// CalendarMonthView 监听并 sheet 出 CountdownView；消费后置 nil。
    public var pendingOpenCountdownID: UUID?

    private init() {}

    /// 跳转到指定日期（跨 Tab / 跨平台统一入口）
    public func showDate(_ date: Date) {
        selectedDate = date
    }

    /// 切换到日历 Tab 并显示指定事件日期
    public func openEventDate(_ date: Date) {
        selectedDate = date
        #if os(iOS)
        phoneTab = .calendar
        #endif
    }

    /// P1：直接打开某事件的详情编辑页（深链 qinghe://event/<UUID> 专用）
    public func openEventDetail(_ id: UUID) {
        pendingOpenEventID = id
        #if os(iOS)
        phoneTab = .calendar
        #endif
        // iPad：事件属于日历节，同步切换侧栏，保证中间栏能看到它
        // （显式 self.：属性名与枚举 NavigationCoordinator.iPadSection 同名）
        self.iPadSection = .calendar
    }

    /// P1：打开倒数日列表并聚焦指定条目（倒数日卡片点击 → qinghe://countdown/<UUID> 专用）。
    /// iPhone 上倒数日入口在「日历」Tab 的工具栏菜单里，故先切到该 Tab；
    /// iPad 上直接切到侧栏的「倒数日」节。
    public func openCountdownDetail(_ id: UUID) {
        pendingOpenCountdownID = id
        #if os(iOS)
        phoneTab = .calendar
        #endif
        self.iPadSection = .countdown
    }
}
