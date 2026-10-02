import Foundation

/// 跨平台本地化入口
/// - iOS / macOS：走系统 `String(localized:)`，按系统语言自动取 lproj 翻译
/// - Linux / 其他无 Darwin Foundation 平台：`String(localized:)` 不存在，
///   退化返回 key 原文（模型层 UI 文案由视图层二次本地化）
enum L10n {
    static func str(_ key: String) -> String {
        #if canImport(Darwin)
        return String(localized: String.LocalizationValue(key))
        #else
        return key
        #endif
    }
}

/// 展示用的月份名（**locale 感知，但日历固定公历**）。
///
/// 为什么不用 `Text(date, format: .dateTime.month(.wide))`：
/// 那个会跟随 `Locale.current` 的**日历**——系统区域设为佛历/和历/伊斯兰历时，
/// 月名会变成该历法的月名，而下面的月历网格是公历，两处对不上
/// （同类问题在 `DataPortability` 的日期格式化注释里已经踩过一次）。
/// 这里只用 locale 的**月名**，日历始终是公历。
///
/// 为什么不用写死的 `"\(month)月"`：英文界面会显示「9月」（P3-3 的原始缺陷）。
enum MonthLabel {
    public static func name(for date: Date, locale: Locale = .current) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = locale
        // 用 MMM 而不是 MMMM：中文/日文的 MMM 是「9月」（与 App 其它日期串「公历 9月25日」一致），
        // MMMM 会变成「九月」——那是本次修复之外的中文界面变更，不做。
        // 英文 MMM = "Sep"、MMMM = "September"；想要全称只改这一个模板。
        f.setLocalizedDateFormatFromTemplate("MMM")
        return f.string(from: date)
    }
}
