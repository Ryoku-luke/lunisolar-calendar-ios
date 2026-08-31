#if canImport(SwiftUI)
import SwiftUI

struct EventRow: View {
    let event: CalendarEvent
    var compact: Bool = false
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
                if !compact, event.type == .reminder || event.type == .schedule {
                    Button { store.toggleCompleted(for: event.id) } label: {
                        Image(systemName: event.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: AppTheme.Touch.checkboxSize, weight: .semibold))
                            .foregroundStyle(
                                event.isCompleted ? Color.systemGreen : Color.tertiaryLabel.opacity(0.7))
                            .symbolRenderingMode(.hierarchical)
                            .frame(minWidth: AppTheme.Touch.minTarget,
                                   minHeight: AppTheme.Touch.minTarget,
                                   alignment: .trailing)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, compact ? AppTheme.Spacing.lg : AppTheme.Spacing.xl)
        .background(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
            .fill(Color.secondarySystemGroupedBackground))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
            .stroke(Color.separator.opacity(0.18), lineWidth: AppTheme.Stroke.hair))
        .contentShape(Rectangle())
    }
}
#endif
