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
                                       horizontalSizeClass: UserInterfaceSizeClass?,
                                       verticalSizeClass: UserInterfaceSizeClass? = nil) -> Bool {
        _ = device   // 保留参数以兼容既有调用；判据不再依赖设备种类（折叠屏 idiom 仍是 .phone）
        // 2026-10-22 折叠屏适配：**同时看宽与高**，而不是只看宽。
        //
        // 为什么不能只看"宽"（P3-2 的教训）：iPhone Plus/Max **横屏**宽度也是 regular，
        // 只看宽会把手机切成三栏、TabBar 消失（仓库有专门的源码扫描守卫禁止这么写）。
        //
        // 为什么"高"能区分：横屏手机是**宽而矮**（vertical == .compact）；
        // iPad 与**折叠屏展开**都是**宽而高**（vertical == .regular）。
        //
        // ⚠️ 已知未知：iPhone Duo 展开后 horizontalSizeClass 是否报 .regular，SDK 无公开说明；
        //   若实测仍为 .compact，则本条规则不足以分栏，下一步需要把容器宽度提到分栏决策之上
        //   （宽度通道）。这一点必须由真机/模拟器实测确认，不能靠猜。
        guard horizontalSizeClass == .regular else { return false }
        guard verticalSizeClass != .compact else { return false }
        return true
    }

    /// 当前设备形态。
    ///
    /// ⚠️ 必须标 `@MainActor`：iOS 26 SDK 里 `UIDevice.current` 本身是主线程隔离的
    /// （`UIDevice` 是主线程单例，`userInterfaceIdiom` 随之隔离）。不标就会在
    /// Swift 6 严格并发下报「Main actor-isolated property 'userInterfaceIdiom'
    /// can not be referenced from a nonisolated context」——**Xcode 里 4 条警告**。
    /// 消费方全是 SwiftUI 视图（`body` 本身在主线程）与单测，标主线程隔离没有代价。
    @MainActor
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

    /// 当前环境是否走 iPad 分栏（视图侧的唯一入口）。
    /// 读 `current`（MainActor 隔离）→ 本方法也必须 `@MainActor`；调用方均为视图 body。
    @MainActor
    public static func usesSplitLayout(horizontalSizeClass: UserInterfaceSizeClass?,
                                       verticalSizeClass: UserInterfaceSizeClass? = nil) -> Bool {
        usesSplitLayout(device: current,
                        horizontalSizeClass: horizontalSizeClass,
                        verticalSizeClass: verticalSizeClass)
    }
}
#endif
