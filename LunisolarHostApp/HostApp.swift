import SwiftUI
import LunisolarCalendarApp

/// 宿主 App 入口。
/// `LunisolarCalendarApp` 作为 dynamic framework 被链接，其内部也有 `@main`，
/// 但 framework 的 `main` 不会成为进程入口，此处的 @main 才是真正的 App 入口。
///
/// App Group ID 必须与 entitlements 中的 com.apple.security.application-groups 一致，
/// 且与 Widget Extension 中使用的 group ID 相同，Widget 才能读到主 App 写的快照。
private let appGroupID = "group.com.lunisolar.calendar"

@main
struct HostApp: App {
    @State private var store = EventStore.shared
    @State private var countdownStore = CountdownStore.shared

    init() {
        // 注入 App Group，让 EventStore 把 Widget 快照写到共享容器。
        EventStore.shared.widgetAppGroupID = appGroupID
    }

    var body: some Scene {
        WindowGroup {
            AdaptiveRootView()
                .environment(store)
                .environment(countdownStore)
        }
    }
}
