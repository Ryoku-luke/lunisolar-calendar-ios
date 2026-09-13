#if canImport(SwiftUI)
import SwiftUI

// MARK: - 颜色扩展 (iOS语义色 + iOS 26 层次色 + 跨平台兼容)

extension Color {

    #if canImport(UIKit)
    // MARK: 系统语义背景色 (iOS 10+)
    static var systemBackground: Color { Color(UIColor.systemBackground) }
    static var secondarySystemBackground: Color { Color(UIColor.secondarySystemBackground) }
    static var tertiarySystemBackground: Color { Color(UIColor.tertiarySystemBackground) }
    static var systemGroupedBackground: Color { Color(UIColor.systemGroupedBackground) }
    static var secondarySystemGroupedBackground: Color { Color(UIColor.secondarySystemGroupedBackground) }
    static var tertiarySystemGroupedBackground: Color { Color(UIColor.tertiarySystemGroupedBackground) }
    static var separator: Color { Color(UIColor.separator) }
    static var opaqueSeparator: Color { Color(UIColor.opaqueSeparator) }

    // MARK: 标签/层次色 (iOS 13+, iOS 26 更强调层级)
    static var label: Color { Color(UIColor.label) }
    static var secondaryLabel: Color { Color(UIColor.secondaryLabel) }
    static var tertiaryLabel: Color { Color(UIColor.tertiaryLabel) }
    static var quaternaryLabel: Color { Color(UIColor.quaternaryLabel) }

    // MARK: 系统着色 (iOS 26: SF Symbols 渲染更柔和)
    static var systemRed: Color { Color(UIColor.systemRed) }
    static var systemOrange: Color { Color(UIColor.systemOrange) }
    static var systemYellow: Color { Color(UIColor.systemYellow) }
    static var systemGreen: Color { Color(UIColor.systemGreen) }
    static var systemBlue: Color { Color(UIColor.systemBlue) }
    static var systemPurple: Color { Color(UIColor.systemPurple) }
    static var systemPink: Color { Color(UIColor.systemPink) }
    static var systemTeal: Color { Color(UIColor.systemTeal) }
    static var systemIndigo: Color { Color(UIColor.systemIndigo) }
    static var systemBrown: Color { Color(UIColor.systemBrown) }
    static var systemCyan: Color { Color(UIColor.systemCyan) }
    static var systemMint: Color { Color(UIColor.systemMint) }
    static var systemGray: Color { Color(UIColor.systemGray) }
    static var systemGray2: Color { Color(UIColor.systemGray2) }
    static var systemGray3: Color { Color(UIColor.systemGray3) }
    static var systemGray4: Color { Color(UIColor.systemGray4) }
    static var systemGray5: Color { Color(UIColor.systemGray5) }
    static var systemGray6: Color { Color(UIColor.systemGray6) }

    // MARK: iOS 26 新增填充色 (FillColors) — 用于徽章、卡片背景、tag
    // Apple iOS 18 新增：systemFill / secondarySystemFill / tertiarySystemFill / quaternarySystemFill
    // 语义：从"较重填充"到"最轻填充"，自动适配深色模式
    static var systemFill: Color { Color(UIColor.systemFill) }
    static var secondarySystemFill: Color { Color(UIColor.secondarySystemFill) }
    static var tertiarySystemFill: Color { Color(UIColor.tertiarySystemFill) }
    static var quaternarySystemFill: Color { Color(UIColor.quaternarySystemFill) }

