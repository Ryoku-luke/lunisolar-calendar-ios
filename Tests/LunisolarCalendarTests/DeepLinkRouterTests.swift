import XCTest
@testable import LunisolarCalendarApp

// MARK: - 深链路由测试（qinghe://）
//
// 背景：主 App 的 Info.plist 曾长期缺少 CFBundleURLTypes（qinghe:// 未被系统注册），
// 且宿主只把 URL 写进 UserDefaults、等 onAppear / scenePhase 变化才消费，
// 于是「点灵动岛 / 桌面小组件没反应」。
//
// 本文件覆盖路由分支与消费时机（scheme 注册本身只能由 Xcode 打包在真机验证）。

@MainActor
final class DeepLinkRouterTests: XCTestCase {

    private let pendingKey = "pending-deeplink"

    /// 单例导航状态在每个用例前复位，避免用例间互相污染
    private func resetNav() {
        let nav = NavigationCoordinator.shared
        nav.selectedDate = Date()
        nav.phoneTab = .calendar
        nav.iPadSection = nil
        nav.pendingOpenEventID = nil
        nav.pendingOpenCountdownID = nil
        UserDefaults.standard.removeObject(forKey: pendingKey)
    }

    private func url(_ s: String, file: StaticString = #filePath, line: UInt = #line) -> URL {
        guard let u = URL(string: s) else {
            XCTFail("测试用 URL 构造失败：\(s)", file: file, line: line)
            return URL(fileURLWithPath: "/dev/null")
        }
        return u
    }

    // MARK: 桌面小组件入口

    /// 三个桌面小组件都用 `qinghe://calendar`：此前该分支会落到函数末尾无任何效果
    func testWidgetCalendarURLSwitchesToCalendarEntry() {
        resetNav()
        let nav = NavigationCoordinator.shared
        nav.iPadSection = .settings
        #if os(iOS)
        nav.phoneTab = .me
        #endif

        DeepLinkRouter.handle(url("qinghe://calendar"))

        XCTAssertEqual(nav.iPadSection, .calendar, "点小组件应切到日历节，而不是原地不动")
        #if os(iOS)
        XCTAssertEqual(nav.phoneTab, .calendar)
        #endif
    }

    func testCalendarDateURLJumpsToDate() {
        resetNav()
        let nav = NavigationCoordinator.shared

        DeepLinkRouter.handle(url("qinghe://calendar/date/2026-09-22"))

        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day],
                                                                from: nav.selectedDate)
        XCTAssertEqual(c.year, 2026)
        XCTAssertEqual(c.month, 9)
        XCTAssertEqual(c.day, 22)
        XCTAssertEqual(nav.iPadSection, .calendar, "iPad 上日期只在日历节可见")
    }

    // MARK: 卡片 / 通知点击

    func testEventURLOpensPendingEventDetail() {
        resetNav()
        let nav = NavigationCoordinator.shared
        let id = UUID()

        DeepLinkRouter.handle(url("qinghe://event/\(id.uuidString)"))

        XCTAssertEqual(nav.pendingOpenEventID, id)
        XCTAssertEqual(nav.iPadSection, .calendar)
        #if os(iOS)
        XCTAssertEqual(nav.phoneTab, .calendar)
        #endif
    }

    func testCountdownURLOpensCountdownSection() {
        resetNav()
        let nav = NavigationCoordinator.shared
        let id = UUID()

        DeepLinkRouter.handle(url("qinghe://countdown/\(id.uuidString)"))

        XCTAssertEqual(nav.pendingOpenCountdownID, id)
        XCTAssertEqual(nav.iPadSection, .countdown)
    }

    #if os(iOS)
    func testAIURLSwitchesToAITab() {
        resetNav()
        let nav = NavigationCoordinator.shared

        DeepLinkRouter.handle(url("qinghe://ai"))

        XCTAssertEqual(nav.phoneTab, .ai)
    }
    #endif

    // MARK: 消费时机（本轮修复的核心）

    /// App 已在前台收到 URL：必须立即消费，且不得残留待处理键
    func testReceiveHandlesImmediatelyAndLeavesNoPendingKey() {
        resetNav()
        let nav = NavigationCoordinator.shared
        let id = UUID()

        DeepLinkRouter.receive(url("qinghe://event/\(id.uuidString)"))

        XCTAssertEqual(nav.pendingOpenEventID, id, "前台点击必须立即生效，不能等 scenePhase 变化")
        XCTAssertNil(UserDefaults.standard.string(forKey: pendingKey),
                     "消费后不得残留待处理键，否则会在下次前后台切换时错误重放")
    }

    /// 冷启动路径：键只被消费一次
    func testHandlePendingDeepLinkConsumesKeyOnce() {
        resetNav()
        let nav = NavigationCoordinator.shared
        let id = UUID()
        UserDefaults.standard.set("qinghe://event/\(id.uuidString)", forKey: pendingKey)

        DeepLinkRouter.handlePendingDeepLink()
        XCTAssertEqual(nav.pendingOpenEventID, id)

        nav.pendingOpenEventID = nil
        DeepLinkRouter.handlePendingDeepLink()
        XCTAssertNil(nav.pendingOpenEventID, "键已消费，重复调用不得重复导航")
    }

    // MARK: 健壮性

    func testMalformedURLsAreIgnored() {
        resetNav()
        let nav = NavigationCoordinator.shared
        let before = nav.selectedDate

        for s in ["qinghe://event/not-a-uuid",
                  "qinghe://event/",
                  "qinghe://countdown/",
                  "qinghe://calendar/date/xxxx-xx-xx",
                  "qinghe://calendar/date/2026-13-45",
                  "qinghe://unknown",
                  "qinghe://",
                  "https://example.com/event/\(UUID().uuidString)"] {
            DeepLinkRouter.handle(url(s))
        }

        XCTAssertNil(nav.pendingOpenEventID, "非法 UUID 不得写入待打开事件")
        XCTAssertNil(nav.pendingOpenCountdownID)
        XCTAssertEqual(nav.selectedDate, before, "非法深链不得改动导航状态")
    }
}
