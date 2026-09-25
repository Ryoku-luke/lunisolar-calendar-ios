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

/// 卡片内事件行（当日安排等）的长按菜单：编辑 / 完成 / 删除。
/// 说明：卡片里的行不是 List row，用不了 swipeActions，这几个动作只能放长按菜单里；
/// 「编辑」用内部 sheet（行外层可能是 NavigationLink，无法命令式 push）。
private struct EventQuickActionsModifier: ViewModifier {
    let event: CalendarEvent
    /// 长按菜单里的「编辑」需要一个 sheet（行外层可能是 NavigationLink，无法命令式 push）
    @State private var editing: CalendarEvent?

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button {
                    editing = event
                } label: {
                    Label(NSLocalizedString("编辑", comment: ""), systemImage: "pencil")
                }
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
            .sheet(item: $editing) { target in
                NavigationStack {
                    EventEditView(editing: target, defaultDate: target.startDate)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
