#if canImport(SwiftUI)
import SwiftUI

// MARK: - AppTheme · DesignToken (iOS 现代风格)
public enum AppTheme {
    public enum Touch {
        /// iOS HIG 最小点击目标
        public static let minTarget: CGFloat = 44
        /// Chip 最小高度（内容 + 呼吸空间）
        public static let chipHeight: CGFloat = 40
        /// 复选框图标尺寸
        public static let checkboxSize: CGFloat = 24
        /// 日历格最小行高（保证 7 列布局下仍可点中）
        public static let minCellHeight: CGFloat = 56
    }
    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 20
        public static let xxl: CGFloat = 28
        public static let section: CGFloat = 24
    }
    public enum Radius {
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 22
        public static let xxl: CGFloat = 28
        public static let pill: CGFloat = 999
    }
    public enum Shadow {
        /// 推荐：静态卡片 / 列表项 / 次级卡片（克制阴影，避免装饰过度）
        public static let resting = (color: Color.black.opacity(0.06),
                                     radius: CGFloat(12),
                                     x: CGFloat(0), y: CGFloat(3))
        /// 推荐：浮动元素 / 主操作按钮 / 选中态强调（清晰但不喧宾夺主）
        public static let elevated = (color: Color.black.opacity(0.12),
                                      radius: CGFloat(18),
                                      x: CGFloat(0), y: CGFloat(6))
        // —— 兼容别名（指向推荐档，旧调用点无需改动）——
        public static let card = resting
        public static let raised = elevated
        public static let floating = (color: Color.black.opacity(0.16),
                                      radius: CGFloat(24),
                                      x: CGFloat(0), y: CGFloat(12))
    }
    public enum Stroke {
        public static let hair: CGFloat = 0.5
        public static let thin: CGFloat = 1
    }
    public enum Font {
        /// P2-8：UIFontMetrics scaled helper —— 固定 pt 基础上随系统 Dynamic Type 缩放。
        /// textStyle 参数类型按平台别名：UIKit 下是 UIFont.TextStyle；
        /// macOS 无 UIFontMetrics，退化为固定字号（textStyle 仅作占位）。
        #if canImport(UIKit)
        private typealias TextStyle = UIFont.TextStyle
        #else
        private enum TextStyle: String {
            case largeTitle, title2, title3, headline, body, subheadline, caption1, caption2
        }
        #endif

        private static func scaled(_ base: CGFloat, weight: SwiftUI.Font.Weight,
                                   design: SwiftUI.Font.Design = .rounded,
                                   textStyle: TextStyle = .body) -> SwiftUI.Font {
            #if canImport(UIKit)
            let metrics = UIFontMetrics(forTextStyle: textStyle)
            let baseFont = UIFont.systemFont(ofSize: base, weight: weight.uiWeight)
            let uiFont: UIFont
            if let descriptor = baseFont.fontDescriptor.withDesign(design.uiDesign) {
                uiFont = UIFont(descriptor: descriptor, size: base)
            } else {
                uiFont = baseFont
            }
            return SwiftUI.Font(metrics.scaledFont(for: uiFont))
            #else
            return .system(size: base, weight: weight, design: design)
            #endif
        }
        public static let hero = scaled(38, weight: .bold, textStyle: .largeTitle)
        public static let title2 = scaled(22, weight: .semibold, textStyle: .title2)
        public static let title3 = scaled(18, weight: .semibold, textStyle: .title3)
        public static let bodyBold = scaled(16, weight: .semibold, textStyle: .headline)
        public static let body = scaled(15, weight: .regular, textStyle: .body)
        public static let subheadline = scaled(13, weight: .medium, textStyle: .subheadline)
        public static let caption = scaled(12, weight: .medium, textStyle: .caption1)
        public static let caption2 = scaled(11, weight: .medium, textStyle: .caption2)
        public static let numeralL = scaled(20, weight: .semibold, textStyle: .headline)
        public static let numeralM = scaled(16, weight: .semibold, textStyle: .body)
        public static let numeralXL = scaled(56, weight: .bold, textStyle: .largeTitle)
    }
    public enum Motion {
        /// 卡片按压弹簧（轻触 → 下沉 → 弹回）
        public static let pressInOut = SwiftUI.Animation.spring(response: 0.22,
                                                                 dampingFraction: 0.72,
                                                                 blendDuration: 0.15)
        /// 月切换/面板展开
        public static let screen = SwiftUI.Animation.spring(response: 0.34,
                                                            dampingFraction: 0.86,
                                                            blendDuration: 0.1)
        /// Toast/Snackbar 滑入
        public static let toast = SwiftUI.Animation.spring(response: 0.3,
                                                          dampingFraction: 0.82,
                                                          blendDuration: 0.08)
    }
}

