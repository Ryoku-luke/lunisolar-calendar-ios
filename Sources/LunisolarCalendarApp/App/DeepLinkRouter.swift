import Foundation

// MARK: - DeepLink 路由（P0-3）
//
// 统一处理 qinghe:// 深链：
// - qinghe://event/<UUID>   → 打开事件对应日期
// - qinghe://calendar/date/<yyyy-MM-dd> → 跳日历到指定日期
// - qinghe://ai             → 打开 AI 助手

@MainActor
public enum DeepLinkRouter {

    /// 处理待处理深链（App 启动时从 UserDefaults 读取）
    public static func handlePendingDeepLink() {
        guard let raw = UserDefaults.standard.string(forKey: "pending-deeplink"),
              let url = URL(string: raw) else { return }
        handle(url)
        UserDefaults.standard.removeObject(forKey: "pending-deeplink")
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

        // qinghe://calendar/date/<yyyy-MM-dd>
        if url.host == "calendar" {
            let path = url.pathComponents
            // path: ["/", "date", "2026-09-22"]
            if path.count >= 3, path[1] == "date",
               let date = parseISODate(path[2]) {
                nav.openEventDate(date)
                return
            }
        }

        // qinghe://ai
        if url.host == "ai" {
            nav.showAI = true
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
