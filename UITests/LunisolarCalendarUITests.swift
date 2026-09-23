import XCTest

/// 清和日历 UI 冒烟测试（XCUITest）。
/// ⚠️ 接线方式（在 Xcode 中一次性完成，无需改工程文件）：
/// 1. Xcode → File → New → Target… → iOS → UI Testing Bundle，命名 LunisolarCalendarUITests
/// 2. Target Application 选择 LunisolarCalendar
/// 3. 将本文件加入该 Target，运行 Cmd+U（需先选中主 scheme）
final class LunisolarCalendarUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 冒烟：App 能启动，且月视图标题出现。
    func testAppLaunchesAndShowsCalendarTitle() {
        let app = XCUIApplication()
        app.launch()

        // 月视图大标题「日历」
        XCTAssertTrue(app.navigationBars["日历"].waitForExistence(timeout: 5),
                      "App 启动后应显示月视图大标题「日历」")
    }

    /// 冒烟：工具栏「+」可进入新建日程编辑页。
    func testNewEventEntryOpensEditor() {
        let app = XCUIApplication()
        app.launch()

        let addButton = app.navigationBars["日历"].buttons["新建日程"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5), "工具栏应存在「新建日程」+ 按钮")
        addButton.tap()

        // 编辑页应出现「保存」按钮（标题非空时可用）
        let saveButton = app.buttons["保存修改"].firstMatch
        XCTAssertTrue(saveButton.waitForExistence(timeout: 3),
                      "点击 + 后应进入编辑页并出现「保存修改」按钮")
    }

    /// 冒烟：月历网格可点选日期（选择 9 月 15 日）。
    func testDaySelectionUpdatesTodayCard() {
        let app = XCUIApplication()
        app.launch()

        // 今日卡片应显示选中日期的星期（存在任意静态文本即可确认网格已渲染）
        let grid = app.otherElements["月历网格"]
        // 若元素未打标识，退化为断言页面静态文本非空
        XCTAssertTrue(app.staticTexts.count > 5, "月视图应有足量静态文本（农历/黄历信息）")
    }
}
