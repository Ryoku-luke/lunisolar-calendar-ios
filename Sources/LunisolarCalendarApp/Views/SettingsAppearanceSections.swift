#if canImport(SwiftUI)
import SwiftUI

extension SettingsView {
    // MARK: - 1. 外观

    var appearanceSection: some View {
        Section {
            // 外观模式：原生菜单 Picker（跟随系统 / 浅色 / 深色）
            Picker(NSLocalizedString("外观模式", comment: ""), selection: $appearanceSelection) {
                ForEach(AppAppearance.allCases) { mode in
                    Label(mode.title, systemImage: mode.iconName).tag(mode)
                }
            }
            .pickerStyle(.menu)
            // 每周起始日（主流日历标配，切换即时生效于月视图网格与星期头）
            Picker(NSLocalizedString("每周起始日", comment: ""), selection: $weekStart) {
                Text(NSLocalizedString("周日", comment: "")).tag(1)
                Text(NSLocalizedString("周一", comment: "")).tag(2)
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier(AccessibilityID.settingsWeekStart)
        } header: {
            QingheSectionHeader(NSLocalizedString("外观", comment: ""), subtitle: "主题与日历显示方式")
        }
    }

    // MARK: - 2.5 日历显示（二级入口，设计稿 04）

    var calendarLinkSection: some View {
        Section {
            NavigationLink {
                CalendarDisplaySettingsView()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("日历", comment: ""))
                            .font(AppTheme.Font.bodyBold)
                            .foregroundStyle(Color.label)
                        Text(NSLocalizedString("农历、节气、节假日显示", comment: ""))
                            .font(AppTheme.Font.caption)
                            .foregroundStyle(Color.tertiaryLabel)
                    }
                } icon: {
                    Image(systemName: "calendar")
                        .foregroundStyle(Color.appTint)
                }
            }
        }
    }
}

#endif
