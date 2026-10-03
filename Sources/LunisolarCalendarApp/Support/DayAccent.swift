#if canImport(SwiftUI)
import SwiftUI

// MARK: - 控件层强调色（对比度分层）
//
// 背景（审查报告 P0-4）：节日强调色是**任意 hex**，直接拿去当控件色必然踩 WCAG。
// 实测全仓 23 个节日色里，**10 个**的白字对比度不达 AA(4.5:1)：
//   儿童节 #FDD835 1.40:1 ／ 中秋节 #F9A825 1.97:1 ／ 劳动节·万圣节 #FB8C00 2.37:1
//   重阳节 #F57C00 2.70:1 ／ 植树节 #43A047 3.30:1 ／ 青年节 #1E88E5 3.68:1
//   妇女节 #EC407A 3.76:1 ／ 元宵节 #E65100 3.79:1 ／ 情人节 #E91E63 4.35:1
// 而报告要求「控件白字 ≥4.5:1」——中秋那天的主按钮正是金底白字。
//
// 所以强调色分两级：
// - **装饰层**（页面染色、描边、格子染色、节日标签）：用节日原色，不受对比度约束；
// - **控件层**（填充按钮里的白字 / tint 的文字与图标）：必须过门槛，
//   做法是**保留色相、把亮度压暗或提亮到达标**——比「一律回落 appTint」更能保住节日识别度。
//
// 门槛取 WCAG 2.1 正文标准的 4.5:1。

/// WCAG 2.1 对比度工具。纯色值运算，不依赖 UIKit，单测可直接遍历全量节日色。
public enum AccentContrast {
    /// WCAG 正文门槛
    public static let threshold = 4.5

