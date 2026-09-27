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
    static let iPadSidebarAI = "ipad.sidebar.ai"
    static let iPadSidebarAgenda = "ipad.sidebar.agenda"
    static let iPadSidebarCountdown = "ipad.sidebar.countdown"
    static let iPadInspectorCountdown = "ipad.inspector.countdown"
    static let monthMenu = "calendar.month.menu"
    static let stateEmpty = "state.empty"
    static let stateError = "state.error"
    static let stateToast = "state.toast"

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
        // §7.1 数据隔离：空库启动，「空态 / 首次使用 / 无数据」类断言与真实容器无关
        app.launchArguments += ["-uitest-empty-store"]
        app.launch()
        dismissSystemPermissionPromptIfNeeded()
        return app
    }

    /// 关掉可能挡住首屏的系统权限弹窗（当前只有定位会弹）。
    ///
    /// 为什么必须显式处理：这个弹窗属于 **SpringBoard**，不在 App 的元素树里，
    /// 所以 `app.buttons["不允许"]` 找不到它；而它一旦挂上，App 内的点击全部落空。
    /// 在**全新模拟器**上第一次跑必然遇到——本项目此前的 UI 测试只在已经授权过的
    /// 机器上跑过，所以一直没暴露这个问题（用新建的 iPhone SE 验收时踩到）。
    private func dismissSystemPermissionPromptIfNeeded() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        // 先判「有没有弹窗」再找按钮：没有就直接返回，
        // 否则每个用例都会为了 3 个标题各白等 3 秒（10 条用例就是一分半）。
        guard springboard.alerts.firstMatch.waitForExistence(timeout: 2) else { return }
        for title in ["不允许", "允许一次", "好"] {
            let button = springboard.buttons[title].firstMatch
            if button.exists {
                button.tap()
                return
            }
        }
    }

    /// 按标识查找元素，不关心它映射成哪一类（textField / textView / other / button…）
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// 按文案查找（只用于没有稳定标识的场景：系统菜单项、纯文案按钮）。
    /// 注意：依赖 App 的本地化文案，所以只在强制简体中文的前提下才可靠。
    private func label(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", text))
            .firstMatch
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

    /// 当月最后一天 —— 网格**最后一行**的探针。
    ///
    /// 与 `midMonthTarget` 的取舍正好相反：这里**故意**用月末，因为它最能代表
    /// 「整月是否一屏可见」（P0-1 的验收）。它的风险是跟手滑动时相邻月的网格会
    /// 一起渲染、同一天出现两次；但 Flow 10 全程不滑动，稳态下只有当前月的网格。
    private var monthEndTarget: (year: Int, month: Int, day: Int) {
        let cal = Calendar(identifier: .gregorian)
        let c = cal.dateComponents([.year, .month], from: Date())
        let year = c.year ?? 2026, month = c.month ?? 1
        var dc = DateComponents(); dc.year = year; dc.month = month
        let firstOfMonth = cal.date(from: dc) ?? Date()
        let days = cal.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 28
        return (year, month, days)
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

    func testFlow3_aiAssistantReactsToInput() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone,
                          "仅在 iPhone 上运行（iPad 为侧栏布局，无 TabBar；AI 助手在 iPad 的入口路径不同）")
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

        // 期望：要么出现预览（含确认创建），要么给出明确的错误提示；绝不能毫无反应。
        // 错误自 P0-3 起改为行内 QingheToast（不再弹模态），三种形态都要认——
        // 否则「错误表现得更轻」会被误判成「毫无反应」。
        let preview = element(app, ID.aiConfirm)
        let previewAppeared = preview.waitForExistence(timeout: 6)
        let toastAppeared = element(app, ID.stateToast).exists
        let alertAppeared = app.alerts.firstMatch.exists
        if !previewAppeared && !toastAppeared && !alertAppeared {
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
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone,
                          "仅在 iPhone 上运行（iPad 为侧栏布局，无 TabBar；AI 助手在 iPad 的入口路径不同）")
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
        // 「必须有反应」的三种合法形态：预览卡 / 行内错误 / 旧式模态 alert。
        // 解析失败自 P0-3 起改为行内 QingheToast（不再弹模态），这里必须一起认，
        // 否则这条断言会因为「错误表现得更轻」而误报失败。
        let reacted = element(app, ID.aiConfirm).waitForExistence(timeout: 5)
            || element(app, ID.stateToast).waitForExistence(timeout: 5)
        XCTAssertTrue(reacted || app.alerts.firstMatch.exists,
                      "点「解析并预览」必须有反应（预览或明确错误）")
    }

    // MARK: - Flow 6：全部日程的搜索可用 + 空态是统一组件且带行动按钮

    /// 两个目的：
    /// 1. 回归「全部日程搜不了」——iOS 26 上 `.searchable` 曾不渲染任何搜索入口，
    ///    搜索框不出现就直接失败；
    /// 2. 报告 §41 要求空态含四要素（图标 + 标题 + 说明 + 行动按钮），且各页共用同一组件。
    ///
    /// 空态用「搜索一个必然无结果的词」造：与容器里有什么数据无关，任何环境都成立。
    /// （此前用「筛选到没有数据的类型」造，容器里提醒/记事都有内容时只能跳过——已弃用。）
    func testFlow6_searchWorksAndEmptyStateIsActionable() {
        let app = launchApp()

        // 进「全部日程」：先点工具栏入口菜单，再点菜单项。
        // ⚠️ 菜单项必须用 `app.buttons[...]` 精确定位：用「任意类型按文案查找」会先匹配到
        // 导航栏标题「全部日程」，点了等于没点（单跑偶发通过、全量跑被跳过，就是这么来的）。
        let menu = element(app, ID.monthMenu)
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "日历页应有工具栏入口菜单")
        menu.tap()

        let agendaItem = app.buttons["全部日程"].firstMatch
        XCTAssertTrue(agendaItem.waitForExistence(timeout: 5), "入口菜单里应有「全部日程」")
        agendaItem.tap()

        XCTAssertTrue(app.navigationBars["全部日程"].waitForExistence(timeout: 10),
                      """
                      应进入全部日程页。
                      当前界面树：
                      \(app.debugDescription)
                      """)

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5),
                      """
                      全部日程的搜索框必须可见（「搜不了」的回归保护）。
                      当前界面树：
                      \(app.debugDescription)
                      """)
        search.tap()
        search.typeText("zzzzzz")

        let empty = element(app, ID.stateEmpty)
        XCTAssertTrue(empty.waitForExistence(timeout: 5),
                      """
                      搜不到结果时应出现统一空态（标识 \(ID.stateEmpty)）。
                      当前界面树：
                      \(app.debugDescription)
                      """)

        let clear = label(app, "清除筛选")
        XCTAssertTrue(clear.waitForExistence(timeout: 3),
                      "空态应带「清除筛选」行动按钮（四要素的第四项）")
        clear.tap()
        XCTAssertFalse(empty.waitForExistence(timeout: 3),
                       "点「清除筛选」后空态应消失（搜索条件真的被清掉）")
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

        // §33/§36 裁决（2026-09-26）：右栏是上下文 Inspector——
        // 倒数日节下右栏应切换为倒数日详情列（未选中时为空态提示），
        // 不再是全节常驻的日详情
        let inspector = element(app, ID.iPadInspectorCountdown)
        XCTAssertTrue(inspector.waitForExistence(timeout: 5),
                      "倒数日节下右栏应显示倒数日 Inspector（标识 \(ID.iPadInspectorCountdown)）")

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

        // 右栏语义已于 2026-09-26 裁决为上下文 Inspector（§33/§36），
        // 倒数日节的右栏断言见上方 iPadInspectorCountdown；日历节的右栏
        // 随选中日期联动，已在选中日期格处隐式覆盖。
    }

    // MARK: - Flow 5：设置页 iCloud 同步区块必须给出明确状态

    func testFlow5_settingsShowsDefiniteICloudState() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone,
                          "仅在 iPhone 上运行（iPad 为侧栏布局，无 TabBar；设置在 iPad 走月历菜单的 sheet 入口）")
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

    // MARK: - Flow 7：空态四要素 + 行动按钮真的可用（依赖 §7.1 数据隔离的干净空库）

    /// 此前「空态」断言只能靠搜索造（Flow 6），因为 UI 测试跑在真实容器上、
    /// 有没有数据不受控。`-uitest-empty-store` 落地后，倒数日 Tab 天然就是空库——
    /// 这是第一条**不依赖任何构造手段**的空态用例，同时验证行动按钮（第四要素）点开编辑器。
    func testFlow7_countdownEmptyStateIsActionable() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone,
                          "仅在 iPhone 上运行（iPad 走侧栏入口，Flow 4 已覆盖该节）")
        let app = launchApp()

        // iPhone 没有「倒数日」Tab（底部四项是 日历/黄历/AI 助手/我的）——
        // 与 Flow 6 同路：月历工具栏入口菜单 → 「倒数日」
        let menu = element(app, ID.monthMenu)
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "日历页应有工具栏入口菜单")
        menu.tap()
        let countdownItem = app.buttons["倒数日"].firstMatch
        XCTAssertTrue(countdownItem.waitForExistence(timeout: 5), "入口菜单里应有「倒数日」")
        countdownItem.tap()

        // 统一空态组件（标识 state.empty）：图标 + 标题 + 说明（前三要素由组件自身保证结构）
        let empty = element(app, ID.stateEmpty)
        XCTAssertTrue(empty.waitForExistence(timeout: 10),
                      """
                      干净空库下倒数日 Tab 应显示统一空态（标识 \(ID.stateEmpty)）。
                      若出现却失败，多半是数据隔离参数没生效。
                      当前界面树：
                      \(app.debugDescription)
                      """)

        // 第四要素：行动按钮存在且真的能点开新建编辑器
        let action = label(app, "新建倒数日")
        XCTAssertTrue(action.waitForExistence(timeout: 5), "空态应带「新建倒数日」行动按钮")
        action.tap()

        let cancel = app.buttons["取消"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5),
                      "点行动按钮应打开倒数日编辑器（出现「取消」）")
    }

    // MARK: - Flow 8：工具栏入口收敛（UI_DESIGN_REVIEW P0-2）

    /// 同一功能只留一条主路径（Phase 1 的验收项之一）：
    /// - 「回到今天」只留工具栏按钮，菜单里不再重复；
    /// - iPhone 的「设置」由底部「我的」Tab 承担，菜单里不再重复；
    /// - 同时锁住「全部日程 / 倒数日」**仍在**菜单里——它们是 iPhone 上唯一的入口
    ///   （Flow 6 / Flow 7 都从这里进），误删等于让功能消失。
    func testFlow8_monthMenuHasSingleEntryPerFeature() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone,
                          "菜单按 isIPadSplit 分流；iPad 的权威入口是侧栏，由 Flow 4 覆盖")
        let app = launchApp()

        let menu = element(app, ID.monthMenu)
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "日历页应有工具栏入口菜单")
        menu.tap()

        for title in ["跳转到日期", "全部日程", "倒数日"] {
            XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 5),
                          "入口菜单应保留「\(title)」（iPhone 上它是唯一入口）")
        }
        XCTAssertFalse(app.buttons["回到今天"].exists,
                       "「回到今天」不应在菜单里重复——工具栏「今天」按钮已是唯一入口")
        XCTAssertFalse(app.buttons["设置"].exists,
                       "「设置」不应在菜单里重复——底部「我的」Tab 已承担")
    }

    // MARK: - Flow 9：iPad 侧栏的两处结构变更（批次 3）

    /// 两件事：
    /// 1. 侧栏新增「AI 助手」节（P0-3，原先只能从设置页头部卡进、入口埋两层深），
    ///    同时年视图节已移出（P0-1 裁决走方案 C）；
    /// 2. **实测** `.doubleColumn` 在「无 Inspector 节」下的真实语义。
    ///    `LunisolarCalendarApp.swift` 的注释一直声称它「隐藏右栏」，而按 Apple 的定义它是
    ///    「显示内容列 + 详情列、隐藏侧栏」——两者不可能都对。这条断言把事实钉住：
    ///    切到「全部日程」后**侧栏必须仍然可见可用**。若这里红，就是取值选错了。
    func testFlow9_iPadSidebarStructureChange() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad,
                          "仅在 iPad 上运行（iPhone 无侧栏）")
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = launchApp()

        // ① 侧栏应有「AI 助手」节（该尺寸下若仍收起，先展开——真实用户也是这一步）
        let aiRow = element(app, ID.iPadSidebarAI)
        if !aiRow.waitForExistence(timeout: 5) {
            let showSidebar = app.buttons["显示边栏"].firstMatch
            if showSidebar.waitForExistence(timeout: 5) { showSidebar.tap() }
        }
        XCTAssertTrue(aiRow.waitForExistence(timeout: 10),
                      """
                      iPad 侧栏应有「AI 助手」行（标识 \(ID.iPadSidebarAI)）。
                      当前界面树：
                      \(app.debugDescription)
                      """)
        XCTAssertFalse(app.staticTexts["年视图"].exists,
                       "「年视图」已移出侧栏（方案 C），侧栏不应再有这一行")

        // ② 切到「全部日程」→ 侧栏不应消失（见本用例头部说明）
        element(app, ID.iPadSidebarAgenda).tap()
        XCTAssertTrue(app.navigationBars["全部日程"].waitForExistence(timeout: 10),
                      "切到「全部日程」后中栏应显示该页")
        let calendarRow = element(app, ID.iPadSidebarCalendar)
        XCTAssertTrue(calendarRow.waitForExistence(timeout: 5),
                      """
                      切到「全部日程」后侧栏**不应消失**。这里若红，说明 `.doubleColumn`
                      在无 Inspector 节下把侧栏也收掉了（见 LunisolarCalendarApp.swift 的注释）。
                      当前界面树：
                      \(app.debugDescription)
                      """)

        // ③ 侧栏行仍可点：切回日历
        calendarRow.tap()
        XCTAssertTrue(app.navigationBars["日历"].waitForExistence(timeout: 10),
                      "切回「日历」应生效（说明侧栏仍可交互）")
    }

    // MARK: - Flow 10：月历首屏必须完整容纳整月（UI_DESIGN_REVIEW P0-1 的验收）

    /// 把「打开即见整月，无需滚动」做成可执行断言：**不滚动**，直接查当月最后一天
    /// （网格最后一行）是否已经可点。页面需要滚动才能看到时，该格要么还没被
    /// `LazyVGrid` 创建（`exists == false`）、要么不在可点区域（`isHittable == false`），
    /// 两种都判失败。这比截图更严格，也能当长期回归护栏。
    ///
    /// 在 iPhone SE（375×667）上跑最能说明问题——那是验收文档点名的机型。
    ///
    /// 只在 iPhone 上跑：验收文档点名的就是 iPhone SE / Pro Max；
    /// 而且末条断言要拿底部 TabBar 当参照，iPad 是侧栏布局、根本没有 TabBar。
    func testFlow10_monthGridFitsOnFirstScreen() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone,
                          "仅在 iPhone 上运行（iPad 无底部 TabBar，且验收针对的是 iPhone SE / Pro Max）")
        let app = launchApp()
        let t = monthEndTarget
        let id = ID.monthDay(year: t.year, month: t.month, day: t.day)
        let last = element(app, id)

        XCTAssertTrue(last.waitForExistence(timeout: 10),
                      """
                      当月最后一天（\(t.year)-\(t.month)-\(t.day)）的日期格在首屏就该存在
                      （标识 \(id)）。不存在通常意味着它在首屏之外，LazyVGrid 还没创建它。
                      当前界面树：
                      \(app.debugDescription)
                      """)
        XCTAssertTrue(last.isHittable,
                      """
                      当月最后一天应**无需滚动**即可见可点（P0-1 的验收「打开即见整月」）。
                      isHittable == false 表示它落在首屏之外，或被底部 TabBar 遮挡。
                      当前界面树：
                      \(app.debugDescription)
                      """)

        // 再加一条量化的：网格最后一行必须整体位于底部 TabBar 之上。
        // `isHittable` 只看元素中心点——被 TabBar 压住一点点也仍算「可点」；
        // 这条把「完全没被压住」也钉住，两条合起来才是「打开即见整月」。
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.exists, "应有底部 TabBar")
        XCTAssertLessThanOrEqual(last.frame.maxY, tabBar.frame.minY,
                                 """
                                 网格最后一行不应被底部 TabBar 压住：
                                 日期格底边 y=\(last.frame.maxY)，TabBar 顶边 y=\(tabBar.frame.minY)。
                                 """)
    }
}