extension Color {
    /// Foundation 语义色的 public 别名 —— 用来规避某些 Xcode 版本把
    /// Color.separator / Color.themeQuaternaryFill 视为 internal 的问题
    public static var themeSeparator: Color {
        #if canImport(UIKit)
        return Color(UIColor.separator)
        #else
        return Color.black.opacity(0.12)
        #endif
    }
    public static var themeQuaternaryFill: Color {
        #if canImport(UIKit)
        return Color(UIColor.quaternarySystemFill)
        #else
        return Color.black.opacity(0.06)
        #endif
    }
    public static var todayCapsule: Color {
        #if canImport(UIKit)
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor.systemRed.withAlphaComponent(0.22)
                : UIColor.systemRed.withAlphaComponent(0.10)
        })
        #else
        Color.systemRed.opacity(0.10)
        #endif
    }
    public static var hairSeparator: Color { Color.themeSeparator.opacity(0.35) }
    /// P2-6：卡片描边深色模式自适应——深色下提亮，浅色保持克制
    public static var cardBorder: Color {
        #if canImport(UIKit)
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor.separator.withAlphaComponent(0.45)
                : UIColor.separator.withAlphaComponent(0.28)
        })
        #else
        Color.themeSeparator.opacity(0.28)
        #endif
    }
}

/// 跨平台工具条位置：iOS 使用 topBarLeading/topBarTrailing，macOS 回退到语义等价位置。
extension ToolbarItemPlacement {
    public static var platformTopBarLeading: ToolbarItemPlacement {
        #if canImport(UIKit)
        return .topBarLeading
        #else
        return .navigation
        #endif
    }
    public static var platformTopBarTrailing: ToolbarItemPlacement {
        #if canImport(UIKit)
        return .topBarTrailing
        #else
        return .primaryAction
        #endif
    }
}

