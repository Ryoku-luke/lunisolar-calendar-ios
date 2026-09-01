#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit

// MARK: - 备用图标管理器 · AlternateIconManager
///
/// 使用说明
///   1) 把 `Assets/XCAssets/AppIcon.appiconset` 和
///      `Assets/XCAssets/AppIconSpringFestival.appiconset` 拖入
///      工程的 Assets.xcassets。
///   2) 将 `Assets/XCAssets/Info.plist-EXAMPLE.xml` 中的
///      CFBundleIcons / CFBundleIcons~ipad 片段合并到 App 目标的 Info.plist。
///   3) 在 App 入口（LunisolarCalendarApp.swift）追加：
///
///         LunisolarCalendarApp()
///             .onAppear { AlternateIconManager.shared.applyTodayIfNeeded() }
///
///   4) 手动测试切换：
///
///         Button("切换到春节图标") {
///             Task { await AlternateIconManager.shared.setIcon(.springFestival) }
///         }
///
@MainActor
public final class AlternateIconManager: ObservableObject {

    public static let shared = AlternateIconManager()

    public enum Icon: String, CaseIterable, Hashable {
        case primary          = nil   // nil → 主图标 AppIcon
        case springFestival   = "SpringFestival"

        public var displayTitle: String {
            switch self {
            case .primary:        return "经典（撕历 + 朱砂印）"
            case .springFestival: return "春节限定（金福 + 红灯笼）"
            }
        }
    }

    @Published public private(set) var current: Icon = .primary

    private init() {
        if let raw = UIApplication.shared.alternateIconName,
           let match = Icon(rawValue: raw) {
            current = match
        } else {
            current = .primary
        }
    }

    // MARK: - 核心切换
    @discardableResult
    public func setIcon(_ icon: Icon) async -> Result<Void, Error> {
        guard current != icon else { return .success(()) }
        do {
            try await UIApplication.shared.setAlternateIconName(icon.rawValue)
            current = icon
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    // MARK: - 自动根据日期启用/停用
    /// 若今天落在「春节窗口」（正月初一前 7 天 ~ 正月初六），自动切换到春节图标；
    /// 否则确保回到主图标（仅在与 current 不一致时才触发系统弹窗）。
    public func applyTodayIfNeeded(
        calendar: Calendar = Calendar(identifier: .chinese),
        graceBeforeDays: Int = 7
    ) {
        let today = Date()
        let expected: Icon = isWithinSpringWindow(today,
                                                  calendar: calendar,
                                                  graceBeforeDays: graceBeforeDays)
            ? .springFestival
            : .primary
        Task { await setIcon(expected) }
    }

    /// 判断给定日期是否处于「春节窗口」
    /// 规则：
    ///   - 农历正月初一 为春节正日；
    ///   - 窗口 = (正月初一 - graceBeforeDays) ~ (正月初六 23:59:59)
    func isWithinSpringWindow(_ date: Date,
                              calendar: Calendar,
                              graceBeforeDays: Int) -> Bool {
        var gregorian: Calendar { Calendar(identifier: .gregorian) }
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = comps.year,
              let month = comps.month,
              let day = comps.day else { return false }

        // 今年正月初一
        var firstDayComps = DateComponents(calendar: calendar,
                                            year: year, month: 1, day: 1)
        guard let firstDay = calendar.date(from: firstDayComps) else { return false }
        let firstDayGregorian = gregorian.startOfDay(for: firstDay)

        // 正月初六
        var sixthDayComps = DateComponents()
        sixthDayComps.day = 5
        guard let sixthDay = calendar.date(byAdding: sixthDayComps, to: firstDay) else {
            return false
        }
        let sixthDayEnd = gregorian.date(bySettingHour: 23, minute: 59, second: 59,
                                         of: sixthDay) ?? sixthDay

        // 窗口左边界 = 正月初一（公历）再往前 grace 天
        guard let windowStart = gregorian.date(byAdding: .day, value: -graceBeforeDays,
                                               to: firstDayGregorian) else { return false }

        let now = date
        return now >= windowStart && now <= sixthDayEnd
    }
}
#endif
