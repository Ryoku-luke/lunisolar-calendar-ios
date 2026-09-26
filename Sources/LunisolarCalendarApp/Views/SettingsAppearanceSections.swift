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

    // MARK: - 1.5 App 图标（P2-9：手动切换主图标/春节限定）
    // UIKit only：UIApplication.setAlternateIconName 为 iOS API，macOS 无替代图标能力

    #if canImport(UIKit)
    var iconSection: some View {
        Section {
            Picker(NSLocalizedString("App 图标", comment: ""), selection: .init(
                get: { AlternateIconManager.shared.current },
                set: { icon in
                    Task { await AlternateIconManager.shared.setIcon(icon) }
                }
            )) {
                ForEach(AlternateIconManager.Icon.allCases, id: \.self) { icon in
                    Label(icon.uiLabel, systemImage: icon == .springFestival ? "gift" : "app")
                        .tag(icon)
                }
            }
            .pickerStyle(.navigationLink)
        } header: {
            QingheSectionHeader(NSLocalizedString("图标", comment: ""),
                                subtitle: NSLocalizedString("主图标 / 春节限定自动切换", comment: ""))
        }
    }
    #endif

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
