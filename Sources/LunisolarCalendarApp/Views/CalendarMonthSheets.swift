import SwiftUI

// MARK: - CalendarMonthView 的 sheet 收口
//
// 审查报告 §74 禁止「用大量 .sheet 堆叠**导航**」，故把月历页全部 sheet 集中到此文件并逐条说明分工：
// - showDateJump / MonthEventEditSheet：真正的**模态**（选日期、长按日期格新建、
//   深链打开某事件编辑），不是导航，保留 sheet；
// - MonthAuxiliaryPage：是导航（倒数日 / 设置），但只服务于**程序化入口**（深链、iPad 菜单），
//   iPhone 上的常规入口走工具栏菜单里的 NavigationLink。
//   iPad 侧刻意用 sheet 而非 push：侧栏内 push 会被挤在窄列
//   （见 CalendarMonthView 工具栏菜单的注释）。
// 曾经还有一个 showAIAssistant 的 sheet，全仓无处置为 true（AI 助手在 iPhone 是独立 Tab、
// iPad 没有该节），属死代码，已删除。
//
// 5 个布尔/可选状态收敛为 showDateJump + auxiliaryPage + eventEditSheet 三个 item，
// 其中后两个为枚举驱动：同一时刻至多呈现一类目标，不会再出现两个 sheet 争抢弹出的组合爆炸。

/// 程序化入口的辅助页（导航性质：倒数日 / 设置）
enum MonthAuxiliaryPage: Identifiable {
    /// focusID：卡片点击深链进来时高亮对应条目（枚举值随 sheet 关闭销毁，
    /// 下次从菜单进入携带 nil，天然实现旧的「关闭后重置」语义）
    case countdown(focusID: UUID?)
    case settings
    var id: String {
        switch self {
        case .countdown: return "countdown"
        case .settings: return "settings"
        }
    }
}

/// 事件编辑模态的两种目标：长按日期格新建 / 深链、通知、Live Activity 打开已有事件
enum MonthEventEditSheet: Identifiable {
    case new(Date)
    case existing(CalendarEvent)
    var id: String {
        switch self {
        case .new(let date): return "new-\(date.timeIntervalSince1970)"
        case .existing(let event): return "existing-\(event.id.uuidString)"
        }
    }
}

/// 月历页全部 sheet 的集中呈现。状态留在 CalendarMonthView 本体（@State 唯一真相），
/// 这里只接收投影绑定，视图文件的 private 状态不需要因此放宽可见性。
struct MonthSheetsModifier: ViewModifier {
    @Binding var showDateJump: Bool
    @Binding var auxiliaryPage: MonthAuxiliaryPage?
    @Binding var eventEditSheet: MonthEventEditSheet?
    @Binding var selectedDate: Date
    @Binding var currentMonth: Date
    @Environment(EventStore.self) private var store

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showDateJump) {
                DateJumpView(targetDate: Binding(
                    get: { selectedDate },
                    set: { newDate in
                        selectedDate = newDate
                        currentMonth = newDate.firstDayOfMonth
                    }
                ))
            }
            .sheet(item: $auxiliaryPage) { page in
                NavigationStack {
                    switch page {
                    case .countdown(let focusID):
                        // CountdownView 的列表自身不包导航栈，sheet 中补一层
                        CountdownView(focusID: focusID)
                    case .settings:
                        // SettingsView 自身不再包导航栈，sheet 场景补一层（push 场景继承外层导航）
                        SettingsView().environment(store)
                    }
                }
            }
            .sheet(item: $eventEditSheet) { target in
                NavigationStack {
                    switch target {
                    case .new(let date):
                        EventEditView(editing: nil, defaultDate: date).environment(store)
                    case .existing(let event):
                        EventEditView(editing: event, defaultDate: event.startDate).environment(store)
                    }
                }
                // P1-8a：iPad regular 下用中 detent，避免全屏 sheet 遮挡主日历
                // （iOS 17 无 .inspector，这是最接近 Inspector 的体验）
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
    }
}
