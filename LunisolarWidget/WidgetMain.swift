import WidgetKit
import SwiftUI
import LunisolarCalendarApp

/// Widget Extension 入口：复用 SPM 包里已实现的 3 个 Widget + 2 个 Live Activity。
/// App Group ID 必须与宿主 App entitlements 中的 com.apple.security.application-groups 一致。
///
/// ⚠️ 此列表必须与 SPM 包内的 `LunisolarWidgetsBundle`（Sources/.../Widgets/LunisolarWidgetBundle.swift）
/// 保持同步：曾漏注册 `QingheLiveActivityWidget`，导致时间胶囊（提醒/高优先级日程/节气）
/// 在系统侧没有渲染器 —— 灵动岛展开为空条、不显示任何内容。
private let appGroupID = "group.com.lumingfeng.lunisolarcalendar"

@main
struct LunisolarWidgetBundle: WidgetBundle {
    var body: some Widget {
        HuangliOverviewWidget(appGroupID: appGroupID)
        LunarCardWidget(appGroupID: appGroupID)
        TodoProgressWidget(appGroupID: appGroupID)
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            CountdownLiveActivityWidget()   // 倒数日 / 纪念日倒计时
            QingheLiveActivityWidget()      // 时间胶囊（高优先级提醒 / 日程 / 节气）
        }
        #endif
    }
}
