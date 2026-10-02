#if canImport(SwiftUI)
import SwiftUI

// MARK: - 「日期胶囊 + 详情」这张卡的排布决策
//
// 背景（执行计划 P3-4）：胶囊里的数字用 `AppTheme.Font.numeralXL`
// （基准 56pt，经 `UIFontMetrics` 按 Dynamic Type 缩放），而胶囊写死了
// `.frame(width: 92)`（当日卡）/ `.frame(width: 110)`（日详情）。
// 默认字号下 92pt 放得下「31」，但辅助字号档位会把 56pt 放大到 2–3 倍
// → 数字被裁掉（无障碍硬缺口：用户把字调大，反而看不见日期）。
//
// 光把宽度放开还不够：横排时数字变宽会挤扁右侧详情列，极端档位下互相重叠。
// 所以辅助字号档位改成**上下堆叠**，让数字独占一行。
//
// 判据抽成纯函数是为了可单测——视图里的分支单测够不着（同 `LayoutIdiom`）。

/// 日期卡（胶囊 + 详情）的排布决策
enum DayCardLayout {

    /// 排布方向：辅助字号档位纵向堆叠，其余横排。
    ///
    /// 用 `isAccessibilitySize` 而不是"某个具体档位"：它正好是
    /// `.accessibility1` 及以上（Apple 对"需要重排"的定义），将来新增档位也自动跟随。
    public static func axis(for typeSize: DynamicTypeSize) -> Axis {
        typeSize.isAccessibilitySize ? .vertical : .horizontal
    }
}
#endif
