#if canImport(SwiftUI)
import SwiftUI

// MARK: - 「是不是 iPad 那套分栏布局」的唯一判据
//
// 背景（执行计划 P3-2）：判断根视图与月历网格是否走 iPad 分栏，原先用的是
// `horizontalSizeClass == .regular`。但 **iPhone Plus/Max 横屏也是 regular** ——
// 于是手机被当成 iPad：根视图切成三栏、底部 TabBar 消失（`DEVICE_TEST_CHECKLIST`
// 里标注未验证的那条），月历网格也切到 iPad 的弹性行高布局。
//
// sizeClass 回答的是「有多宽」，不是「是什么设备」。要问后者就得看设备形态。
//
// 保留 sizeClass 这一半条件是**刻意的**：iPad 在分屏/侧拉里宽度变 compact 时，
// 现有行为是回落到手机式单栏（窄栏更适合单栏），这里不改变它。

/// 布局取向：把「设备形态 + 宽度类别」两个输入合成一个可单测的纯函数。
public enum LayoutIdiom {

    /// 平台无关的设备形态（macOS 侧没有 `UIDevice`）。
    /// - Note: 只区分"会不会用 iPad 那套分栏"，不追求穷举所有形态。
    public enum Device: Sendable, Equatable {
        case phone
        case pad
        case mac
        case other
    }

    /// 是否使用 iPad 分栏布局（三栏 / 双栏 + 弹性网格）。
    ///
    /// - 必须**同时**是 iPad **且**宽度为 regular：
    ///   - iPhone 横屏（regular）→ false：手机永远保留底部 TabBar（P3-2 的验收）；
    ///   - iPad 分屏/侧拉（compact）→ false：窄栏回落单栏（保持既有行为）；
    ///   - 宽度未知（`nil`，例如某些宿主环境）→ false：保守走单栏，避免误切三栏。
    public static func usesSplitLayout(device: Device,
                                       horizontalSizeClass: UserInterfaceSizeClass?) -> Bool {
        device == .pad && horizontalSizeClass == .regular
    }

    /// 当前设备形态
    public static var current: Device {
        #if canImport(UIKit)
        switch UIDevice.current.userInterfaceIdiom {
        case .phone:  return .phone
        case .pad:    return .pad
        case .mac:    return .mac
        default:      return .other
        }
        #else
        return .mac
        #endif
    }

    /// 当前环境是否走 iPad 分栏（视图侧的唯一入口）
    public static func usesSplitLayout(horizontalSizeClass: UserInterfaceSizeClass?) -> Bool {
        usesSplitLayout(device: current, horizontalSizeClass: horizontalSizeClass)
    }
}
#endif