    // 标记/便签色 (iOS 18+) — 用于优先级胶囊、节日徽章
    #else
    // MARK: macOS / Linux fallback (基于 SwiftUI 原生 Color)
    static var systemBackground: Color { Color(NSColor.windowBackgroundColor) }
    static var secondarySystemBackground: Color { Color(NSColor.underPageBackgroundColor) }
    static var tertiarySystemBackground: Color { Color(NSColor.controlBackgroundColor) }
    static var systemGroupedBackground: Color { Color(NSColor.windowBackgroundColor) }
    static var secondarySystemGroupedBackground: Color { Color(NSColor.underPageBackgroundColor) }
    static var tertiarySystemGroupedBackground: Color { Color(NSColor.controlBackgroundColor) }
    static var separator: Color { Color.gray.opacity(0.3) }
    static var opaqueSeparator: Color { Color.gray.opacity(0.6) }
    static var label: Color { Color.primary }
    static var secondaryLabel: Color { Color.secondary }
    static var tertiaryLabel: Color { Color.secondary.opacity(0.6) }
    static var quaternaryLabel: Color { Color.secondary.opacity(0.4) }
    static var systemRed: Color { Color.red }
    static var systemOrange: Color { Color.orange }
    static var systemYellow: Color { Color.yellow }
    static var systemGreen: Color { Color.green }
    static var systemBlue: Color { Color.blue }
    static var systemPurple: Color { Color.purple }
    static var systemPink: Color { Color.pink }
    static var systemTeal: Color { Color.teal }
    static var systemIndigo: Color { Color.indigo }
    static var systemBrown: Color { Color.brown }
    static var systemCyan: Color { Color.cyan }
    static var systemMint: Color { Color.mint }
    static var systemGray: Color { Color.gray }
    static var systemGray2: Color { Color.gray.opacity(0.85) }
    static var systemGray3: Color { Color.gray.opacity(0.7) }
    static var systemGray4: Color { Color.gray.opacity(0.55) }
    static var systemGray5: Color { Color.gray.opacity(0.4) }
    static var systemGray6: Color { Color.gray.opacity(0.25) }
    static var systemFill: Color { Color.gray.opacity(0.2) }
    static var secondarySystemFill: Color { Color.gray.opacity(0.15) }
    static var tertiarySystemFill: Color { Color.gray.opacity(0.1) }
    static var quaternarySystemFill: Color { Color.gray.opacity(0.05) }
    #endif

    // MARK: 应用品牌色 (iOS 26 风格 — 深浅模式自适应)
    // 使用 UIColor(dynamicProvider:) 让品牌色在浅色/深色模式下自动切换亮度与饱和度
    #if canImport(UIKit)
    /// 中国红：浅色模式 0.77/0.10/0.10；深色模式提亮至 0.90/0.30/0.30 避免暗背景上发黑
    static var festiveRed: Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.90, green: 0.30, blue: 0.30, alpha: 1.0)
                : UIColor(red: 0.77, green: 0.10, blue: 0.10, alpha: 1.0)
        })
    }
    /// 喜庆金：深色模式更暖更亮
    static var festiveGold: Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.95, green: 0.80, blue: 0.42, alpha: 1.0)
                : UIColor(red: 0.88, green: 0.72, blue: 0.35, alpha: 1.0)
        })
    }
    /// 主题强调色：现代暖调靛蓝（比纯系统蓝更有辨识度，且与节日红/金不冲突）
    /// 浅色模式：柔和的蓝紫调，高级感；深色模式：提亮饱和度保持活力
    static var appTint: Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.34, green: 0.52, blue: 0.98, alpha: 1.0)
                : UIColor(red: 0.24, green: 0.39, blue: 0.87, alpha: 1.0)
        })
    }
    #else
    // macOS / Linux fallback（固定色值）
    static var festiveRed: Color { Color(red: 0.77, green: 0.10, blue: 0.10) }
    static var festiveGold: Color { Color(red: 0.88, green: 0.72, blue: 0.35) }
    static var appTint: Color { Color(red: 0.24, green: 0.39, blue: 0.87) }
    #endif
}

// MARK: ShapeStyle 便捷扩展 (iOS 26 材质背景)

/// iOS 26 推荐：NavigationBar / Toolbar 用 .regularMaterial
/// 卡片/面板用 .thinMaterial，模态 Sheet 用 .ultraThinMaterial
extension ShapeStyle where Self == Material {
    /// iOS 26 导航栏/顶栏材质：iOS 16+ 推荐
    static var navBar: Material { .regularMaterial }
    /// iOS 26 卡片/面板背景：iOS 18 更清晰的半透明
    static var cardSurface: Material { .thinMaterial }
}

