import SwiftUI

/// AI 助手的「解析并预览」按钮（P4-2 第 ② 步：抽取自 `AIAssistantView.body`）。
///
/// 为什么只抽按钮、**不抽外面那层 `Section`**：SwiftUI 对 `Section` 有"必须是 List
/// 内容构建器直接子节点"的特殊处理，把 `Section` 包进自定义视图存在丢失分组语义的风险
/// ——那属于会改行为的改动，本次只做纯搬运（只搬按钮）。
///
/// 不读不写任何状态，只把动作交给父视图（`onParse`）✓ 符合"视图只做 UI"。
struct AIParseButton: View {
    let onParse: () -> Void

    var body: some View {
                    Button {
                    onParse()
                    } label: {
                    Text(NSLocalizedString("解析并预览", comment: "AI助手"))
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
    }
}
