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
    /// 2026-09-27 批次 3：去掉 `.year`（年视图改走方案 C——移出侧栏，入口统一到
    /// 「跳转到日期 → 全年视图」，见 docs/IPAD_UI_DESIGN_2026-09-27.md 的 P0-1 裁决）；
    /// 新增 `.ai`（AI 助手原先只能从设置页头部卡进，入口埋两层深）。
    public enum iPadSection: Hashable { case calendar, ai, agenda, countdown, settings }
    public var iPadSection: iPadSection? = .calendar

    /// P1：待打开的事件详情 ID（深链 / 通知 / Live Activity 点击设置）。
    /// CalendarMonthView 监听此字段并 sheet 出 EventEditView；消费后置 nil。
    public var pendingOpenEventID: UUID?

    /// P1：待打开的倒数日 ID（倒数日 / 纪念日 Live Activity 卡片 → qinghe://countdown/<UUID>）。
    /// 消费方：iPhone 侧 CalendarMonthView（sheet 出 CountdownView），iPad 侧 iPadRootView
    /// （中栏的「倒数日」节高亮对应条目）。消费后置 nil。
    public var pendingOpenCountdownID: UUID?

    /// iPad 上下文 Inspector（§33/§36 裁决 2026-09-26）：倒数日节下右栏跟随的选中条目。
    /// 与 pendingOpenCountdownID 分工：那个只投递一次，这个是常驻选中状态。
    public var iPadCountdownSelection: UUID?

    private init() {}

    /// 切到日历入口（三个桌面小组件的 widgetURL `qinghe://calendar` 专用）
    public func openCalendar() {
        #if os(iOS)
        phoneTab = .calendar
        #endif
        self.iPadSection = .calendar
    }

    /// 打开 AI 助手（深链 `qinghe://ai`）。
    /// N-1 修复：iPad 侧栏已有 AI 节（2026-09-27 批次 3 新增 `.ai`），
    /// 旧实现只切 iPhone Tab、注释也停留在"iPad 没有 AI 节"的过时状态，
    /// 导致 iPad 上点 AI 深链无任何反应。现在双端同步切换。
    public func openAIAssistant() {
        #if os(iOS)
        phoneTab = .ai
        #endif
        self.iPadSection = .ai
    }

    /// 切换到日历 Tab 并显示指定事件日期
    public func openEventDate(_ date: Date) {
        selectedDate = date
        #if os(iOS)
        phoneTab = .calendar
        #endif
        // iPad：日期只在日历节可见，同步切侧栏（与 openEventDetail 一致）
        self.iPadSection = .calendar
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
