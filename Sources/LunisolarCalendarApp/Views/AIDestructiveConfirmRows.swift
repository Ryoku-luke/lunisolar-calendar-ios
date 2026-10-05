import SwiftUI

/// AI「删除 / 修改」破坏性操作的确认行（P4-2 第 ② 步第五块：抽取自 `AIAssistantView.body`）。
///
/// 按既定规矩**只搬行、不搬 `Section`**：`Section` 必须是 List 内容构建器的直接子节点，
/// 包进自定义视图有丢失分组语义的风险；因此 `header`（显示要操作的那条日程名）留在父视图。
///
/// 接口刻意收窄：父视图把「日程名 / 当前时间 / 重复规则的说明」算好传进来，
/// 子视图只说"用户点了确认还是取消"——状态怎么变仍由父视图决定（父视图是唯一状态所有者）。
struct AIDestructiveConfirmRows: View {
    let title: String
    let occurrence: String
    /// 重复规则的说明；`nil` 表示不是重复日程（此时不显示那条橙色警示）。
    let repeatLabel: String?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        LabeledContent(NSLocalizedString("日程", comment: ""), value: title)
        LabeledContent(
            NSLocalizedString("当前时间", comment: ""),
            value: occurrence
        )
        // 重复日程：模型里没有"单次例外"，这里的操作会作用于**整条重复规则**。
        // 必须说清楚，否则用户以为只删/只改"明天那次"，实际整条每周序列都没了。
        if let repeatLabel {
            Label(String(format: NSLocalizedString("这是重复日程（%@），将影响整条重复规则", comment: "AI助手"),
                         repeatLabel),
                  systemImage: "exclamationmark.triangle.fill")
                .font(AppTheme.Font.caption)
                .foregroundStyle(Color.systemOrange)
        }
        HStack {
            Button(role: .cancel) {
                onCancel()
            } label: {
                Label(NSLocalizedString("取消", comment: ""), systemImage: "xmark.circle")
            }
            // 同上：List 行内多按钮需要显式样式，否则整行抢点击
            .buttonStyle(.borderless)
            Spacer()
            Button {
                onConfirm()
            } label: {
                Label(NSLocalizedString("确认", comment: ""), systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .tint(Color.appTint)
        }
    }
}