extension View {
    public func pageBackground() -> some View {
        self.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.systemGroupedBackground.ignoresSafeArea())
    }
    public func modernCard(
        radius: CGFloat = AppTheme.Radius.xl,
        material: Material = .thinMaterial,
        border: Color = .cardBorder,
        shadow: (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) = AppTheme.Shadow.card
    ) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(material)
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(border, lineWidth: AppTheme.Stroke.hair)
        )
        .shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
    /// iOS 26 液态玻璃卡片：双层材料 + 高光边 + 动态阴影
    public func liquidCard(
        radius: CGFloat = AppTheme.Radius.xxl,
        material: Material = .regularMaterial,
        tint: Color = .clear,
        shadow: (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) = AppTheme.Shadow.raised,
        highlight: CGFloat = 0.12
    ) -> some View {
        self
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(material)
                    if tint != .clear {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(tint.opacity(0.12))
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.white.opacity(highlight), lineWidth: AppTheme.Stroke.hair)
                    .blendMode(.overlay)
            )
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.08), Color.clear],
                                         startPoint: .top, endPoint: .center))
                    .frame(height: radius * 0.7)
                    .allowsHitTesting(false)
            }
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.themeSeparator.opacity(0.20), lineWidth: AppTheme.Stroke.hair)
            )
            .shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
    public func capsuleTag(
        fill: Color = Color.themeQuaternaryFill,
        border: Color = .clear,
        hPad: CGFloat = 10,
        vPad: CGFloat = 4
    ) -> some View {
        self.padding(.horizontal, hPad).padding(.vertical, vPad)
            .background(Capsule().fill(fill))
            .overlay(Capsule().stroke(border, lineWidth: AppTheme.Stroke.hair))
    }
    public func constrainReadable(maxWidth: CGFloat = 760) -> some View {
        self.frame(maxWidth: maxWidth)
    }
    public func hideListBackground() -> some View {
        #if canImport(UIKit)
        self.scrollContentBackground(.hidden)
        #else
        self
        #endif
    }
    /// 跨平台大标题：iOS 使用 navigationBarTitleDisplayMode(.large)，macOS 无此概念（空操作）。
    public func largeTitleBar() -> some View {
        #if canImport(UIKit)
        self.navigationBarTitleDisplayMode(.large)
        #else
        self
        #endif
    }
    /// 跨平台行内标题：iOS 使用 navigationBarTitleDisplayMode(.inline)，macOS 空操作。
    public func inlineTitleBar() -> some View {
        #if canImport(UIKit)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
    /// 统一将交互元素扩展到最小 44×44 触碰区域（iOS HIG）
    public func touchTarget(min: CGFloat = AppTheme.Touch.minTarget) -> some View {
        self.frame(minWidth: min, minHeight: min, alignment: .center)
            .contentShape(Rectangle())
    }
    /// 按压反馈：按下时缩放到 0.97 + 轻微下沉 + 提亮
    public func pressableFeedback() -> some View {
        modifier(_PressableFeedbackModifier())
    }
    /// 节日染色壁纸：月视图 / 日详情 / 设置页 / 编辑页统一风格
    public func festiveWallpaper(accent: Color) -> some View {
        self.background {
            ZStack {
                Color.systemGroupedBackground
                // 原生风格：极淡节日染色（去掉模糊色斑壁纸特效）
                LinearGradient(
                    colors: [accent.opacity(0.05), Color.clear],
                    startPoint: .top, endPoint: .bottom
                )
            }.ignoresSafeArea()
        }
    }

    // MARK: - 现代化统一组件（iOS 26 · 克制装饰 · 国际主流审美）
    //
    // 设计原则（适配 frontend-design 审美基准到 SwiftUI）：
    // 1. 单层材质 + 单层分隔线 + 单层阴影，避免 5-6 层 overlay 叠加
    // 2. 统一组件消除重复代码，全应用同一视觉语言
    // 3. 阴影 2 档（resting/elevated），不再 3 档冗余
    // 4. 字体阶梯复用 AppTheme.Font，不引入新硬编码

    /// 统一玻璃卡片：克制版液态玻璃（单层 Material + 单层分隔线 + 单层阴影）
    /// 替代旧 liquidCard 的多层 overlay（白高光 + 顶部渐变 + separator stroke + clipShape 叠加）
    /// 注：内部不含 padding，调用方自行控制内边距，便于精确排版
    public func glassCard(
        radius: CGFloat = AppTheme.Radius.xxl,
        material: Material = .regularMaterial,
        tint: Color = .clear,
        shadow: (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) = AppTheme.Shadow.resting
    ) -> some View {
        self
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(material)
                    if tint != .clear {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(tint.opacity(0.10))
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.themeSeparator.opacity(0.20), lineWidth: AppTheme.Stroke.hair)
            )
            .shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// 软标签底（统一散落的 .fill + stroke 写法）
    /// - material 版本：用于 .ultraThinMaterial / .thinMaterial 等系统材质
    public func softChipBackground(
        radius: CGFloat = AppTheme.Radius.lg,
        material: Material = .ultraThinMaterial
    ) -> some View {
        self
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(material))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Color.themeSeparator.opacity(0.18), lineWidth: AppTheme.Stroke.hair))
    }

    /// 软标签底 · Color 版本：用于 Color.quaternarySystemFill 等纯色背景
    public func softChipBackground(
        radius: CGFloat = AppTheme.Radius.lg,
        fill: Color
    ) -> some View {
        self
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Color.themeSeparator.opacity(0.20), lineWidth: AppTheme.Stroke.hair))
    }
}

private struct _PressableFeedbackModifier: ViewModifier {
    @State private var pressed = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed ? 0.975 : 1.0)
            .brightness(pressed ? -0.02 : 0)
            .animation(AppTheme.Motion.pressInOut, value: pressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !pressed { pressed = true } }
                    .onEnded { _ in pressed = false }
            )
    }
}

