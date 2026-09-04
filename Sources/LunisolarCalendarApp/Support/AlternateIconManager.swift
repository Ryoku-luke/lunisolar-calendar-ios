#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit
import LunarCore

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

        public var uiLabel: String {
            switch self {
            case .primary:        return "经典（撕历 + 朱砂印）"
            case .springFestival: return "春节限定（金福 + 红灯笼）"
            }
        }
    }

    @Published public private(set) var current: Icon = .primary

    private init() {
        syncFromSystem()
    }

    // MARK: - 系统状态校准
    /// 从 `UIApplication.shared.alternateIconName` 反向读取当前真实图标，校准 `current`。
    /// P3 修复：旧实现只在 init 时读一次。若用户在 iOS 设置 → App 切了备用图标、
    ///   或系统弹窗后用户取消、或外部进程触发 setAlternateIconName，
    ///   `current` 不会同步，下次 applyTodayIfNeeded 会以为 current==expected 跳过切换，
    ///   导致图标停留错误状态（最常见：春节窗口外仍停在春节图标）。
    ///   修复：applyTodayIfNeeded 与 setIcon 入口先 syncFromSystem，再判等。
    private func syncFromSystem() {
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
        // 切换前先校准 current，避免外部已改但 self.current 仍为旧值导致 skip
        syncFromSystem()
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
    ///
    /// ⚠️ 春节窗口判定统一走 LunarCore（本 App 自己的农历数据库），避免 Apple `.chinese` Calendar
    /// 与我们的农历查表有±1天偏差导致「月视图显示正月初一但图标没切/切早了」的不一致。
    public func applyTodayIfNeeded(graceBeforeDays: Int = 7) {
        let today = Date()
        let expected: Icon = isWithinSpringWindow(today, graceBeforeDays: graceBeforeDays)
            ? .springFestival
            : .primary
        Task { await setIcon(expected) }
    }

    /// 判断给定日期是否处于「春节窗口」
    /// 规则：
    ///   - 农历正月初一 为春节正日；
    ///   - 窗口 = (春节正日公历 - graceBeforeDays) ~ (正月初六 23:59:59 公历)。
    ///   - 因为今天可能处于上一个春节和下一个春节之间，需检查「今年」和「明年」两个候选年。
    func isWithinSpringWindow(_ date: Date, graceBeforeDays: Int) -> Bool {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: date)

        // 当前公历年对应的正月初一 及 明年对应的正月初一
        // 注意：today 可能处于公历1-2月，但该年正月初一可能是下一个月（2月份），
        // 或已过了今年正月，明年正月在 1-2 月的窗口内（例如春节前 7 天已是公历跨年）。
        let thisGY = cal.component(.year, from: today)
        let candidates: [Int] = [thisGY, thisGY + 1]

        for gy in candidates {
            // 求：农历 gy 年 正月初一 的公历日期
            // 先假设正月初一在农历 gy 年，但 农历 gy 年可能从公历 gy 的 1-2 月才开始，
            // 所以需要求「农历 gy 年正月初一」对应的公历日期。
            guard let springDay = ChineseCalendar.solarDate(
                fromLunar: gy, month: 1, day: 1, isLeap: false
            ) else { continue }
            let springGregorian = cal.startOfDay(for: springDay)
            // 正月初六：正月初一 + 5 天 = 第 6 天
            guard let sixthDay = cal.date(byAdding: .day, value: 5, to: springGregorian) else {
                continue
            }
            let sixthDayEnd = cal.date(bySettingHour: 23, minute: 59, second: 59, of: sixthDay)
                ?? sixthDay
            guard let windowStart = cal.date(byAdding: .day, value: -graceBeforeDays, to: springGregorian)
                else { continue }
            if today >= windowStart && today <= sixthDayEnd {
                return true
            }
        }
        return false
    }
}
#endif
