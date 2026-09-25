import Foundation

// MARK: - DeepLink 路由（P0-3）
//
// 统一处理 qinghe:// 深链：
// - qinghe://event/<UUID>     → 打开事件详情编辑页
// - qinghe://countdown/<UUID> → 打开倒数日列表并聚焦该条（倒数日 / 纪念日卡片点击）
// - qinghe://calendar         → 切到日历入口（三个桌面小组件的 widgetURL）
// - qinghe://calendar/date/<yyyy-MM-dd> → 跳日历到指定日期
// - qinghe://ai               → 打开 AI 助手
//
// ⚠️ scheme 必须在主 App 的 Info.plist 声明 CFBundleURLTypes，否则系统不会把
//    qinghe:// 交给本 App，上列路由全部收不到（曾长期缺失，表现为点什么都没反应）。

@MainActor
public enum DeepLinkRouter {

    /// 待处理深链在 UserDefaults 中的键（与宿主约定，键名保持兼容）
    private static let pendingKey = "pending-deeplink"

    /// 收到外部唤起 URL 的统一入口（`AppRootView` 的 `.onOpenURL` 转发到此）。
    ///
    /// 必须在这里立即消费：App 已在前台时 scenePhase 不会变化，
    /// 只依赖 `onAppear` / `.active` 消费的旧写法会让点击静默失效。
    public static func receive(_ url: URL) {
        UserDefaults.standard.set(url.absoluteString, forKey: pendingKey)
        handlePendingDeepLink()
    }

    /// 处理待处理深链（冷启动由 AppRootView.onAppear 兜底调用）
    public static func handlePendingDeepLink() {
        guard let raw = UserDefaults.standard.string(forKey: pendingKey),
              let url = URL(string: raw) else { return }
        handle(url)
        UserDefaults.standard.removeObject(forKey: pendingKey)
    }

    /// 处理外部唤起 URL
    public static func handle(_ url: URL) {
        let nav = NavigationCoordinator.shared

        // qinghe://event/<UUID>
        if url.host == "event",
           let uuid = UUID(uuidString: url.lastPathComponent) {
            // P1：直接打开事件详情编辑页（而非仅切日期）
            nav.openEventDetail(uuid)
            return
        }

        // qinghe://countdown/<UUID>（倒数日 / 纪念日 Live Activity 卡片点击直达）
        if url.host == "countdown",
           let uuid = UUID(uuidString: url.lastPathComponent) {
            nav.openCountdownDetail(uuid)
            return
        }

        // qinghe://calendar/date/<yyyy-MM-dd>
        if url.host == "calendar" {
            let path = url.pathComponents
            // path: ["/", "date", "2026-09-22"]
            if path.count >= 3, path[1] == "date",
               let date = parseISODate(path[2]) {
                nav.openEventDate(date)
                return
            }
            // qinghe://calendar（三个桌面小组件的 widgetURL）→ 切到日历入口。
            // 此前这条会落到函数末尾无任何效果：host 是 calendar 但 path 只有 ["/"]，
            // path.count >= 3 不成立，于是点小组件"打开了 App 却停在原来的 Tab"。
            nav.openCalendar()
            return
        }

        // qinghe://ai
        if url.host == "ai" {
            nav.openAIAssistant()
            return
        }
    }

    private static func parseISODate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar(identifier: .gregorian)
        return f.date(from: s)
    }
}
