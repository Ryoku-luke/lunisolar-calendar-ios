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