    /// sRGB 相对亮度（WCAG 2.1 定义）
    public static func relativeLuminance(hex: String) -> Double {
        let (r, g, b) = components(hex)
        func linear(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    /// 两色对比度（对称）
    public static func ratio(_ a: String, _ b: String) -> Double {
        let la = relativeLuminance(hex: a), lb = relativeLuminance(hex: b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// 白字压在该色上的对比度（填充按钮的判据）
    public static func whiteOn(hex: String) -> Double { ratio("#FFFFFF", hex) }

    /// 该色压在深色页面底上的对比度（深色模式 tint 文字的判据）
    public static func onBlack(hex: String) -> Double { ratio("#000000", hex) }

    /// 白 / 黑里对比度更高的那一支 —— 选中格文字色用它。
    ///
    /// 为什么是「挑色」而不是「把填充压暗到白字达标」：
    /// - 压暗会把节日色洗掉（儿童节黄、中秋金正是最需要保住识别度的两个）；
    /// - 而**任一填充色**在白/黑里至少有一支达标：两者相等的最坏点在亮度 ≈0.179，
    ///   此时对比度 ≈4.58:1 > 门槛 4.5。也就是说这条路上不存在"选不出一支达标色"的情况。
    public static func bestForeground(hex: String) -> (hex: String, ratio: Double) {
        let asWhiteText = whiteOn(hex: hex)   // 白字压在该色上
        let asBlackText = onBlack(hex: hex)   // 黑字压在该色上（= 该色对黑底的比值，对称）
        return asWhiteText >= asBlackText ? ("#FFFFFF", asWhiteText) : ("#000000", asBlackText)
    }

    /// 保留色相、向黑混合，直到白字达标（原色已达标则原样返回）
    public static func darkenedForWhiteText(hex: String) -> String {
        guard whiteOn(hex: hex) < threshold else { return hex }
        return blend(hex, toward: "#000000", until: { whiteOn(hex: $0) >= threshold })
    }

    /// 保留色相、向白混合，直到深色底上达标（原色已达标则原样返回）
    public static func lightenedForDarkBackground(hex: String) -> String {
        guard onBlack(hex: hex) < threshold else { return hex }
        return blend(hex, toward: "#FFFFFF", until: { onBlack(hex: $0) >= threshold })
    }

    // MARK: - 内部

    static func components(_ hex: String) -> (Double, Double, Double) {
        let h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        return (Double((v >> 16) & 0xFF) / 255,
                Double((v >> 8) & 0xFF) / 255,
                Double(v & 0xFF) / 255)
    }

    private static func toHex(_ r: Double, _ g: Double, _ b: Double) -> String {
        func clamp(_ x: Double) -> Int { Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", clamp(r), clamp(g), clamp(b))
    }

    /// 以 5% 步长向目标色混合，直到满足条件。步长足够细，结果稳定可复现
    /// （纯函数、无随机、无浮点依赖平台差异，单测可断言精确 hex）。
    private static func blend(_ hex: String,
                              toward target: String,
                              until satisfied: (String) -> Bool) -> String {
        let (r1, g1, b1) = components(hex)
        let (r2, g2, b2) = components(target)
        var t = 0.0
        while t < 1.0 {
            t += 0.05
            let candidate = toHex(r1 + (r2 - r1) * t, g1 + (g2 - g1) * t, b1 + (b2 - b1) * t)
            if satisfied(candidate) { return candidate }
        }
        return target
    }
}

// MARK: - Color 便捷入口

extension Color {
    /// 控件层·填充：带白字的按钮用它。节日原色若白字不达标，自动压暗到达标。
    /// 两种模式共用一支——按钮里的字始终是白的，判据与模式无关。
    static func controlFill(festivalHex: String?) -> Color {
        guard let hex = festivalHex else { return .appTint }
        return Color(hex: AccentContrast.darkenedForWhiteText(hex: hex))
    }

    /// 控件层·着色：`tint` / 图标 / 文字用它。
    /// 浅色模式要「深到白底上看得清」，深色模式要「亮到黑底上看得清」——方向相反，故按模式分支。
    static func controlTint(festivalHex: String?) -> Color {
        guard let hex = festivalHex else { return .appTint }
        #if canImport(UIKit)
        return Color(UIColor { traits in
            let safe = traits.userInterfaceStyle == .dark
                ? AccentContrast.lightenedForDarkBackground(hex: hex)
                : AccentContrast.darkenedForWhiteText(hex: hex)
            return UIColor(Color(hex: safe))
        })
        #else
        return Color(hex: AccentContrast.darkenedForWhiteText(hex: hex))
        #endif
    }
}

/// 选中态格内文字色的**唯一决策点**。
///
/// 为什么单独抽出来：审查报告的验收要求「测试覆盖这条真实路径，而不只是助手函数」，
/// 而这条路径原先写在 `DayCellView`（SwiftUI 视图）里 —— 视图本体在单测里够不着。
/// 抽成纯函数后，`SelectedCellContrastTests` 能对**全部真实节日色**跑这条决策。
///
/// 规则：
/// - 有节日色 → 按亮度在白/黑里挑对比度更高的一支（填充仍是节日原色，不压暗：
///   压暗会把儿童节黄、中秋金洗掉，而识别度正是这些颜色的价值）；
/// - 无节日色 → 白色（选中日是品牌色填充，沿用既有视觉契约，见计划里的 D8）。
///
/// ⚠️ 返回的颜色必须**不透明**：半透明白会把实际对比度拉到校验值以下
/// （实测 0.9 白字最差 3.94:1，而门槛是 4.5）。
enum SelectedCellForeground {
    static func resolve(festivalHex: String?) -> Color {
        guard let hex = festivalHex else { return .white }
        return Color(hex: AccentContrast.bestForeground(hex: hex).hex)
    }
}

/// 某个日期的节日强调色，按 P0-4 的要求分成**装饰层**与**控件层**。
///
/// 用法：视图里一次算好，装饰处用 `decorative`，控件处用 `controlFill` / `controlTint`。
public struct DayAccent {
    /// 装饰层：节日原色；当天无节日时回落 appTint
    public let decorative: Color
    /// 控件层·填充（带白字的按钮）
    public let controlFill: Color
    /// 控件层·着色（tint / 图标 / 文字）
    public let controlTint: Color

    public init(date: Date) {
        let hex = FestivalManager.festivals(on: date, lunar: date.lunar).first?.accentHex
        decorative = hex.map { Color(hex: $0) } ?? .appTint
        controlFill = .controlFill(festivalHex: hex)
        controlTint = .controlTint(festivalHex: hex)
    }
}

#endif

/// 选中日格子的**填充色**（D8，2026-10-04）。
///
/// 为什么不能直接用 `appTint`（#4B6FF2）：白字在它上面只有 **4.33:1**，低于 AA 的 4.5——
/// 而格子里那行农历是小字号，必须达标。
///
/// 取舍：**只压到刚好够**（亮度降约 5%，肉眼几乎无差），而不是把整个品牌色改暗——
/// 按钮、强调色等处的 `appTint` 一点不动，品牌观感不变。备选方案（选中日改黑字）
/// 会让同一品牌的蓝底上一处白字一处黑字，反而不一致，故未采用。
public enum SelectedCellFill {
    /// `#4B6FF2` 压到「白字 ≥4.5:1」的最小压暗结果
    public static let brandHex = AccentContrast.darkenedForWhiteText(hex: "#4B6FF2")
    public static var color: Color { Color(hex: brandHex) }
}
