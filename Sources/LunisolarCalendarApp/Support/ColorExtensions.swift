#if canImport(SwiftUI)
import SwiftUI

// MARK: - 颜色扩展 (iOS语义色 + 跨平台兼容)

extension Color {

    #if canImport(UIKit)
    static var systemBackground: Color { Color(UIColor.systemBackground) }
    static var secondarySystemBackground: Color { Color(UIColor.secondarySystemBackground) }
    static var tertiarySystemBackground: Color { Color(UIColor.tertiarySystemBackground) }
    static var systemGroupedBackground: Color { Color(UIColor.systemGroupedBackground) }
    static var separator: Color { Color(UIColor.separator) }
    static var label: Color { Color(UIColor.label) }
    static var secondaryLabel: Color { Color(UIColor.secondaryLabel) }
    static var tertiaryLabel: Color { Color(UIColor.tertiaryLabel) }
    static var systemRed: Color { Color(UIColor.systemRed) }
    static var systemOrange: Color { Color(UIColor.systemOrange) }
    static var systemYellow: Color { Color(UIColor.systemYellow) }
    static var systemGreen: Color { Color(UIColor.systemGreen) }
    static var systemBlue: Color { Color(UIColor.systemBlue) }
    static var systemPurple: Color { Color(UIColor.systemPurple) }
    static var systemPink: Color { Color(UIColor.systemPink) }
    static var systemTeal: Color { Color(UIColor.systemTeal) }
    static var systemIndigo: Color { Color(UIColor.systemIndigo) }
    #else
    // macOS / Linux fallback (基于 SwiftUI 原生 Color)
    static var systemBackground: Color { Color(NSColor.windowBackgroundColor) }
    static var secondarySystemBackground: Color { Color(NSColor.underPageBackgroundColor) }
    static var tertiarySystemBackground: Color { Color(NSColor.controlBackgroundColor) }
    static var systemGroupedBackground: Color { Color(NSColor.windowBackgroundColor) }
    static var separator: Color { Color.gray.opacity(0.3) }
    static var label: Color { Color.primary }
    static var secondaryLabel: Color { Color.secondary }
    static var tertiaryLabel: Color { Color.secondary.opacity(0.6) }
    static var systemRed: Color { Color.red }
    static var systemOrange: Color { Color.orange }
    static var systemYellow: Color { Color.yellow }
    static var systemGreen: Color { Color.green }
    static var systemBlue: Color { Color.blue }
    static var systemPurple: Color { Color.purple }
    static var systemPink: Color { Color.pink }
    static var systemTeal: Color { Color.teal }
    static var systemIndigo: Color { Color.indigo }
    #endif

    /// 黄道吉日吉祥红
    static var auspicious: Color {
        Color(red: 0.85, green: 0.2, blue: 0.2)
    }
}

// MARK: - 屏幕尺寸辅助 (跨平台)
// Swift 6 / iOS 26：UIScreen.main 被废弃（多 Scene 场景下不可靠）
// 这里只做 fallback，真实 app 中应该从 View 的 windowScene 获取。

enum ScreenHelper {
    #if canImport(UIKit)
    @available(iOS, deprecated: 26.0, message: "Use view.window?.windowScene?.screen instead")
    static var width: CGFloat { UIScreen.main.bounds.width }
    #else
    static var width: CGFloat { 390 }
    #endif
}

#endif
