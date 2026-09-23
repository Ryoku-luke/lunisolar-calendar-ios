#if canImport(SwiftUI)
import SwiftUI

struct EventRow: View {
    let event: CalendarEvent
    var compact: Bool = false
    @Environment(EventStore.self) private var store
    @State private var pressed = false
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
                if event.type == .reminder || event.type == .schedule {
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
                    .accessibilityLabel(event.isCompleted ? "标记为未完成" : "标记为完成")
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, compact ? AppTheme.Spacing.lg : AppTheme.Spacing.xl)
        .softChipBackground(radius: AppTheme.Radius.lg,
                             fill: Color.secondarySystemGroupedBackground)
        .contentShape(Rectangle())
        // P2：整行按压缩放反馈
        .scaleEffect(pressed ? 0.985 : 1.0)
        .animation(AppTheme.Motion.pressInOut, value: pressed)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity) { } onPressingChanged: { p in
            pressed = p
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.title) \(event.displayTimeRange)\(event.isCompleted ? " 已完成" : "")")
        .accessibilityHint(event.type == .reminder || event.type == .schedule ? "轻点完成按钮切换完成状态" : "")
    }
}
#endif
