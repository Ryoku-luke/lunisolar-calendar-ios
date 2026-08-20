#if canImport(WidgetKit)
import WidgetKit
import SwiftUI

// MARK: - 3 种 Widget 封装 + Bundle

/// ① 今日黄历概览 Widget
@available(iOSApplicationExtension 17.0, *)
public struct HuangliOverviewWidget: Widget {
    public let kind: String = "HuangliOverview"
    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LunisolarWidgetTimelineProvider()) { entry in
            HuangliOverviewWidgetView(entry: entry)
        }
        .configurationDisplayName("今日黄历概览")
        .description("查看当日宜忌、冲煞、五行和节日，最常看的黄历信息一屏掌握。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

/// ② 农历日期卡片 Widget
@available(iOSApplicationExtension 17.0, *)
public struct LunarCardWidget: Widget {
    public let kind: String = "LunarCard"
    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LunisolarWidgetTimelineProvider()) { entry in
            LunarCardWidgetView(entry: entry)
        }
        .configurationDisplayName("农历日期卡片")
        .description("大字号显示农历月日和传统节日、节日主题色渐变，一眼掌握今天是农历几月几日。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

/// ③ 今日待办进度 Widget
@available(iOSApplicationExtension 17.0, *)
public struct TodoProgressWidget: Widget {
    public let kind: String = "TodoProgress"
    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LunisolarWidgetTimelineProvider()) { entry in
            TodoProgressWidgetView(entry: entry)
        }
        .configurationDisplayName("今日待办进度")
        .description("环形进度条展示今日已完成日程占比，激励每日打卡，Medium 尺寸还显示节日与冲煞信息。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

// MARK: - WidgetBundle 入口

/// 宿主 Widget Extension 里只要：
///   ```
///   @main
///   struct LunisolarWidgetsBundle: WidgetBundle {
///       var body: some Widget {
///           HuangliOverviewWidget()
///           LunarCardWidget()
///           TodoProgressWidget()
///       }
///   }
///   ```
/// 直接复用此处的 3 个 Widget 实现即可。
@available(iOSApplicationExtension 17.0, *)
public struct LunisolarWidgetsBundle: WidgetBundle {
    public init() {}

    @WidgetBundleBuilder
    public var body: some Widget {
        HuangliOverviewWidget()
        LunarCardWidget()
        TodoProgressWidget()
    }
}
#endif
