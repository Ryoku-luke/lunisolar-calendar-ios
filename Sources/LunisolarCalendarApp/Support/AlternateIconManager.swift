#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit
import LunarCore

// MARK: - 备用图标管理器 · AlternateIconManager
///
/// 使用说明
///   1) 把 `Assets/Assets.xcassets/AppIcon.appiconset` 和
///      `Assets/Assets.xcassets/AppIconSpringFestival.appiconset` 拖入
///      工程的 Assets.xcassets。
///   2) 将 `Sources/LunisolarCalendarApp/Info.plist` 中的
///      CFBundleIcons / CFBundleIcons~ipad 片段保留（已内置春节限定声明）。
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
        case primary          = "primary"          // 主图标 AppIcon
        case springFestival   = "SpringFestival"   // 春节（正月初一）
        case lantern          = "Lantern"          // 元宵（正月十五）
        case qingMing         = "QingMing"         // 清明
        case duanWu           = "DuanWu"           // 端午（五月初五）
        case qixi             = "Qixi"             // 七夕（七月初七）
        case midAutumn        = "MidAutumn"        // 中秋（八月十五）
        case chongYang        = "ChongYang"        // 重阳（九月初九）
        case winterSolstice   = "WinterSolstice"  // 冬至

        /// 传给 `UIApplication.setAlternateIconName` 的值：
        /// 主图标返回 nil（重置为默认图标），备用图标返回其 rawValue。
        var alternateIconName: String? {
            switch self {
            case .primary:        return nil
            default:              return rawValue
            }
        }

        public var uiLabel: String {
            switch self {
            case .primary:        return NSLocalizedString("经典（撕历 + 四季）", comment: "")
            case .springFestival: return NSLocalizedString("春节限定（金福 + 红灯笼）", comment: "")
            case .lantern:       return NSLocalizedString("元宵限定（汤圆 + 花灯）", comment: "")
            case .qingMing:      return NSLocalizedString("清明限定（新柳 + 青团）", comment: "")
            case .duanWu:        return NSLocalizedString("端午限定（粽子 + 龙舟）", comment: "")
            case .qixi:          return NSLocalizedString("七夕限定（鹊桥 + 星河）", comment: "")
            case .midAutumn:     return NSLocalizedString("中秋限定（满月 + 玉兔）", comment: "")
            case .chongYang:     return NSLocalizedString("重阳限定（菊花 + 枫叶）", comment: "")
            case .winterSolstice: return NSLocalizedString("冬至限定（饺子 + 梅花）", comment: "")
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
            try await UIApplication.shared.setAlternateIconName(icon.alternateIconName)
            current = icon
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    // MARK: - 自动根据日期启用/停用
    /// 根据今天日期自动选择图标：落在任一节日窗口内则切对应节日图标，
    /// 否则回主图标。多个节日窗口重叠时按下面 priority 数组顺序取第一个命中。
    public func applyTodayIfNeeded(graceBeforeDays: Int = 7) {
        let today = Date()
        let expected: Icon = icon(for: today, graceBeforeDays: graceBeforeDays)
        Task { await setIcon(expected) }
    }

    /// 判断某天应使用哪个节日图标（纯函数，便于测试）
    func icon(for date: Date, graceBeforeDays: Int = 7) -> Icon {
        // 优先级：春节 > 元宵 > 端午 > 中秋 > 七夕 > 重阳 > 清明 > 冬至
        if isWithinSpringWindow(date, graceBeforeDays: graceBeforeDays) { return .springFestival }
        if isWithinLunarFestival(date, month: 1, day: 15, windowDays: 1) { return .lantern }
        if isWithinSolarFestival(date, month: 4, day: 5, windowDays: 1) { return .qingMing }
        if isWithinLunarFestival(date, month: 5, day: 5, windowDays: 1) { return .duanWu }
        if isWithinLunarFestival(date, month: 7, day: 7, windowDays: 0) { return .qixi }
        if isWithinLunarFestival(date, month: 8, day: 15, windowDays: 1) { return .midAutumn }
        if isWithinLunarFestival(date, month: 9, day: 9, windowDays: 0) { return .chongYang }
        if isWithinSolarFestival(date, month: 12, day: 22, windowDays: 1) { return .winterSolstice }
        return .primary
    }

    /// 农历节日窗口：农历 month/month day 前后 windowDays 天
    private func isWithinLunarFestival(_ date: Date, month: Int, day: Int, windowDays: Int) -> Bool {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: date)
        let gy = cal.component(.year, from: today)
        // 春节在公历 1-2 月，可能属于上一个农历年；其他节日月份稳定，查 gy 即可
        for candidateYear in [gy, gy + 1, gy - 1] {
            guard let festivalDay = ChineseCalendar.solarDate(
                fromLunar: candidateYear, month: month, day: day, isLeap: false
            ) else { continue }
            let fest = cal.startOfDay(for: festivalDay)
            guard let start = cal.date(byAdding: .day, value: -windowDays, to: fest),
                  let end = cal.date(byAdding: .day, value: windowDays, to: fest) else { continue }
            if today >= start && today <= end { return true }
        }
        return false
    }

    /// 公历节日窗口：month/day 前后 windowDays 天
    private func isWithinSolarFestival(_ date: Date, month: Int, day: Int, windowDays: Int) -> Bool {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: date)
        let gy = cal.component(.year, from: today)
        for candidateYear in [gy, gy + 1, gy - 1] {
            var comps = DateComponents()
            comps.year = candidateYear; comps.month = month; comps.day = day
            guard let fest = cal.date(from: comps) else { continue }
            let festStart = cal.startOfDay(for: fest)
            guard let start = cal.date(byAdding: .day, value: -windowDays, to: festStart),
                  let end = cal.date(byAdding: .day, value: windowDays, to: festStart) else { continue }
            if today >= start && today <= end { return true }
        }
        return false
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
