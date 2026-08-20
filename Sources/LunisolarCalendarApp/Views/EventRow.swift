#if canImport(SwiftUI)
import SwiftUI

// MARK: - 事件行（列表项）

struct EventRow: View {
    @Environment(EventStore.self) private var store
    let event: CalendarEvent
    var compact: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // 左侧竖条 (颜色指示，加宽到 4pt 提升可见度)
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(event.priority.tintColor)
                .frame(width: 4)
                .padding(.vertical, 4)

            // 完成按钮 + 类型图标
            VStack(spacing: 6) {
                Button {
                    store.toggleCompleted(event)
                } label: {
                    Image(systemName: event.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(compact ? .system(size: 18) : .title3)
                        .foregroundStyle(
                            event.isCompleted ? event.priority.tintColor : Color.separator
                        )
                }
                .buttonStyle(.plain)

                Image(systemName: event.type.systemIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(event.type.tintColor)
            }
            .frame(width: 26)

            // 内容
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(event.title)
                        .font(compact ? .footnote.weight(.semibold) : .body.weight(.medium))
                        .strikethrough(event.isCompleted, color: Color.secondaryLabel)
                        .foregroundStyle(event.isCompleted ? Color.secondaryLabel : Color.label)
                        .lineLimit(compact ? 1 : 2)

                    Spacer()

                    if event.priority == .urgent || event.priority == .high {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(event.priority.tintColor)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.tertiaryLabel)
                    Text(event.timeDisplay)
                        .font(.system(size: compact ? 10 : 11))
                        .foregroundStyle(Color.secondaryLabel)

                    if !compact, let loc = event.location, !loc.isEmpty {
                        Divider().frame(height: 10)
                        Image(systemName: "mappin.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.tertiaryLabel)
                        Text(loc)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondaryLabel)
                            .lineLimit(1)
                    }
                }

                // 重复规则标签（农历生日高亮红色）
                let ruleLabel = event.repeatRuleLabel
                if !compact, !ruleLabel.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: event.repeatRule == .lunarAnnually ? "lamp.floor" : "repeat")
                            .font(.system(size: 9))
                            .foregroundStyle(
                                event.repeatRule == .lunarAnnually
                                    ? Color(hex: "#C41A1A")
                                    : Color.tertiaryLabel
                            )
                        Text(ruleLabel)
                            .font(.system(size: 10, weight: event.repeatRule == .lunarAnnually ? .semibold : .regular))
                            .foregroundStyle(
                                event.repeatRule == .lunarAnnually
                                    ? Color(hex: "#C41A1A")
                                    : Color.secondaryLabel
                            )
                    }
                }

                if !compact, let notes = event.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.footnote)
                        .foregroundStyle(Color.tertiaryLabel)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, compact ? 6 : 10)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: compact ? 8 : 12, style: .continuous)
                .fill(Color.tertiarySystemBackground)
        )
    }
}

#endif
