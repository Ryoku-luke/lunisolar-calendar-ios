import SwiftUI

/// 「查询结果」Section 的**内容行**（P4-2 第 ② 步第三块：抽取自 `AIAssistantView.body`）。
///
/// 只搬内容、**不搬外面那层带 `header:` 的 `Section`**——SwiftUI 对 `Section` 有
/// "必须是 List 内容构建器直接子节点"的特殊处理，包进自定义视图有丢失分组语义的风险。
/// header 里用到的 `queryDate` 因此仍留在父视图。
///
/// 只依赖入参、不持有状态。
struct AIQueryResultRows: View {
    let results: [CalendarEvent]

    var body: some View {
                    if results.isEmpty {
                        Text(NSLocalizedString("这一天没有安排。", comment: "AI助手"))
                            .foregroundStyle(Color.secondary)
                    } else {
                        ForEach(results) { ev in
                            HStack(spacing: AppTheme.Spacing.sm) {
                                Text(ev.isAllDay
                                     ? NSLocalizedString("全天", comment: "")
                                     : ev.startDate.formatted(date: .omitted, time: .shortened))
                                    .font(AppTheme.Font.caption)
                                    .foregroundStyle(Color.secondaryLabel)
                                    .frame(width: 52, alignment: .leading)
                                Text(ev.title)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                        }
                    }
    }
}
