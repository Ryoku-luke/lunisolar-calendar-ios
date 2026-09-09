import WidgetKit
import SwiftUI
import LunisolarCalendarApp

/// Widget Extension 入口：复用 SPM 包里已实现的 3 个 Widget。
/// App Group ID 必须与宿主 App entitlements 中的 com.apple.security.application-groups 一致。
private let appGroupID = "group.com.lunisolar.calendar"

@main
struct LunisolarWidgetBundle: WidgetBundle {
    var body: some Widget {
        HuangliOverviewWidget(appGroupID: appGroupID)
        LunarCardWidget(appGroupID: appGroupID)
        TodoProgressWidget(appGroupID: appGroupID)
    }
}
