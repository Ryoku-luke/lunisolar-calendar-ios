#if canImport(SwiftUI)
import SwiftUI
import LunarCore

/// iPad 上下文 Inspector 的倒数日详情列（§33/§36 裁决 2026-09-26：右栏随选中倒数日切换）。
/// 只读摘要 + 「编辑」入口（编辑器复用 CountdownEditor，sheet 呈现，与列表页一致）；
/// 未选中或条目已删除时给统一空态提示。
struct CountdownDetailView: View {
    @Binding var selection: UUID?
    @Environment(CountdownStore.self) private var store
    @State private var editingEvent: CountdownEvent?

    var body: some View {
        Group {
            if let id = selection, let event = store.events.first(where: { $0.id == id }) {
                detail(event)
            } else {
                QingheEmptyView(
                    icon: "hourglass",
                    title: NSLocalizedString("未选择倒数日", comment: "iPad Inspector 空态"),
                    message: NSLocalizedString("在左侧列表中选择一个倒数日，这里会显示它的详情", comment: "iPad Inspector 空态")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.systemGroupedBackground)
        // 稳定标识：Flow 4 断言右栏确实是倒数日 Inspector（而非常驻日详情）
        .accessibilityIdentifier(AccessibilityID.iPadInspectorCountdown)
        .sheet(item: $editingEvent) { event in
            CountdownEditor(event: event)
        }
    }

    private func detail(_ event: CountdownEvent) -> some View {
        let today = Date()
        return ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                HStack(spacing: AppTheme.Spacing.md) {
                    Text(event.emoji)
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .frame(width: 64, height: 64)
                        .background(Color.themeQuaternaryFill)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                        Text(event.title)
                            .font(AppTheme.Font.title3)
                            .foregroundStyle(Color.label)
                        Label(event.kind.label, systemImage: event.kind.icon)
                            .font(AppTheme.Font.caption)
                            .foregroundStyle(Color.secondaryLabel)
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text(event.displayText(today: today))
                        .font(AppTheme.Font.numeralXL)
                        .foregroundStyle(Color.appTint)
                        .contentTransition(.numericText())
                    Text(event.date.formatted(Date.FormatStyle(date: .long, time: .omitted,
                                                              locale: Locale(identifier: "zh_Hans_CN"))))
                        .font(AppTheme.Font.subheadline)
                        .foregroundStyle(Color.secondaryLabel)
                }

                if let note = event.note, !note.isEmpty {
                    Text(note)
                        .font(AppTheme.Font.body)
                        .foregroundStyle(Color.label)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppTheme.Spacing.md)
                        .softChipBackground(fill: Color.themeQuaternaryFill)
                }

                Button {
                    editingEvent = event
                } label: {
                    Label(NSLocalizedString("编辑", comment: ""), systemImage: "pencil")
                }
                .buttonStyle(SecondaryActionButtonStyle(accent: Color.appTint))
            }
            .padding(AppTheme.Spacing.lg)
        }
    }
}
#endif
