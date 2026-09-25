import XCTest
import UIKit

// MARK: - 清和日历 UI 测试
//
// 覆盖《UI 整体界面打磨总报告》§55 要求的真实用户路径。原有的 3 条冒烟测试已删除：
// 它们断言了已不存在的文案（「保存修改」）、不存在的标识（「月历网格」），
// 且第三条只断言 staticTexts.count > 5，属空断言。
//
// 设计约定（都是踩过的坑，别改）：
// 1. **强制简体中文**：App 的字符串键就是简体中文原文，模拟器若为英文会走 en.lproj，
//    所有基于文案的断言都会失配。用 launchArguments 固定语言/地区。
// 2. **优先按 accessibilityIdentifier 定位**，文案只作兜底。
// 3. **不假设初始数据为空**：模拟器上的 App 容器跨运行保留，因此只断言「这次造的东西出现了」，
//    绝不依赖「原本没有」。
// 4. **用 `element(_:_:)` 而不是绑死元素类型**：SwiftUI 的 `TextField(axis:.vertical)`、
//    `Toggle`、`HStack+accessibilityIdentifier` 在 XCUITest 里映射到的类型会随 SDK 变化，
//    按标识全类型查找才不会因为类型变了就失败。

/// 与 App 侧 `Sources/LunisolarCalendarApp/Support/AccessibilityID.swift` 保持一致的**字面量副本**。
///
/// 为什么不复用那个类型：UI 测试 target 没有链接 App 的框架模块，无法 import。
/// 失配不会静默——找不到元素就是测试红，因此可以接受这份副本；
/// 而 App 侧的命名规范与格式由 `AccessibilityIDTests` 锁住。
private enum ID {
    static let monthNewEvent = "calendar.month.new"
    static let todayJump = "calendar.month.today"
    static let selectedSummary = "calendar.selected.summary"
    static let editTitle = "event.edit.title"
    static let editSave = "event.edit.save"
    static let aiInput = "ai.input.draft"
    static let aiParse = "ai.input.parse"
    static let aiConfirm = "ai.preview.confirm"
    static let aiDone = "ai.input.done"
    static let settingsSyncToggle = "settings.sync.toggle"
    static let settingsSyncStatus = "settings.sync.status"
    static let iPadSidebarCalendar = "ipad.sidebar.calendar"
    static let iPadSidebarCountdown = "ipad.sidebar.countdown"

    /// 必须与 App 侧 `AccessibilityID.monthDay` 的格式完全一致
    static func monthDay(year: Int, month: Int, day: Int) -> String {
        String(format: "calendar.month.day.y%04dm%02dd%02d", year, month, day)
    }
}

