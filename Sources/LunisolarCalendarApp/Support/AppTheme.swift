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
        public static let card = (color: Color.black.opacity(0.06),
                                  radius: CGFloat(14),
                                  x: CGFloat(0), y: CGFloat(4))
        public static let raised = (color: Color.black.opacity(0.10),
                                    radius: CGFloat(20),
                                    x: CGFloat(0), y: CGFloat(8))
        public static let floating = (color: Color.black.opacity(0.16),
                                      radius: CGFloat(24),
                                      x: CGFloat(0), y: CGFloat(12))
    }
    public enum Stroke {
        public static let hair: CGFloat = 0.5
        public static let thin: CGFloat = 1
    }
    public enum Font {
        public static let hero = SwiftUI.Font.system(size: 38, weight: .bold, design: .rounded)
        public static let title1 = SwiftUI.Font.system(size: 28, weight: .bold, design: .rounded)
        public static let title2 = SwiftUI.Font.system(size: 22, weight: .semibold, design: .rounded)
        public static let title3 = SwiftUI.Font.system(size: 18, weight: .semibold, design: .rounded)
        public static let bodyBold = SwiftUI.Font.system(size: 16, weight: .semibold, design: .rounded)
        public static let body = SwiftUI.Font.system(size: 15, weight: .regular, design: .rounded)
        public static let subheadline = SwiftUI.Font.system(size: 13, weight: .medium, design: .rounded)
        public static let caption = SwiftUI.Font.system(size: 12, weight: .medium, design: .rounded)
        public static let caption2 = SwiftUI.Font.system(size: 11, weight: .medium, design: .rounded)
        public static let numeralL = SwiftUI.Font.system(size: 20, weight: .semibold, design: .rounded)
        public static let numeralM = SwiftUI.Font.system(size: 16, weight: .semibold, design: .rounded)
        public static let numeralXL = SwiftUI.Font.system(size: 56, weight: .bold, design: .rounded)
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
    public static var appBackground: some ShapeStyle {
        LinearGradient(
            colors: [Color.systemGroupedBackground, Color.systemGroupedBackground],
            startPoint: .top, endPoint: .bottom
        )
    }
    public static var appTintSoft: Color { Color.appTint.opacity(0.12) }
    public static var festiveRedSoft: Color { Color.festiveRed.opacity(0.12) }
    public static var todayCapsule: Color { Color.systemRed.opacity(0.10) }
    public static var hairSeparator: Color { Color.separator.opacity(0.35) }
}

extension View {
    public func pageBackground() -> some View {
        self.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.systemGroupedBackground.ignoresSafeArea())
    }
    public func modernCard(
        radius: CGFloat = AppTheme.Radius.xl,
        material: Material = .thinMaterial,
        border: Color = Color.separator.opacity(0.28),
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
                    .stroke(Color.separator.opacity(0.20), lineWidth: AppTheme.Stroke.hair)
            )
            .shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
    public func capsuleTag(
        fill: Color = Color.quaternarySystemFill,
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
                LinearGradient(
                    colors: [accent.opacity(0.09), accent.opacity(0.02), Color.clear],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                Circle().fill(accent.opacity(0.06))
                    .frame(width: 380, height: 380).blur(radius: 80)
                    .offset(x: -140, y: -160)
                Circle().fill(accent.opacity(0.05))
                    .frame(width: 320, height: 320).blur(radius: 72)
                    .offset(x: 120, y: 340)
            }.ignoresSafeArea()
        }
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
    }
}

#endif
