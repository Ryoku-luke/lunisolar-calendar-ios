#if canImport(SwiftUI)
import SwiftUI

struct EventRow: View {
    let event: CalendarEvent
    var compact: Bool = false
    /// 多选模式下隐藏行内完成圆圈：整行本身是选择按钮，嵌套按钮会导致点击失效
    var showsCompleteToggle: Bool = true
    @Environment(EventStore.self) private var store
    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            RoundedRectangle(cornerRadius: AppTheme.Stroke.thin, style: .continuous)
                .fill(event.priority.tintColor)
                .frame(width: event.priority == .urgent ? 4 : 3,
                       height: event.type == .note ? 28 : (compact ? 40 : 54))
                .padding(.vertical, compact ? 2 : 4)
            VStack(alignment: .leading, spacing: compact ? 3 : 5) {
                Text(event.title)
                    .font(compact ? AppTheme.Font.bodyBold : AppTheme.Font.title3)
                    .foregroundStyle(event.isCompleted ? Color.tertiaryLabel : Color.label)
                    .strikethrough(event.isCompleted, color: Color.tertiaryLabel)
                    .lineLimit(compact ? 1 : 2)
                if event.type != .note {
                    HStack(spacing: 6) {
                        Image(systemName: event.type.iconName)
                            .font(compact ? AppTheme.Font.caption2 : AppTheme.Font.caption)
                            .foregroundStyle(event.type.tintColor)
                            .symbolRenderingMode(.hierarchical)
                        Text(event.displayTimeRange)
                            .font(compact ? AppTheme.Font.caption2 : AppTheme.Font.caption)
                            .foregroundStyle(Color.secondaryLabel).lineLimit(1)
                        if let rule = event.repeatRule.displayText, !rule.isEmpty {
                            Text("· \(rule)").font(compact ? AppTheme.Font.caption2 : AppTheme.Font.caption)
                                .foregroundStyle(Color.tertiaryLabel).lineLimit(1)
                        }
                    }
                }
                if !compact, let note = event.notes, !note.isEmpty {
                    Text(note).font(AppTheme.Font.caption)
                        .foregroundStyle(Color.tertiaryLabel).lineLimit(2)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: compact ? 4 : 8) {
                ChipLabel(title: event.priority.shortTitle,
                          tint: event.priority.tintColor,
                          font: AppTheme.Font.caption2)
                if showsCompleteToggle, event.type == .reminder || event.type == .schedule {
                    Button {
                        // 仅在"从未完成 → 完成"方向计入评分引导（取消勾选不计），
                        // 避免用户反复勾选刷计数。
                        if !event.isCompleted { RatingPromptCoordinator.registerMeaningfulAction() }
                        EventService.shared.setCompleted(event)
                    } label: {
                        Image(systemName: event.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: compact ? 18 : AppTheme.Touch.checkboxSize, weight: .semibold))
                            .foregroundStyle(
                                event.isCompleted ? Color.systemGreen : Color.tertiaryLabel.opacity(0.7))
                            .symbolRenderingMode(.hierarchical)
                            .frame(minWidth: compact ? 36 : AppTheme.Touch.minTarget,
                                   minHeight: compact ? 36 : AppTheme.Touch.minTarget,
                                   alignment: .trailing)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    // 三元表达式会走 accessibilityLabel 的 StringProtocol 重载 → 不查表，
                    // 必须显式 NSLocalizedString（与 CountdownView / EventEditView 同类问题）
                    .accessibilityLabel(event.isCompleted
                                        ? NSLocalizedString("标记为未完成", comment: "")
                                        : NSLocalizedString("标记为完成", comment: ""))
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, compact ? AppTheme.Spacing.lg : AppTheme.Spacing.xl)
        .softChipBackground(radius: AppTheme.Radius.lg,
                             fill: Color.secondarySystemGroupedBackground)
        .contentShape(Rectangle())
        // 注意：此处**不能**用 onLongPressGesture 做按压反馈 —— 它会在触摸按下的瞬间
        // 抢走手势，导致外层 Button / onTapGesture / contextMenu 全部失效
        // （真机表现：全部日程点不开编辑、多选点不动）。
        // 按压反馈统一由调用方 .pressableFeedback()（simultaneousGesture 实现）提供。
        .accessibilityElement(children: .combine)
        // ⚠️ 这两处也是三元 / String 形参：内层字面量必须显式 NSLocalizedString 才会查表
        .accessibilityLabel("\(event.title) \(event.displayTimeRange)\(event.isCompleted ? " " + NSLocalizedString("已完成", comment: "") : "")")
        .accessibilityHint(event.type == .reminder || event.type == .schedule
                           ? NSLocalizedString("轻点完成按钮切换完成状态", comment: "")
                           : "")
    }
}
#endif