final class LunisolarCalendarUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - 基础工具

    @discardableResult
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        // 固定语言/地区：否则英文模拟器下界面走 en.lproj，文案断言全部失配
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_Hans_CN"]
        app.launch()
        return app
    }

    /// 按标识查找元素，不关心它映射成哪一类（textField / textView / other / button…）
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// 当前月份的月中日（15 号）。
    ///
    /// 为什么必须是月中日：跟手滑动时相邻两个月的网格会**同时渲染**（`calendarShell` 会被
    /// 调用两次），月初/月末的日期会在两个网格里各出现一次 → 同一个 accessibilityIdentifier
    /// 匹配到多个元素，测试随之变得不稳定。月中日只会出现在当月网格里。
    private var midMonthTarget: (year: Int, month: Int, day: Int) {
        let cal = Calendar(identifier: .gregorian)
        let c = cal.dateComponents([.year, .month], from: Date())
        return (c.year ?? 2026, c.month ?? 1, 15)
    }

    private func todayTarget() -> (year: Int, month: Int, day: Int) {
        let cal = Calendar(identifier: .gregorian)
        let c = cal.dateComponents([.year, .month, .day], from: Date())
        return (c.year ?? 2026, c.month ?? 1, c.day ?? 1)
    }

    /// 往下滚动直到元素出现（设置页很长）
    private func scrollUntilVisible(_ app: XCUIApplication,
                                    _ target: XCUIElement,
                                    maxSwipes: Int = 8) -> Bool {
        for _ in 0..<maxSwipes {
            if target.exists { return true }
            app.swipeUp()
        }
        return target.exists
    }

    // MARK: - Flow 1：打开 → 点日期 → 选中态与当日摘要跟随

    func testFlow1_selectingDayUpdatesSelectionAndSummary() {
        let app = launchApp()

        let target = midMonthTarget
        let cell = element(app, ID.monthDay(year: target.year, month: target.month, day: target.day))
        XCTAssertTrue(cell.waitForExistence(timeout: 15),
                      "月历网格里应出现本月 \(target.day) 日（标识 \(ID.monthDay(year: target.year, month: target.month, day: target.day))）")

        let wasSelected = cell.isSelected
        cell.tap()

        XCTAssertTrue(cell.isSelected, "点击后该日期格应带上选中态（.isSelected）")

        // 选中日摘要卡必须渲染出来（农历/黄历/天气都挂在它里面）
        XCTAssertTrue(element(app, ID.selectedSummary).waitForExistence(timeout: 5),
                      "选中日期后应出现选中日摘要卡")

        // 反向断言：原来选中的「今天」应让出选中态（除非本来就点的是今天）
        let today = todayTarget()
        let isTargetToday = (today.year == target.year
                             && today.month == target.month
                             && today.day == target.day)
        if !wasSelected && !isTargetToday {
            let todayCell = element(app, ID.monthDay(year: today.year, month: today.month, day: today.day))
            if todayCell.exists {
                XCTAssertFalse(todayCell.isSelected,
                               "选中其它日期后，今天不应仍处于选中态（选中态必须唯一）")
            }
        }
    }

    // MARK: - Flow 2：新建日程 → 保存 → 回日历能看到

    func testFlow2_createEventThenItAppearsOnCalendar() {
        let app = launchApp()

        // 唯一标题：模拟器容器跨运行保留，固定标题会与历史数据混淆
        let title = "UI测试事件-\(Int(Date().timeIntervalSince1970))"

        let addButton = element(app, ID.monthNewEvent)
        XCTAssertTrue(addButton.waitForExistence(timeout: 15), "工具栏应有新建日程按钮")
        addButton.tap()

        let titleField = element(app, ID.editTitle)
        XCTAssertTrue(titleField.waitForExistence(timeout: 5), "编辑页应出现标题输入框")
        titleField.tap()
        titleField.typeText(title)

        let saveButton = element(app, ID.editSave)
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5), "编辑页应有保存按钮")
        saveButton.tap()

        // 回到日历后，当日安排里应能看到刚建的事件标题
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 10),
                      "保存后应回到日历，且当天安排里出现「\(title)」")
    }

    // MARK: - Flow 3：AI 助手必须对输入有反应（用户反馈过「点了没反应」）

    func testFlow3_aiAssistantReactsToInput() {
        let app = launchApp()

        app.tabBars.buttons["AI 助手"].tap()

        let input = element(app, ID.aiInput)
        XCTAssertTrue(input.waitForExistence(timeout: 10), "AI 助手应有输入区")
        input.tap()
        // 用中性的输入：本用例断言的是「有反应」，不是解析正确性
        // （解析正确性由 43 条 AIAssistantTests / 18 条边界用例在单测层覆盖）
        input.typeText("测试输入")
        // 先确认文字真的进去了：CJK 输入若失败，后面的断言会指向错误的方向
        XCTAssertEqual(input.value as? String, "测试输入", "输入框应包含刚键入的文本")

        let parseButton = element(app, ID.aiParse)
        XCTAssertTrue(parseButton.waitForExistence(timeout: 5), "应有「解析并预览」按钮")
        parseButton.tap()

        // 期望：要么出现预览（含确认创建），要么弹出明确的错误提示；绝不能毫无反应
        let preview = element(app, ID.aiConfirm)
        let previewAppeared = preview.waitForExistence(timeout: 6)
        let alertAppeared = app.alerts.firstMatch.exists
        if !previewAppeared && !alertAppeared {
            XCTFail("""
                点「解析并预览」后必须给出结果（预览或明确错误），不能毫无反应。
                当前界面树：
                \(app.debugDescription)
                """)
        }
    }

    // MARK: - Flow 3b：AI 助手的输入焦点行为（点里面保持 / 点外面收起 / 「完成」收起）

    /// 回归两条用户反馈：「点输入框没反应」与「键盘无法关闭」。
    ///
    /// 焦点态的可观测代理：**导航栏的「完成」按钮只在输入框聚焦时出现**。
    /// 为什么不用 `app.keyboards`：模拟器（xcodebuild 驱动）不显示软件键盘，
    /// `app.keyboards` 恒为空，用它断言会永远失效或永远跳过。用「完成」按钮才可以真正断言。
    func testFlow3b_aiInputFocusBehavior() throws {
        let app = launchApp()

        app.tabBars.buttons["AI 助手"].tap()

        let input = element(app, ID.aiInput)
        XCTAssertTrue(input.waitForExistence(timeout: 10), "AI 助手应有输入区")
        let done = element(app, ID.aiDone)

        // ① 点输入框**本身** → 必须保持焦点
        //    （历史 bug：整页「点空白收键盘」手势会把刚点起来的键盘立刻收掉）
        input.tap()
        XCTAssertTrue(done.waitForExistence(timeout: 5),
                      "点输入框后应保持焦点，导航栏出现「完成」按钮")

        // ② 点输入框**之外**（分区标题）→ 应收起键盘
        app.staticTexts["用一句话描述"].firstMatch.tap()
        XCTAssertFalse(done.waitForExistence(timeout: 3),
                       "点输入框之外应能收起键盘（导航栏「完成」随之消失）")

        // ③ 再点输入框 → 应能重新聚焦（不能变成「点不开」）
        input.tap()
        XCTAssertTrue(done.waitForExistence(timeout: 5),
                      "收起后应能重新点开输入框")

        // ④ 点「完成」按钮 → 同样收起
        done.tap()
        XCTAssertFalse(done.waitForExistence(timeout: 3),
                       "点「完成」后应收起键盘")

        // ⑤ 键盘收起状态下点行内「解析并预览」→ 按钮必须真的被点到
        //    （历史 bug：onTapGesture 时代这个按钮的点击会被整页手势吞掉）
        app.staticTexts["用一句话描述"].firstMatch.tap()   // 确保先失焦
        element(app, ID.aiParse).tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5)
                      || element(app, ID.aiConfirm).exists,
                      "点「解析并预览」必须有反应（预览或明确错误）")
    }

    // MARK: - Flow 4：iPad 三栏与侧栏导航（iPhone 上跳过）

    func testFlow4_iPadSidebarNavigatesMiddleColumn() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad,
                          "仅在 iPad 上运行（iPhone 为单栏 TabBar，无侧栏）")

        // 强制横屏：横屏才是「三栏并排」，竖屏时 Sidebar 是**浮层**并且默认收起，
        // 展开后会盖住中栏（实测 cell.isHittable == false，点击落不到日期格上）。
        // 竖屏那一套交互请走 docs/DEVICE_TEST_CHECKLIST.md 第 11 节人工复测。
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = launchApp()

        // 侧栏切到「倒数日」→ 中栏应渲染倒数日页
        let countdownRow = element(app, ID.iPadSidebarCountdown)
        if !countdownRow.waitForExistence(timeout: 5) {
            // 兜底：若该尺寸下仍收起侧栏，先展开（真实用户也是这一步）
            let showSidebar = app.buttons["显示边栏"].firstMatch
            XCTAssertTrue(showSidebar.waitForExistence(timeout: 5),
                          "侧栏收起时应提供「显示边栏」按钮")
            showSidebar.tap()
        }
        XCTAssertTrue(countdownRow.waitForExistence(timeout: 10),
                      """
                      iPad 侧栏应有「倒数日」行（标识 \(ID.iPadSidebarCountdown)）。
                      当前界面树：
                      \(app.debugDescription)
                      """)
        countdownRow.tap()

        XCTAssertTrue(app.navigationBars["倒数日"].waitForExistence(timeout: 5),
                      "切到倒数日后，中栏应显示倒数日页")

        // 切回「日历」→ 月历网格应可再次操作（日期格带稳定标识）
        let calendarRow = element(app, ID.iPadSidebarCalendar)
        XCTAssertTrue(calendarRow.waitForExistence(timeout: 5), "iPad 侧栏应有「日历」行")
        calendarRow.tap()

        let target = midMonthTarget
        let cell = element(app, ID.monthDay(year: target.year, month: target.month, day: target.day))
        XCTAssertTrue(cell.waitForExistence(timeout: 10),
                      """
                      切回日历后应能看到日期格。
                      当前界面树：
                      \(app.debugDescription)
                      """)
        // 等它真的可点再点：切节有转场动画，过早点击会落空
        expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: cell, handler: nil)
        waitForExpectations(timeout: 5)

        cell.tap()
        XCTAssertTrue(cell.isSelected,
                      """
                      iPad 上点日期也应生效（该格应带上 .isSelected）。
                      可点击性：\(cell.isHittable)
                      当前界面树：
                      \(app.debugDescription)
                      """)

        // 说明：右栏（Inspector）该显示什么目前尚未裁决（见 docs/PROGRESS_ANALYSIS_2026-09-25.md §4-A），
        // 因此这里刻意不断言右栏内容，避免把未定方案固化进测试。
    }

    // MARK: - Flow 5：设置页 iCloud 同步区块必须给出明确状态

    func testFlow5_settingsShowsDefiniteICloudState() {
        let app = launchApp()

        app.tabBars.buttons["我的"].tap()

        // 同步状态行在「可用（有开关）」与「不可用（只有说明）」两个分支里都存在，
        // 恰好渲染其中之一，因此是跨账号状态都成立的可断言点。
        let status = element(app, ID.settingsSyncStatus)
        XCTAssertTrue(scrollUntilVisible(app, status),
                      "设置页应能找到 iCloud 同步状态行（模拟器无 iCloud 账号时应显示不可用/未启用）")

        // 有账号时还应有开关；无账号时不强求
        let toggle = element(app, ID.settingsSyncToggle)
        if toggle.exists {
            XCTAssertTrue(toggle.isEnabled, "有 iCloud 账号时同步开关应可用")
        }
    }
}
