import SwiftUI

/// AI 预览卡的内容行（P4-2 第 ② 步第四块：抽取自 `AIAssistantView.body`）。
///
/// 按既定规矩**只搬行、不搬 `Section`**：`Section` 必须是 List 内容构建器的直接子节点，
/// 包进自定义视图有丢失分组语义的风险；因此标题（`预览 · 确认后入库`）仍留在父视图。
///
/// 只依赖入参 + 两个回调（取消 / 确认创建）——不持有状态，父视图仍是唯一状态所有者。
struct AIPreviewRows: View {
    let draft: AICreateEventDraft
    let onCancel: () -> Void
    let onCreate: (AICreateEventDraft) -> Void

    var body: some View {
        LabeledContent(NSLocalizedString("标题", comment: ""), value: draft.title)
        // 类型决定会不会响（提醒类型到点必响，日程默认不打扰）——
        // 不显示出来，用户无法预判「说了提醒我」到底有没有兑现
        LabeledContent(NSLocalizedString("类型", comment: ""), value: draft.type.uiLabel)
        LabeledContent(NSLocalizedString("时间", comment: ""), value: draft.startDate.formatted(date: .abbreviated, time: .shortened))
        HStack {
            Button(role: .cancel) {
                // 取消只收起预览并保留原文（此前会清空输入，用户得重新打一遍）；
                // 焦点还给输入框，方便直接改词后重新解析
                onCancel()
            } label: {
                Label(NSLocalizedString("取消", comment: ""), systemImage: "xmark.circle")
            }
            // List 行内多按钮必须显式样式：默认样式下整行会抢走点击 →
            // 两个按钮都点不动（真机反馈「点确认取消也不起作用」）
            .buttonStyle(.borderless)
            .accessibilityIdentifier(AccessibilityID.aiCancel)
            Spacer()
            Button {
                onCreate(draft)
            } label: {
                Label(NSLocalizedString("确认创建", comment: "AI助手"), systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier(AccessibilityID.aiConfirm)
            .tint(Color.appTint)
        }
    }
}
