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
    static let dayDetailNewEvent = "calendar.day.detail.new"
    static let editTitle = "event.edit.title"
    static let editSave = "event.edit.save"
    static let aiInput = "ai.input.draft"
    static let aiParse = "ai.input.parse"
    static let aiConfirm = "ai.preview.confirm"
    static let aiDone = "ai.input.done"
    static let aiGoToCreatedDay = "ai.created.goto"
    static let settingsSyncToggle = "settings.sync.toggle"
    static let settingsSyncStatus = "settings.sync.status"
    static let iPadSidebarCalendar = "ipad.sidebar.calendar"
    static let iPadSidebarAI = "ipad.sidebar.ai"
    static let iPadSidebarAgenda = "ipad.sidebar.agenda"
    static let iPadSidebarCountdown = "ipad.sidebar.countdown"
    static let iPadSidebarSettings = "ipad.sidebar.settings"
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
        // 固定语言/地区：否则英文模拟器下界面走 en.lproj，文案断言全部失配。
        // shots.sh --tour --lang 用 SHOTS_LANG 覆盖（截图巡游按指定语言出图）；
        // 普通 Flow 用例不传该变量，固定 zh-Hans 保证断言稳定。
        switch ProcessInfo.processInfo.environment["SHOTS_LANG"] ?? "zh-Hans" {
        case "en":      app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        case "ja":      app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        case "zh-Hant": app.launchArguments += ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_Hant_TW"]
        default:        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_Hans_CN"]
        }
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

    /// 「今天、且还没到」的时刻文案（形如 `19点54分`），用于需要落在**今天**的用例。
    ///
    /// 为什么要算而不是写死：`AICommandValidator.validateCreate` 会拦下
    /// 「一次性（不重复）日程落在过去」——这是**正确**的产品行为，但它让写死时刻的
    /// 用例变成「几点跑决定红绿」：写「下午3点」时，15:00 之后跑必然拿不到预览。
    /// 2026-10-02 18:54 的全量跑就是这样红的。
    ///
    /// 距零点不足 5 分钟时返回 nil（调用方 `XCTSkip`）：那个窗口里构造不出
    /// 「今天且还没到」的时刻，与其假红不如明说跳过。
    private func laterTodayText() -> String? {
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        guard let tomorrowStart = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)),
              tomorrowStart.timeIntervalSince(now) > 300 else { return nil }
        // 现在 + 1 小时；若跨天则收敛到 23:59（仍是今天，且必然在未来）
        let target = min(now.addingTimeInterval(3600), tomorrowStart.addingTimeInterval(-60))
        let c = cal.dateComponents([.hour, .minute], from: target)
        return "\(c.hour ?? 0)点\(c.minute ?? 0)分"
    }

    /// 事件行的标题断言（「当日安排」里能不能看到某条日程）。
    ///
    /// ⚠️ 不能写成 `app.staticTexts[title]`：`EventRow` 用了
    /// `.accessibilityElement(children: .combine)`，整行被合成**一个**元素，
    /// 其 label 是「标题 + 时间段」（见 `EventRow.swift` 的 accessibilityLabel）——
    /// 按标题做**精确**匹配永远找不到事件行，行为完全正确也会红。
    /// 这里用前缀匹配：将来若把 combine 去掉、标题还原成独立 Text，它同样成立。
    private func eventRow(_ app: XCUIApplication, title: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", title))
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
        XCTAssertTrue(eventRow(app, title: title).waitForExistence(timeout: 10),
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

    // MARK: - Flow 3c：AI 创建的日程必须**立刻**出现在日历的「今日安排」里
    //
    // 真机回归（2026-09-30 用户报告）：
    //   「AI 日历助手创建的日程不会立刻出现在今日安排里面，必须手动再创建一条新的日程
    //     才会和新创建的日程一同显示」
    //
    // 为什么此前没被发现：Flow 2 断言了「手动创建 → 日历出现」，
    // 而 Flow 3 只断言 AI「有反应」（预览/错误二选一），**没人断言 AI 创建的事件真的落到日历上**。
    // 这条用例补的就是那个缺口——它是这个 bug 的回归锚点。
    //
    // 数据层已单独验证过是正确的（AI 写入与手动写入在 store 上留下的状态完全一致：
    // count+1、revision+1、events(on: today) 立刻 +1）。所以本用例失败时，
    // 问题一定在**视图重新求值/观察**，不要去改数据层。
    //
    // ── 2026-09-30 真机诊断的最终结论（重要，别再往刷新方向查）──────────────
    // 实测（临时埋点已被移除）：写入 → 观察通知 → `month.body` → `card.body`，
    // SwiftUI 自证 `SelectedDayCardView: \EventStore.revision changed.`，
    // 新事件 id 确实出现在它所属那天的当日数组里。**刷新链路完全正常。**
    //
    // 用户报告的「不立刻出现」真因是：说「明天上午10点…」时日程**正确地建到了明天**，
    // 而用户人还在今天的日历页 —— 今天列表当然不变，直到切日期才看见。
    // 也就是说：不是刷新 bug，而是**反馈没说明加到了哪一天、也没有去路**。
    // 对应修复在 `AIAssistantView.create()`；回归锚点是下面的 Flow 3d。

    func testFlow3c_aiCreatedEventAppearsInTodayScheduleImmediately() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone,
                          "仅在 iPhone 上运行（iPad 为侧栏布局，AI 入口路径不同）")
        let app = launchApp()

        // 唯一标题，避免模拟器容器里的历史数据混淆断言
        let title = "AI日程-\(Int(Date().timeIntervalSince1970))"

        app.tabBars.buttons["AI 助手"].tap()

        let input = element(app, ID.aiInput)
        XCTAssertTrue(input.waitForExistence(timeout: 10), "AI 助手应有输入区")
        input.tap()
        // 显式带上标题与「今天」，让解析结果落在今天。
        // ⚠️ 时刻**不能写死**（原来写「下午3点」）：`AICommandValidator` 会正确拦下
        // 「一次性日程落在过去」，于是预览不出现、这条断言假红——2026-10-02 18:54 的
        // 全量跑正是这样红的（探针复现：parser OK，validator `inThePast`
        // 「「2026年10月2日 15:00」已经过去了」）。取「现在 + 1 小时」。
        guard let timeText = laterTodayText() else {
            throw XCTSkip("距零点不足 5 分钟：构造不出「今天、且还没到」的时刻，而本用例必须落在今天")
        }
        input.typeText("今天\(timeText)提醒我\(title)")

        let parseButton = element(app, ID.aiParse)
        XCTAssertTrue(parseButton.waitForExistence(timeout: 5), "应有「解析并预览」按钮")
        parseButton.tap()

        let confirm = element(app, ID.aiConfirm)
        XCTAssertTrue(confirm.waitForExistence(timeout: 6),
                      "应出现「确认创建」预览（若这里是解析失败，说明输入未被识别）")
        confirm.tap()

        // 回到日历 Tab —— 这一步就是用户报告里「不立刻出现」的地方
        app.tabBars.buttons["日历"].tap()

        XCTAssertTrue(eventRow(app, title: title).waitForExistence(timeout: 10),
                      """
                      AI 创建后切回日历，「今日安排」里必须立刻出现「\(title)」。
                      若失败：数据层已证明写入正确，问题在视图未重新求值（观察失效），
                      而不是事件没存进去。当前界面树：
                      \(app.debugDescription)
                      """)
    }

    // MARK: - Flow 3d：日程建在**非今天**时，必须说清是哪天并给去路
    //
    // 真机反馈（2026-09-30）的**真因**，不是刷新问题：
    //   用户说「明天上午10点提醒我开会」→ AI 正确建到**明天** → 用户人在**今天**的日历页，
    //   今天列表当然不变 → 看起来"没反应"，直到切日期/再操作一次才看见。
    //   实测（埋点已移除）证明刷新链路正常：写入 → 观察通知 → month.body → card.body，
    //   且 SwiftUI 自证 `\EventStore.revision changed.`。
    //
    // 修复：`AIAssistantView.create()` 在落点非今天时，提示改为「已加入 <日期> 的日程」
    //   并给出「去看看」按钮（复用 `NavigationCoordinator.openEventDate`）。
    // 本用例锁定三点——否则将来有人把文案改回笼统的"已加入日历"，这个坑会原样复活：
    //   ① 提示说出了具体日期 ② 给了「去看看」去路 ③ 点它真能跳到那天并看到该事件。

    func testFlow3d_eventOnAnotherDayAnnouncesDateAndOffersJump() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone,
                          "仅在 iPhone 上运行（iPad 为侧栏布局，AI 入口路径不同）")
        let app = launchApp()

        // ⚠️ 标题里绝不能出现日期词：解析器会把标题中**所有**已识别的日期词全局删掉
        // （`AICommandParser` 第 3 步对 `consumedDate` 做 replacingOccurrences，
        //  而 normalize 会把「明日」归一成「明天」）。实测「明日日程-<ts>」的落库标题是
        // 「日程-<ts>」——断言会去找一个永远不存在的字符串。
        // 这里用不含日期词的标题；其原样落库已由探针验证。
        let title = "AI跨日日程-\(Int(Date().timeIntervalSince1970))"
        app.tabBars.buttons["AI 助手"].tap()

        let input = element(app, ID.aiInput)
        XCTAssertTrue(input.waitForExistence(timeout: 10), "AI 助手应有输入区")
        input.tap()
        // 刻意用「明天」：这条用例的全部意义就是落点**不是今天**
        input.typeText("明天上午10点提醒我\(title)")

        let parseButton = element(app, ID.aiParse)
        XCTAssertTrue(parseButton.waitForExistence(timeout: 5), "应有「解析并预览」按钮")
        parseButton.tap()

        let confirm = element(app, ID.aiConfirm)
        XCTAssertTrue(confirm.waitForExistence(timeout: 6),
                      "应出现「确认创建」预览（解析失败说明「明天上午10点」没被识别）")
        confirm.tap()

        // 顺序刻意为「先抓可点的那个，再断言文案」：
        // 成功提示是 2 秒后自动消失的行内 Toast（AIAssistantView.showSuccess），
        // 文案与「去看看」按钮同生同灭。若先对着文案做一次 waitForExistence，
        // 查询开销就可能把那 2 秒窗口耗掉，后面找按钮变成随机红。
        // 反过来用按钮当闸门是安全的：按钮在 ⇔ 文案在（同一 Section，同一状态位）。

        // 断言 2：必须给去路
        let goThere = element(app, ID.aiGoToCreatedDay)
        XCTAssertTrue(goThere.waitForExistence(timeout: 6),
                      """
                      非今天的日程应提供「去看看」跳转按钮。当前界面树：
                      \(app.debugDescription)
                      """)

        // 断言 1：提示必须点出具体日期，而不是笼统的"已加入日历"
        // 用 `.matching(predicate)`（按元素自身的 label 过滤），不要用 `.containing(...)`
        // ——后者是「含有匹配**后代**」的语义，纯 Text 没有后代，会永远找不到。
        let announced = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "的日程"))
            .firstMatch
        XCTAssertTrue(announced.exists,
                      """
                      日程建在非今天时，提示必须说明加到了哪一天（形如「已加入 <日期> 的日程」）。
                      笼统的「日程已加入日历。」会让用户以为操作没生效。
                      """)

        // 断言 3：点「去看看」必须真能跳到那天并看到刚建的事件
        goThere.tap()
        XCTAssertTrue(eventRow(app, title: title).waitForExistence(timeout: 10),
                      """
                      点「去看看」后应跳到该日程所在那一天，并在「今日安排」里看到「\(title)」。
                      若失败：检查 NavigationCoordinator.openEventDate 是否被正确调用。
                      """)
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
        // 「搜索条件真的被清掉」的可观测证据是**行动按钮消失**，不能断言空态消失：
        // 本用例跑在 `-uitest-empty-store` 的空库上，清掉条件后列表依然为空、
        // 空态依然在（`AllEventsView` 用的还是同一个 `state.empty` 元素，
        // 只是 `actionTitle` 从「清除筛选」变成 nil）——
        // 原来这里写 `XCTAssertFalse(empty.waitForExistence(...))`，必定红。
        XCTAssertFalse(label(app, "清除筛选").waitForExistence(timeout: 3),
                       "点「清除筛选」后行动按钮应消失（说明筛选条件真的被清掉）")
        // 注意：空库下「搜索真的筛掉了内容」这一半天然是空的（列表本来就空）。
        // 要让它非空洞，得先造一条数据再搜——留给 P3 的搜索用例，见执行计划 §七。
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

    // MARK: - Flow 13/14：无障碍按钮审计（P3-6）

    /// 已知**未修**的无标签控件：按「子元素的 accessibilityIdentifier」精确匹配。
    ///
    /// 为什么用子元素标识而不是 frame/文案：frame 会随字号与机型变，文案随语言变；
    /// 而 SF Symbol 名（`slider.horizontal.3` 等）稳定且唯一。
    ///
    /// **当前为空**：2026-10-03 审计抓到的两处真缺陷都已修好——
    /// 1. 设置页「导入 / 恢复数据」：嵌套 `Menu` → `Button + confirmationDialog`（标准控件自带标签与 44pt 命中区）；
    /// 2. 日历工具栏图标菜单：光秃秃的 `Image(systemName:)` → `Label(文字, systemImage:)`
    ///    （**不需要任何 accessibility 修饰符**；给那个 Menu 挂修饰符会让 SwiftUI 崩溃，
    ///     见 docs/EXECUTION_PLAN_2026-09-30.md 的 P3-6 小节）。
    ///
    /// 新增已知未修项时：键填「其子元素的 accessibilityIdentifier」，值写清原因与出处；
    /// 修好后删掉条目——「已知项恰好各命中一次」那条断言会提醒你，白名单不会烂在原地。
    private static let knownUnlabeledControls: [String: String] = [:]

    /// 审计当前屏幕的全部按钮：把「无标签 / 标签是 SF Symbol 名」记进 offenders。
    /// 抽成 helper 是为了 Flow 13（主屏）与 Flow 14（深层界面）用同一判据。
    private func auditVisibleButtons(in app: XCUIApplication, screen: String,
                                     offenders: inout [String]) -> (audited: Int, known: Int) {
        // 标签等于 SF Symbol 名，等于没有替代文本（朗读出来是英文符号名）
        let knownSymbolNames = ["plus", "minus", "gearshape", "chevron.left", "chevron.right",
                                "chevron.up", "chevron.down", "ellipsis", "xmark", "checkmark",
                                "square.and.arrow.up", "arrow.clockwise", "trash", "line.3.horizontal"]
        var audited = 0
        var known = 0
        for button in app.buttons.allElementsBoundByIndex where button.exists {
            audited += 1
            let labelText = button.label
            if labelText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let childIDs = Set(button.descendants(matching: .any).allElementsBoundByIndex
                    .map(\.identifier).filter { !$0.isEmpty })
                if childIDs.contains(where: { Self.knownUnlabeledControls[$0] != nil }) {
                    known += 1
                    continue
                }
                // 诊断：肇事元素不能靠 frame 猜（第一版就猜错过），把它的描述一起报出来
                let dump = button.debugDescription
                    .split(separator: "\n").prefix(6).joined(separator: " | ")
                offenders.append("[\(screen)] 按钮无标签: frame=\(button.frame) 详情: \(dump)")
            } else if knownSymbolNames.contains(labelText) {
                offenders.append("[\(screen)] 按钮标签是 SF Symbol 名「\(labelText)」: frame=\(button.frame)")
            }
        }
        return (audited, known)
    }

    /// iPad 侧栏项：**首启后侧栏要等一会儿才进无障碍树**（实测约 10s；Flow 9 也是等出来的），
    /// 直接 tap 会以「No matches found」失败。所以统一「先等存在、再点」。
    private func tapSidebarItem(_ app: XCUIApplication, _ identifier: String,
                                timeout: TimeInterval = 15) {
        let item = element(app, identifier)
        if !item.waitForExistence(timeout: 5) {
            // 竖屏/窄窗下侧栏是 overlay、处于收起状态：先展开（真实用户也是这一步）。
            // 抄 Flow 9 的成熟做法——系统按钮就叫「显示边栏」。
            let showSidebar = app.buttons["显示边栏"].firstMatch
            if showSidebar.waitForExistence(timeout: 5) { showSidebar.tap() }
        }
        XCTAssertTrue(item.waitForExistence(timeout: timeout), "iPad 侧栏应有 \(identifier)")
        item.tap()
    }

    /// 主屏清单：iPhone 走底部 Tab（4 个），iPad 走侧栏（5 节）。
    /// 两者**互斥**——iPhone 没有侧栏、iPad 没有底部 Tab，不能共用一套入口。
    private func mainScreens(_ app: XCUIApplication) -> [(String, () -> Void)] {
        if UIDevice.current.userInterfaceIdiom == .pad {
            // 返回的是闭包数组（escaping），所以必须写 `self.`——Swift 要求显式捕获语义
            return [
                ("iPad·日历节", { self.tapSidebarItem(app, ID.iPadSidebarCalendar) }),
                ("iPad·AI 助手节", { self.tapSidebarItem(app, ID.iPadSidebarAI) }),
                ("iPad·全部日程节", { self.tapSidebarItem(app, ID.iPadSidebarAgenda) }),
                ("iPad·倒数日节", { self.tapSidebarItem(app, ID.iPadSidebarCountdown) }),
                ("iPad·设置节", { self.tapSidebarItem(app, ID.iPadSidebarSettings) }),
            ]
        }
        return ["日历", "黄历", "AI 助手", "我的"].map { title in
            (title, { app.tabBars.buttons[title].tap() })
        }
    }

    func testFlow13_allVisibleButtonsHaveReadableLabels() throws {
        // iPad 竖屏下侧栏是收起的（Flow 11 清单：「竖屏侧栏应收起」），先转横屏再遍历
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        if isPad { XCUIDevice.shared.orientation = .landscapeLeft }
        defer { if isPad { XCUIDevice.shared.orientation = .portrait } }

        let app = launchApp()
        var offenders: [String] = []
        var audited = 0
        var knownSkipped = 0

        for (screen, open) in mainScreens(app) {
            open()
            _ = app.buttons.firstMatch.waitForExistence(timeout: 5)
            let result = auditVisibleButtons(in: app, screen: screen, offenders: &offenders)
            audited += result.audited
            knownSkipped += result.known
        }

        // 诊断（只在失败时输出）：日历屏全部按钮，便于下次一眼看出肇事元素
        if isPad {
            tapSidebarItem(app, ID.iPadSidebarCalendar)
        } else {
            app.tabBars.buttons["日历"].tap()
        }
        var calendarDump: [String] = []
        for button in app.buttons.allElementsBoundByIndex where button.exists {
            calendarDump.append("label='\(button.label)' id='\(button.identifier)' frame=\(button.frame)")
        }

        XCTAssertGreaterThan(audited, 20, "审计到的按钮太少（\(audited)），可能没真的走完各屏")
        XCTAssertEqual(knownSkipped, Self.knownUnlabeledControls.count,
                       "已知未修项应恰好各命中一次（当前 \(knownSkipped)/\(Self.knownUnlabeledControls.count)）——"
                       + "若某条被修好，请从 knownUnlabeledControls 里删掉它，否则这条会提醒你")
        let report = "日历屏全部按钮：\n" + calendarDump.joined(separator: "\n")
            + "\n---\n以下按钮缺少可读标签（VoiceOver 只会读出「按钮」或英文符号名）：\n"
            + offenders.joined(separator: "\n")
        XCTAssertTrue(offenders.isEmpty, report)

        // 结构从「嵌套 Menu」换成「Button + confirmationDialog」，必须证明点击行为没坏：
        // 这一行现在应当**按名字就能找到**（无标签的 Menu 时代找不到），点开应给出两个格式选项。
        //
        // 放在最后且不关掉对话框：`confirmationDialog` 的系统「取消」不在 app 的元素树里
        // （实测 `app.buttons["取消"]` 无匹配——它是系统面板的部件），关不掉就干脆不动它；
        // 每条用例都会重启 app，留着打开状态没有副作用。
        if isPad {
            tapSidebarItem(app, ID.iPadSidebarSettings)
        } else {
            app.tabBars.buttons["我的"].tap()
        }
        let importRow = app.buttons["导入 / 恢复数据"]
        XCTAssertTrue(importRow.waitForExistence(timeout: 5),
                      "设置页应有名为「导入 / 恢复数据」的按钮（无标签的 Menu 时代是按名字找不到的）")
        XCTAssertGreaterThanOrEqual(importRow.frame.height, 44,
                                    "该行命中高度应 ≥44pt（HIG）；Menu 时代实测只有 20.3pt")
        importRow.tap()
        XCTAssertTrue(app.buttons["从 .ics 日历文件导入"].waitForExistence(timeout: 5),
                      "点该行应弹出格式选择——防误触语义（先选格式再导入）不能丢")
        XCTAssertTrue(app.buttons["从 .json 备份恢复"].exists, "两个格式选项都应可选")
    }

    // MARK: - Flow 14：深层界面的按钮审计（P3-6）

    /// 主屏之外的三处深层界面：全部日程 / 倒数日 / 年视图。
    ///
    /// 每处**新起一次 app**：跨界面返回逻辑本身也随形态（Tab↔侧栏）不同，
    /// 一次启动约 3 秒，比写三条返回路径可靠得多。
    func testFlow14_deepScreensButtonsHaveReadableLabels() throws {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        if isPad { XCUIDevice.shared.orientation = .landscapeLeft }
        defer { if isPad { XCUIDevice.shared.orientation = .portrait } }

        var offenders: [String] = []
        var audited = 0
        var knownSkipped = 0

        func audit(_ screen: String, open: (XCUIApplication) -> Void) {
            let app = launchApp()
            open(app)
            _ = app.buttons.firstMatch.waitForExistence(timeout: 5)
            let result = auditVisibleButtons(in: app, screen: screen, offenders: &offenders)
            audited += result.audited
            knownSkipped += result.known
            app.terminate()
        }

        audit("全部日程") { app in
            if isPad {
                tapSidebarItem(app, ID.iPadSidebarAgenda)
            } else {
                element(app, ID.monthMenu).tap()
                let item = app.buttons["全部日程"].firstMatch
                XCTAssertTrue(item.waitForExistence(timeout: 5), "月历菜单应有「全部日程」")
                item.tap()
            }
        }

        audit("倒数日") { app in
            if isPad {
                tapSidebarItem(app, ID.iPadSidebarCountdown)
            } else {
                element(app, ID.monthMenu).tap()
                let item = app.buttons["倒数日"].firstMatch
                XCTAssertTrue(item.waitForExistence(timeout: 5), "月历菜单应有「倒数日」")
                item.tap()
            }
        }

        // 年视图：点月历标题 → 日期跳转 → 全年视图。
        //
        // ⚠️ 只在 iPhone 上审计：iPad 上点标题后「全年视图」入口 5 秒内没出现，
        // 排查方向有三种（面板未展开 / 该入口需滚动 / iPad 走了别的入口——侧栏的
        // `iPadSidebarYear` 已随「年视图改走方案 C」删除）。**未定论前不留假绿**，
        // 所以这里明确跳过并记为待办，不假装它通过。
        if !isPad { audit("年视图") { app in
            let title = app.buttons["选择月份或年份"].firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 10), "月历标题应可点开日期跳转")
            title.tap()
            let yearEntry = app.buttons["全年视图"]
            XCTAssertTrue(yearEntry.waitForExistence(timeout: 5), "跳转面板应有「全年视图」入口")
            yearEntry.tap()
        } }

        XCTAssertGreaterThan(audited, 10, "深层界面审计到的按钮太少（\(audited)），可能没真的打开这些界面")
        XCTAssertEqual(knownSkipped, Self.knownUnlabeledControls.count,
                       "已知未修项应恰好各命中一次（当前 \(knownSkipped)/\(Self.knownUnlabeledControls.count)）")
        XCTAssertTrue(offenders.isEmpty,
                      "以下深层界面的按钮缺少可读标签：\n" + offenders.joined(separator: "\n"))
    }

    // MARK: - Flow 12：年视图月卡的无障碍（P3-6）

    /// 年视图原先用 `.contentShape(Rectangle()) + onTapGesture` 点整张月卡：
    /// **VoiceOver 拿不到「按钮」特征与激活语义**，卡内几十个迷你日期格还会被逐个朗读，
    /// 而整张卡没有任何标签。改法：`Button` + 整卡一个标签 + 装饰网格 `accessibilityHidden`。
    ///
    /// 这条测试把「可量化」的部分钉住：12 张月卡都是**按钮**、命中区域 ≥44pt（HIG）、
    /// 卡内不再暴露独立文本元素（已合成为一个元素）。
    func testFlow12_yearOverviewMonthCardsAreAccessibleButtons() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone,
                          "iPhone 上从月历菜单进年视图；iPad 的入口在侧栏（可后续补一条）")
        let app = launchApp()

        let menu = element(app, ID.monthMenu)
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "日历页应有工具栏入口菜单")
        menu.tap()
        let dateJump = app.buttons["跳转到日期"]
        XCTAssertTrue(dateJump.waitForExistence(timeout: 5))
        dateJump.tap()

        let yearEntry = app.buttons["全年视图"]
        XCTAssertTrue(yearEntry.waitForExistence(timeout: 5), "跳转面板应有「全年视图」入口")
        yearEntry.tap()

        // 年视图的 12 张月卡：标签就是本地化后的月份名（空数据下不带日程数）。
        // 测试进程自己按 zh-Hans 算出期望名，顺带钉住「月卡标题确实本地化」。
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.setLocalizedDateFormatFromTemplate("MMMM")
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: Date())

        for month in 1...12 {
            var dc = DateComponents(); dc.year = year; dc.month = month; dc.day = 1
            let date = try XCTUnwrap(calendar.date(from: dc), "\(year) 年 \(month) 月 应能算出一个日期")
            let expectedName = formatter.string(from: date)
            let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", expectedName)).firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 3),
                          "年视图应有名为「\(expectedName)」的月卡按钮（原先它是 onTapGesture，不是按钮）")
            XCTAssertGreaterThanOrEqual(card.frame.width, 44,
                                        "「\(expectedName)」月卡命中宽度应 ≥44pt（HIG）")
            XCTAssertGreaterThanOrEqual(card.frame.height, 44,
                                        "「\(expectedName)」月卡命中高度应 ≥44pt（HIG）")
            XCTAssertEqual(card.staticTexts.count, 0,
                           "「\(expectedName)」卡内几十个迷你日期格是装饰，不应作为独立元素暴露")
        }

        // 结构从 `onTapGesture` 换成了「透明覆盖层 Button」，所以必须证明
        // **点击行为本身没被破坏**：点某个月的卡，年视图收起、日历跳到该月。
        let monthHeaderFormatter = DateFormatter()
        monthHeaderFormatter.locale = Locale(identifier: "zh_Hans_CN")
        monthHeaderFormatter.calendar = Calendar(identifier: .gregorian)
        monthHeaderFormatter.setLocalizedDateFormatFromTemplate("MMM")
        var marchDC = DateComponents(); marchDC.year = year; marchDC.month = 3; marchDC.day = 1
        let marchDate = try XCTUnwrap(calendar.date(from: marchDC))
        let marchCardName = formatter.string(from: marchDate)          // 年视图卡片：三月
        let marchHeaderName = monthHeaderFormatter.string(from: marchDate)  // 月历表头：3月

        let marchCard = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", marchCardName)).firstMatch
        XCTAssertTrue(marchCard.waitForExistence(timeout: 3))
        marchCard.tap()
        XCTAssertTrue(app.staticTexts[marchHeaderName].waitForExistence(timeout: 5),
                      "点「\(marchCardName)」卡应跳到该月（月历表头显示「\(marchHeaderName)」）——"
                      + "换成覆盖层 Button 后点击行为必须仍然有效")
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

    // MARK: - 截图巡游（仅在 Tools/shots.sh --tour 时运行）

    /// 视觉取证的「必须点击才能到达」那一半：把 Tab、月历菜单二级页、iPad 侧栏各节走一遍，
    /// 每站挂一张 `XCUIScreen.main.screenshot()`，由 `Tools/shots.sh --tour` 从结果包导出 PNG。
    /// 「无需点击就能到达」的页面走深链，由同脚本的默认模式（纯 shell）覆盖，不必进测试。
    ///
    /// 为什么默认跳过：它的断言是「页面到了」而非业务正确性，还会截图、耗时，
    /// 不该混进 `Tools/run_tests.sh` 的四通道。开关由脚本传——`TEST_RUNNER_` 前缀的
    /// 环境变量会被 xcodebuild 转发到模拟器上的测试进程（即 `TEST_RUNNER_SHOTS=1` → 这里看到 `SHOTS=1`）。
    ///
    /// 不 sleep：每一站的同步都靠「等一个该页独有的元素」，既准又快（目标 ≤ 40 秒）。
    func testScreenshotTour() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SHOTS"] == "1",
                          "截图巡游：由 Tools/shots.sh --tour 通过 TEST_RUNNER_SHOTS=1 开启")

        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        // 固定方向并在结束时还原：iPad 只在横屏才是「三栏并排」
        // （Flow 4 的结论：竖屏时侧栏是浮层且默认收起，展开会盖住中栏）
        XCUIDevice.shared.orientation = isPad ? .landscapeLeft : .portrait
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = launchApp()
        if isPad {
            tourPad(app)
        } else {
            tourPhone(app)
        }
    }

    /// 全屏截图挂成附件。`name` 就是导出后的文件名——`Tools/shots.sh` 会按 manifest.json
    /// 的 `suggestedHumanReadableName` 把 xcresult 里的随机名还原成它。
    ///
    /// 横屏（iPad 巡游）必须把像素转正：`XCUIScreen.screenshot()` 给的图是**像素竖着存**的
    /// （1668×2420 而界面是横的），直接导出会躺倒 90°，取证时得歪头看。
    private func shot(_ name: String) {
        let attachment = XCTAttachment(image: uprightIfNeeded(XCUIScreen.main.screenshot().image))
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// 横屏时把图转正（竖屏原样返回，iPhone 巡游不受影响）
    ///
    /// 判据用 **cgImage 的像素宽高**而不是 `image.size`：`XCUIScreenshot` 的像素始终是
    /// 「竖着存」的（1668×2420），横屏只体现在 `UIImage.imageOrientation` 上 —— 所以
    /// `image.size` 已经是横的、`cgImage` 还是竖的，而 `XCTAttachment(image:)` 写的是
    /// **cgImage 的像素**，于是导出的 PNG 躺倒 90°。这里用一次重绘把 orientation
    /// 烘进像素（`image.draw` 会应用 orientation），竖屏图 orientation == .up，重绘后不变。
    private func uprightIfNeeded(_ image: UIImage) -> UIImage {
        guard let cg = image.cgImage, cg.width < cg.height,
              UIDevice.current.userInterfaceIdiom == .pad else { return image }
        return UIGraphicsImageRenderer(size: image.size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    /// 巡游文案查表：--lang 切语言后 Tab 名 / 菜单项 / 导航标题都本地化，
    /// 硬编码中文会失配（截图批次实测踩到）。普通 Flow 用例固定 zh-Hans 不受影响。
    private func tourLabel(_ zh: String) -> String {
        let lang = ProcessInfo.processInfo.environment["SHOTS_LANG"] ?? "zh-Hans"
        guard lang != "zh-Hans" else { return zh }
        switch (lang, zh) {
        case ("en", "日历"): return "Calendar"
        case ("en", "黄历"): return "Almanac"
        case ("en", "我的"): return "Me"
        case ("en", "全部日程"): return "All Events"
        case ("en", "倒数日"): return "Countdown"
        case ("en", "AI 助手"): return "AI Assistant"
        case ("en", "设置"): return "Settings"
        case ("en", "AI 日历助手"): return "AI Calendar Assistant"
        case ("ja", "日历"): return "カレンダー"
        case ("ja", "黄历"): return "黄暦"
        case ("ja", "我的"): return "マイページ"
        case ("ja", "全部日程"): return "すべての予定"
        case ("ja", "倒数日"): return "カウントダウン"
        case ("ja", "AI 助手"): return "AI アシスタント"
        case ("ja", "设置"): return "設定"
        case ("ja", "AI 日历助手"): return "AI カレンダーアシスタント"
        case ("zh-Hant", "日历"): return "日曆"
        case ("zh-Hant", "黄历"): return "黃曆"
        case ("zh-Hant", "我的"): return "我的"
        case ("zh-Hant", "全部日程"): return "所有行程"
        case ("zh-Hant", "倒数日"): return "倒數日"
        case ("zh-Hant", "AI 助手"): return "AI 助理"
        case ("zh-Hant", "设置"): return "設定"
        case ("zh-Hant", "AI 日历助手"): return "AI 行事曆助理"
        default: return zh
        }
    }

    /// 切 Tab。**刻意不等「已被选中」**：`isSelected` 只能靠 `expectation` 轮询，
    /// 实测一次要 2~3 秒（4 次切换就是十几秒）；而每站「到了没」由调用方等一个
    /// 该页独有的元素来保证，一次约 1 秒，加起来反而更快也更准。
    private func switchTab(_ app: XCUIApplication, _ title: String) {
        app.tabBars.buttons[tourLabel(title)].tap()
    }

    /// 经月历工具栏菜单进二级页并截图（iPhone 上进「全部日程 / 倒数日」的唯一路径，见 Flow 6/7/8）
    private func shotViaMonthMenu(_ app: XCUIApplication,
                                 item: String, readyNav: String, name: String) {
        switchTab(app, "日历")
        let menu = element(app, ID.monthMenu)
        // 一次查询够用就不要查第二次：`waitForExistence` 本身要 1 秒，两站省下的就是 2 秒多
        var menuReady = menu.waitForExistence(timeout: 5)
        if !menuReady {
            // 兜底：上一次从菜单进的二级页还压在这个 Tab 的导航栈上，先退回根
            app.navigationBars.buttons.firstMatch.tap()
            menuReady = menu.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(menuReady, "日历页应有工具栏入口菜单")
        menu.tap()

        let entry = app.buttons[tourLabel(item)].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "入口菜单里应有「\(item)」")
        entry.tap()
        XCTAssertTrue(app.navigationBars[tourLabel(readyNav)].waitForExistence(timeout: 10),
                      "应进入「\(item)」页")
        shot(name)
    }

    /// 往上拖日历页（把月卡下方的选中日卡拖进视野）。
    ///
    /// ⚠️ **不要**以为「月卡区域拖不动」。巡游实现时一度观察到「从月卡上起手动不了、
    /// 换个起点才行」，还归因于月卡的横向翻页手势吃掉了纵向拖动；事后用 A/B 探针复测
    /// **否掉了这个结论**：同一次运行里从月卡中部（日期格上）起手照样能滚
    /// （`selectedSummary` 的 y 从 599 → 271 → −77）。
    /// 真正会出问题的是 **XCUITest 的合成拖拽偶发不落到 App 上**（表现为连拖几次都
    /// 纹丝不动、截图仍是原样）。所以这里不假设一次就成功——调用处循环拖到目标
    /// 元素真的露出来为止再截图。
    private func scrollCalendarUp(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22))
            .press(forDuration: 0.05,
                   thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)))
    }

    private func tourPhone(_ app: XCUIApplication) {
        // ① 日历首屏
        XCTAssertTrue(element(app, ID.monthMenu).waitForExistence(timeout: 15), "日历首屏应有月历工具栏")
        shot("01-日历首屏")

        // ② 点月中日后的选中摘要（月中日只出现在当月网格里，见 midMonthTarget 的说明）。
        //    摘要卡在网格下方且默认是收起的紧凑卡 —— 它**已经在屏幕内**（被底部 TabBar 压住大半），
        //    所以可见性判据要用 TabBar 的顶边，不能拿 app.frame 比（比出来永远成立，一张都不滑）。
        let t = midMonthTarget
        let cell = element(app, ID.monthDay(year: t.year, month: t.month, day: t.day))
        XCTAssertTrue(cell.waitForExistence(timeout: 10), "月历网格应有本月 \(t.day) 日")
        cell.tap()

        let summary = element(app, ID.selectedSummary)
        XCTAssertTrue(summary.waitForExistence(timeout: 5), "选中后应出现选中日摘要卡")
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.exists, "应有底部 TabBar")
        for _ in 0..<3 where summary.frame.maxY > tabBar.frame.minY {
            scrollCalendarUp(app)
        }
        XCTAssertLessThanOrEqual(summary.frame.maxY, tabBar.frame.minY,
                                 "往下滑后选中日摘要卡应完整露出（否则截出来的不是摘要）")
        shot("02-选中日摘要")

        // ③ 黄历 Tab。就绪标志用它工具栏里的「新建日程」——黄历页的导航栏标题是星期名，
        //    而该按钮只挂在 DayDetailView（日历 Tab 用的是行内摘要卡），因此是它独有的
        switchTab(app, "黄历")
        XCTAssertTrue(element(app, ID.dayDetailNewEvent).waitForExistence(timeout: 10),
                      "黄历页应出现工具栏「新建日程」")
        shot("03-黄历")

        // ④⑤ 全部日程 / 倒数日：iPhone 上只有一个入口 —— 月历工具栏菜单
        shotViaMonthMenu(app, item: "全部日程", readyNav: "全部日程", name: "04-全部日程")
        shotViaMonthMenu(app, item: "倒数日", readyNav: "倒数日", name: "05-倒数日")

        // ⑥ 我的（设置）：iCloud 同步区块在首屏之下，滚到它再截（Flow 5 的断言点）
        switchTab(app, "我的")
        XCTAssertTrue(scrollUntilVisible(app, element(app, ID.settingsSyncStatus), maxSwipes: 5),
                      "设置页应能找到 iCloud 同步状态行")
        shot("06-我的-设置")

        // ⑦ AI 助手
        switchTab(app, "AI 助手")
        XCTAssertTrue(element(app, ID.aiInput).waitForExistence(timeout: 10), "AI 助手应有输入区")
        shot("07-AI助手")
    }

    private func tourPad(_ app: XCUIApplication) {
        // (侧栏显示名, 侧栏锚点, 中栏就绪标志 = 该节的导航栏标题, 截图名)
        let sections: [(label: String, row: String, ready: String, name: String)] = [
            ("日历", ID.iPadSidebarCalendar, "日历", "01-iPad-日历"),
            ("AI 助手", ID.iPadSidebarAI, "AI 日历助手", "02-iPad-AI助手"),
            ("全部日程", ID.iPadSidebarAgenda, "全部日程", "03-iPad-全部日程"),
            ("倒数日", ID.iPadSidebarCountdown, "倒数日", "04-iPad-倒数日"),
            ("设置", ID.iPadSidebarSettings, "设置", "05-iPad-设置"),
        ]
        for s in sections {
            let row = element(app, s.row)
            if !row.waitForExistence(timeout: 5) {
                // 侧栏收起时的兜底（与 Flow 4 / Flow 9 同款，真实用户也是这一步）
                let showSidebar = app.buttons["显示边栏"].firstMatch
                if showSidebar.waitForExistence(timeout: 5) { showSidebar.tap() }
            }
            XCTAssertTrue(row.waitForExistence(timeout: 5),
                          "iPad 侧栏应有「\(s.label)」行（标识 \(s.row)）")
            row.tap()
            XCTAssertTrue(app.navigationBars[tourLabel(s.ready)].waitForExistence(timeout: 10),
                          "切到「\(s.label)」后中栏应显示导航栏标题「\(s.ready)」")
            shot(s.name)
        }
    }
}
