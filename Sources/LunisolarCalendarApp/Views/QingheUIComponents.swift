#if canImport(SwiftUI)
import SwiftUI

/// 清和日历 2.0 的轻量设计组件：只负责视觉，不承载业务状态。
struct QingheSettingsHeroCard: View {
    let eventCount: Int
    let version: String
    let onAI: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.appTint.opacity(0.95), Color.systemIndigo.opacity(0.82)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("清和日历")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.label)
                    Text("让日历更懂你的生活")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(Color.secondaryLabel)
                }

                Spacer(minLength: 0)
            }

            Button(action: onAI) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.subheadline.weight(.semibold))
                    Text("AI 日历助手")
                        .font(AppTheme.Font.subheadline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.tertiaryLabel)
                }
                .foregroundStyle(Color.appTint)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(Color.appTint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.appTint.opacity(0.10), lineWidth: 0.6)
                }
        }
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 3)
        .padding(.vertical, 4)
    }
}

private struct QingheMetricPill: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.appTint)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.tertiaryLabel)
                Text(value)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.label)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.secondarySystemGroupedBackground.opacity(0.72), in: Capsule())
    }
}

struct QinghePhoneAIChip: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(Color.systemIndigo.opacity(0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.systemIndigo)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("AI 日历助手")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.label)
                    Text("让安排更简单")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.secondaryLabel)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.tertiaryLabel)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.systemIndigo.opacity(0.10), lineWidth: 0.7))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("AI 日历助手")
    }
}

struct QingheSectionHeader: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.secondaryLabel)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.tertiaryLabel)
            }
            Spacer()
        }
        .textCase(nil)
    }
}
// MARK: - 事件行快速操作（长按菜单）

/// 卡片内事件行（当日安排等）的长按菜单：完成 / 删除。
/// 说明：卡片里的行不是 List row，用不了 swipeActions；点按编辑由外层 NavigationLink 提供，
/// 故此处只补最常用的两个动作，不重复放"编辑"。
private struct EventQuickActionsModifier: ViewModifier {
    let event: CalendarEvent

    func body(content: Content) -> some View {
        content.contextMenu {
            Button {
                EventService.shared.setCompleted(event, flush: true)
            } label: {
                Label(event.isCompleted
                      ? NSLocalizedString("取消完成", comment: "")
                      : NSLocalizedString("标记完成", comment: ""),
                      systemImage: event.isCompleted ? "arrow.uturn.backward.circle" : "checkmark.circle")
            }
            Button(role: .destructive) {
                EventService.shared.removeEvent(event, flush: true)
            } label: {
                Label(NSLocalizedString("删除", comment: ""), systemImage: "trash")
            }
        }
    }
}

extension View {
    /// 事件行快速操作（长按：标记完成 / 删除）
    func eventQuickActions(_ event: CalendarEvent) -> some View {
        modifier(EventQuickActionsModifier(event: event))
    }
}
#endif
