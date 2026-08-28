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
    /// 吉祥红 (黄道吉日)：深色模式降低不透明度避免过曝
    static var auspicious: Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.88, green: 0.35, blue: 0.35, alpha: 0.90)
                : UIColor(red: 0.82, green: 0.22, blue: 0.22, alpha: 0.88)
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
    /// 主题蓝：浅色模式偏暖蓝；深色模式提亮饱和度
    static var appTint: Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.20, green: 0.55, blue: 0.97, alpha: 1.0)
                : UIColor(red: 0.07, green: 0.45, blue: 0.93, alpha: 1.0)
        })
    }
    #else
    // macOS / Linux fallback（固定色值）
    static var festiveRed: Color { Color(red: 0.77, green: 0.10, blue: 0.10) }
    static var auspicious: Color { Color(red: 0.82, green: 0.22, blue: 0.22, opacity: 0.88) }
    static var festiveGold: Color { Color(red: 0.88, green: 0.72, blue: 0.35) }
    static var appTint: Color { Color(red: 0.07, green: 0.45, blue: 0.93) }
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
    /// iOS 26 底层面板（如 Sheet 背景）：极度轻薄
    static var sheetSurface: Material { .ultraThinMaterial }
    /// iOS 26 浮动按钮 / FAB：毛玻璃感
    static var fabSurface: Material { .thickMaterial }
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

    /// iOS 26 Segmented Picker 样式：外层胶囊 + capsule material 背景
    func ios26SegmentedBackground() -> some View {
        self
            .background(
                Capsule()
                    .fill(Color.secondarySystemGroupedBackground)
            )
            .overlay(
                Capsule()
                    .stroke(Color.separator.opacity(0.4), lineWidth: 0.5)
            )
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

    /// 液态玻璃胶囊：用于按钮、徽标等小尺寸元素
    /// iOS 26+ 自动获得 glassEffect 折射 + interactive 弹性动画
    func liquidGlassCapsule(
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        glassCapsuleFallback(tint: tint, interactive: interactive)
    }

    /// 将内容包裹在 GlassEffectContainer 中（iOS 26+）
    /// 确保容器内多个 glass 元素之间的折射一致性
    func liquidGlassContainer<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        glassContainerFallback(content)
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
        if #available(iOS 26.0, *) {
            self
                .glassEffect(
                    interactive
                        ? GlassEffect.regular.interactive()
                        : GlassEffect.regular,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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

    // 胶囊
    @ViewBuilder
    fileprivate func glassCapsuleFallback(
        tint: Color?,
        interactive: Bool
    ) -> some View {
        #if canImport(UIKit)
        if #available(iOS 26.0, *) {
            if interactive {
                self.glassEffect(
                    .regular.interactive().tint(tint ?? .clear),
                    in: Capsule()
                )
            } else if let tint {
                self.glassEffect(
                    .regular.tint(tint),
                    in: Capsule()
                )
            } else {
                self.glassEffect(
                    .regular,
                    in: Capsule()
                )
            }
        } else {
            self
                .background(
                    Capsule()
                        .fill(tint?.opacity(0.12) ?? Color.quaternarySystemFill)
                )
                .overlay(
                    Capsule()
                        .stroke(Color.separator.opacity(0.3), lineWidth: 0.5)
                )
        }
        #else
        self
            .background(
                Capsule()
                    .fill(tint?.opacity(0.12) ?? Color.gray.opacity(0.15))
            )
        #endif
    }

    // 容器
    @ViewBuilder
    fileprivate func glassContainerFallback<Content: View>(
        _ content: () -> Content
    ) -> some View {
        #if canImport(UIKit)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                content()
            }
        } else {
            content()
        }
        #else
        content()
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
