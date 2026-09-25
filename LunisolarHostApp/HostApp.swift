import SwiftUI
import LunisolarCalendarApp

/// 宿主 App 入口。
/// `LunisolarCalendarApp` 作为 dynamic framework 被链接，其内部也有 `@main`，
/// 但 framework 的 `main` 不会成为进程入口，此处的 @main 才是真正的 App 入口。
///
/// App Group ID 必须与 entitlements 中的 com.apple.security.application-groups 一致，
/// 且与 Widget Extension 中使用的 group ID 相同，Widget 才能读到主 App 写的快照。
private let appGroupID = "group.com.lumingfeng.lunisolarcalendar"

@main
struct HostApp: App {
    init() {
        // 注入 App Group，让 EventStore 把 Widget 快照写到共享容器。
        EventStore.shared.widgetAppGroupID = appGroupID
    }

    var body: some Scene {
        WindowGroup {
            // 生命周期接线（iCloud 启动重建/后台落盘/通知续排/外观偏好）
            // 全部封装在框架内 AppRootView，宿主不重复实现。
            // 深链（qinghe://）交由框架内的 AppRootView 统一处理（onOpenURL → DeepLinkRouter）。
            // 宿主不再自己转存 UserDefaults：原先"只写键、等 onAppear / scenePhase 消费"的写法，
            // 在 App 已处于前台时没有任何消费点，表现为点灵动岛 / 小组件没反应。
            AppRootView()
        }
    }
}