public struct ChipLabel: View {
    public var title: String
    public var systemImage: String?
    public var tint: Color = .appTint
    public var font: Font = AppTheme.Font.caption
    public var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).font(font).symbolRenderingMode(.hierarchical)
            }
            Text(title).font(font).fontWeight(.semibold)
        }
        .foregroundStyle(tint)
        .capsuleTag(fill: tint.opacity(0.12))
        // 信息胶囊整体作为一个无障碍元素读出（图标 + 标题）
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 按钮样式（统一主/次操作按钮，消除重复的渐变+高光+阴影代码）

/// 主操作按钮：渐变填充 + 单层分隔线 stroke + 单层阴影 + 按压缩放
/// 替代散落在 CalendarMonthView/DayDetailView 的「新建日程」按钮重复代码
public struct PrimaryActionButtonStyle: ButtonStyle {
    public var accent: Color
    public var cornerRadius: CGFloat = AppTheme.Radius.lg
    public init(accent: Color, cornerRadius: CGFloat = AppTheme.Radius.lg) {
        self.accent = accent; self.cornerRadius = cornerRadius
    }
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.Font.bodyBold)
            .frame(maxWidth: .infinity)
            .frame(minHeight: AppTheme.Touch.minTarget)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LinearGradient(
                        colors: [accent, accent.opacity(0.82)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.20), lineWidth: AppTheme.Stroke.hair)
            )
            .shadow(color: accent.opacity(configuration.isPressed ? 0.18 : 0.28),
                    radius: configuration.isPressed ? 6 : 10,
                    x: 0, y: configuration.isPressed ? 2 : 4)
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(AppTheme.Motion.pressInOut, value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// 次操作按钮：thinMaterial + 单层分隔线 stroke + 按压缩放
/// 替代散落的「查看黄历详情」/「查看全部」等次要按钮重复代码
public struct SecondaryActionButtonStyle: ButtonStyle {
    public var accent: Color
    public var cornerRadius: CGFloat = AppTheme.Radius.lg
    public init(accent: Color, cornerRadius: CGFloat = AppTheme.Radius.lg) {
        self.accent = accent; self.cornerRadius = cornerRadius
    }
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.Font.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(minHeight: AppTheme.Touch.minTarget)
            .foregroundStyle(Color.label)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.thinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.themeSeparator.opacity(0.22), lineWidth: AppTheme.Stroke.hair)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(AppTheme.Motion.pressInOut, value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// 危险/删除操作按钮：红色软填充 + 红色 stroke + 按压缩放
/// 替代 EventEditView 内联的删除按钮（fill+stroke+顶部高光 overlay 三层叠加）
public struct DestructiveActionButtonStyle: ButtonStyle {
    public var cornerRadius: CGFloat = AppTheme.Radius.lg
    public init(cornerRadius: CGFloat = AppTheme.Radius.lg) {
        self.cornerRadius = cornerRadius
    }
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.Font.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(minHeight: AppTheme.Touch.minTarget)
            .foregroundStyle(Color.systemRed)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.systemRed.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.systemRed.opacity(0.30), lineWidth: AppTheme.Stroke.hair)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(AppTheme.Motion.pressInOut, value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// 选项 Chip 选择器（pill 形态）：选中态填充 + 未选中态软背景
/// 替代 EventEditView 内 4 处 type/repeat/priority chip 选择的重复 pill + fill + stroke 写法
public struct SelectChipStyle: ButtonStyle {
    public var isSelected: Bool
    public var tint: Color
    public init(isSelected: Bool, tint: Color) {
        self.isSelected = isSelected; self.tint = tint
    }
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.Font.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? .white : Color.label)
            .padding(.horizontal, AppTheme.Spacing.md)
            .frame(minHeight: AppTheme.Touch.chipHeight)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.pill, style: .continuous)
                    .fill(isSelected ? tint : Color.quaternarySystemFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.pill, style: .continuous)
                    .stroke(isSelected ? tint.opacity(0.45) : .clear,
                            lineWidth: AppTheme.Stroke.hair)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(AppTheme.Motion.pressInOut, value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.pill, style: .continuous))
    }
}

#if canImport(UIKit)
private extension SwiftUI.Font.Weight {
    var uiWeight: UIFont.Weight {
        switch self {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }
}
private extension SwiftUI.Font.Design {
    var uiDesign: UIFontDescriptor.SystemDesign {
        switch self {
        case .rounded: return .rounded
        case .monospaced: return .monospaced
        case .serif: return .serif
        default: return .default
        }
    }
}
#endif

#endif
