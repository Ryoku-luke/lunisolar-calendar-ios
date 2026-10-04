import SwiftUI

/// 行内提示条的状态：由"上一次操作的结果"驱动（错误 / 成功且有休息日 / 无）。
///
/// 为什么用枚举而不是三个可选值：三条分支互斥且共用一个位置——父视图映射成 state、
/// 子视图只做渲染，这样抽取出来的视图**不持有状态**（同 P4-1 的安全边界）。
enum AIInlineNoticeState {
    case error(String)
    case success(String, offDay: Date?)
    case none
}

/// 行内提示条（P4-2 第 ② 步第一块：抽取自 `AIAssistantView.body` 的 if/else-if 链）。
///
/// ⚠️ 抽取前先看清：`body` 里相邻的 `if let` 可能是**同一条链**（这一块就是
/// `if let inlineError … else if let completedMessage …`），只看块起始行会漏掉后半段。
struct AIInlineNotice: View {
    let state: AIInlineNoticeState

    @ViewBuilder
    var body: some View {
        switch state {
        case .error(let message):
                Section {
                    QingheToast(icon: "xmark.circle.fill", message: message, tint: .systemRed)
                }
        case .success(let message, let offDay):
                // 统一行内提示（报告 §42：同一件事不要既 Toast 又 Alert）
                Section {
                    QingheToast(message: message)
                    // 真机反馈（2026-09-30）：说「明天上午10点」时日程建到**明天**，
                    // 而用户人还在「今天」的日历页 → 今天列表毫无变化，看起来像"没反应"，
                    // 直到切日期/再操作一次才看见。根因不是刷新（实测 observation 与重绘都正常），
                    // 而是**反馈没有说明加到了哪一天、也没有去路**。
                    // 因此：仅当落点不是今天时，补一个「去看看」跳到该日。
                    if let offDay = offDay {
                        Button {
                            NavigationCoordinator.shared.openEventDate(offDay)
                        } label: {
                            Label(NSLocalizedString("去看看", comment: "AI助手：日程建在别的日子时跳过去"), systemImage: "arrow.right.circle")
                        }
                        .buttonStyle(SecondaryActionButtonStyle(accent: Color.appTint))
                        .accessibilityIdentifier(AccessibilityID.aiGoToCreatedDay)
                    }
                }
        case .none:
            EmptyView()
        }
    }
}
