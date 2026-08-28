#if canImport(SwiftUI)
import SwiftUI

// MARK: - 事件行（列表项）
// iOS 26 升级：分层背景、圆角 14/16、SF Symbols palette 渲染、完成态层次色

struct EventRow: View {
    @Environment(EventStore.self) private var store
    let event: CalendarEvent
    var compact: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 左侧：优先色渐变竖条 (iOS 26 视觉提示更明显)
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [event.priority.tintColor, event.priority.tintColor.opacity(0.55)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 4.5)
                .padding(.vertical, compact ? 4 : 6)

            // 完成按钮 + 类型图标 (两列更紧凑)
            VStack(spacing: compact ? 6 : 8) {
                Button {
                    store.toggleCompleted(event)
                } label: {
                    Image(systemName: event.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(compact ? .system(size: 20, weight: .regular) : .title2.weight(.regular))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(
                            event.isCompleted ? event.priority.tintColor : Color.secondaryLabel,
                            event.isCompleted ? Color.systemBackground : Color.clear
                        )
                }
                .buttonStyle(.plain)

                Image(systemName: event.type.systemIcon)
                    .font(.system(size: compact ? 11 : 12, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(event.type.tintColor)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle().fill(event.type.tintColor.opacity(0.12))
                    )
            }
            .frame(width: compact ? 26 : 30)

            // 内容
            VStack(alignment: .leading, spacing: compact ? 4 : 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(event.title)
                        .font(compact ? .footnote.weight(.semibold) : .body.weight(.semibold))
                        .strikethrough(event.isCompleted, color: Color.tertiaryLabel)
                        .foregroundStyle(event.isCompleted ? Color.tertiaryLabel : Color.label)
                        .lineLimit(compact ? 1 : 2)

                    Spacer()

                    // 紧急/高优先级图标
                    if event.priority == .urgent || event.priority == .high {
                        Label {
                            Text(event.priority.shortTitle)
                                .font(.caption2.weight(.bold))
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                        }
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(
                            Capsule().fill(event.priority.tintColor.opacity(0.14))
                        )
                        .foregroundStyle(event.priority.tintColor)
                    }
                }

                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: compact ? 10 : 11))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.tertiaryLabel)
                        Text(event.timeDisplay)
                            .font(.system(size: compact ? 11 : 12, weight: .medium))
                            .foregroundStyle(Color.secondaryLabel)
                    }

                    if !compact, let loc = event.location, !loc.isEmpty {
                        HStack(spacing: 0) {
                            // iOS 26：用竖点而不是 Divider，避免 layout 尺寸
                            Text("·")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.quaternaryLabel)
                                .padding(.horizontal, 4)
                            Image(systemName: "mappin.circle")
                                .font(.system(size: 11))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(Color.tertiaryLabel)
                            Text(loc)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.secondaryLabel)
                                .lineLimit(1)
                        }
                    }
                }

                // 重复规则标签（农历生日高亮红色）
                let ruleLabel = event.repeatRuleLabel
                if !compact, !ruleLabel.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: event.repeatRule == .lunarAnnually ? "lamp.floor" : "repeat")
                            .font(.system(size: 10))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(
                                event.repeatRule == .lunarAnnually
                                    ? Color.festiveRed
                                    : Color.tertiaryLabel
                            )
                        Text(ruleLabel)
                            .font(.system(size: 11, weight: event.repeatRule == .lunarAnnually ? .semibold : .medium))
                            .foregroundStyle(
                                event.repeatRule == .lunarAnnually
                                    ? Color.festiveRed
                                    : Color.secondaryLabel
                            )
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(
                        Capsule().fill(
                            event.repeatRule == .lunarAnnually
                                ? Color.festiveRed.opacity(0.10)
                                : Color.quaternarySystemFill
                        )
                    )
                }

                if !compact, let notes = event.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.footnote)
                        .foregroundStyle(Color.tertiaryLabel)
                        .lineLimit(2)
                        .padding(.top, 1)
                }
            }
        }
        .padding(.vertical, compact ? 8 : 12)
        .padding(.horizontal, compact ? 10 : 14)
        .background(
            // iOS 26：分层填充 —— 非 compact 模式用 secondaryGrouped 做"卡片中的卡片"层次感
            RoundedRectangle(cornerRadius: compact ? 10 : 14, style: .continuous)
                .fill(compact ? Color.tertiarySystemBackground.opacity(0.8) : Color.secondarySystemGroupedBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 10 : 14, style: .continuous)
                .stroke(Color.separator.opacity(compact ? 0.0 : 0.3), lineWidth: 0.5)
        )
        .opacity(event.isCompleted ? 0.88 : 1.0)
    }
}

#endif