// MARK: - View extension (iOS 26 样式便捷 modifier)

extension View {
    /// iOS 26 卡片风格：圆角 20 + 连续圆角 + 毛玻璃材质 + 轻阴影 + 可选边框
    /// 用于 DayDetailView / MonthView 底部面板
    func ios26Card(cornerRadius: CGFloat = 20,
                   material: Material = .cardSurface,
                   borderColor: Color = .clear,
                   borderWidth: CGFloat = 0,
                   shadowOpacity: Double = 0.06) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(material)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor.opacity(0.6), lineWidth: borderWidth)
            )
            .shadow(color: .black.opacity(shadowOpacity),
                    radius: shadowOpacity > 0 ? 10 : 0,
                    x: 0, y: 4)
    }
}

// MARK: - 液态玻璃 (Liquid Glass) — iOS 26+ 原生 glassEffect 封装
// iOS 26 引入 glassEffect / GlassEffectContainer，提供实时折射的液态玻璃质感。
// 旧版本回退到 Material (thinMaterial / thickMaterial) 毛玻璃，保证跨版本一致性。

extension View {
    /// 液态玻璃卡片：iOS 26+ 使用 glassEffect，旧版本回退到 ios26Card
    func liquidGlassCard(
        cornerRadius: CGFloat = 20,
        borderColor: Color = .clear,
        borderWidth: CGFloat = 0,
        shadowOpacity: Double = 0.06,
        interactive: Bool = false
    ) -> some View {
        glassCardFallback(
            cornerRadius: cornerRadius,
            borderColor: borderColor,
            borderWidth: borderWidth,
            shadowOpacity: shadowOpacity,
            interactive: interactive
        )
    }
}

// MARK: - 平台分发实现

extension View {
    // 卡片
    @ViewBuilder
    fileprivate func glassCardFallback(
        cornerRadius: CGFloat,
        borderColor: Color,
        borderWidth: CGFloat,
        shadowOpacity: Double,
        interactive: Bool
    ) -> some View {
        #if canImport(UIKit)
        // iOS 26 GlassEffect / LiquidGlass 在 Xcode 公开 SDK（截至 iOS 18 GM）中尚未正式声明，
        // 直接写 `GlassEffect.regular` 会触发 "Cannot find 'GlassEffect' in scope"。
        // 为了让当前 Xcode App Target 能过编译，这里统一使用 iOS 15+ 的 thickMaterial +
        // 半透明渐变高光来模拟液态玻璃的折射/高光感；一旦 Apple 公开 Liquid Glass API，
        // 只要把下面 iOS 26 分支换回 .glassEffect(GlassEffect...) 即可。
        if #available(iOS 26.0, *) {
            self
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.thickMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        // 顶部内高光，模拟折射边缘
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .white.opacity(interactive ? 0.45 : 0.25),
                                    .white.opacity(0.04)
                                ],
                                startPoint: .top, endPoint: .bottom
                            ),
                            lineWidth: 0.6
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(borderColor.opacity(0.6), lineWidth: borderWidth)
                )
                .shadow(color: .black.opacity(shadowOpacity),
                        radius: shadowOpacity > 0 ? 8 : 0,
                        x: 0, y: 3)
        } else {
            self
                .ios26Card(
                    cornerRadius: cornerRadius,
                    material: .cardSurface,
                    borderColor: borderColor,
                    borderWidth: borderWidth,
                    shadowOpacity: shadowOpacity
                )
        }
        #else
        self
            .ios26Card(
                cornerRadius: cornerRadius,
                material: .cardSurface,
                borderColor: borderColor,
                borderWidth: borderWidth,
                shadowOpacity: shadowOpacity
            )
        #endif
    }
}

// MARK: - 外观模式 (浅色 / 深色 / 跟随系统)

public enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system   = "system"
    case light    = "light"
    case dark     = "dark"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light:  return "浅色"
        case .dark:   return "深色"
        }
    }

    public var iconName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        }
    }

    /// 转换为 SwiftUI 的 ColorScheme?（nil = 跟随系统）
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

#endif
