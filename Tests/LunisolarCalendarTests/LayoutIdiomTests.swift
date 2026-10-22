import XCTest
import SwiftUI
@testable import LunisolarCalendarApp

// MARK: - 布局取向：iPhone 横屏不该变成 iPad（执行计划 P3-2）
//
// 缺陷：根视图与月历网格都用 `horizontalSizeClass == .regular` 判断"是不是 iPad"。
// 但 iPhone Plus/Max **横屏**也是 regular → 手机被切成三栏、底部 TabBar 消失
// （项目自己的 `DEVICE_TEST_CHECKLIST` 里标注未验证的那条）。
//
// sizeClass 回答的是「有多宽」，不是「是什么设备」——本组测试把这条区分钉住。

final class LayoutIdiomTests: XCTestCase {

    // MARK: P3-2 的验收：iPhone 横屏保留 TabBar

    /// **回归点**：iPhone + regular（横屏）必须走单栏
    func testPhoneInLandscapeKeepsPhoneLayout() {
        XCTAssertFalse(
            LayoutIdiom.usesSplitLayout(device: .phone, horizontalSizeClass: .regular,
                                        verticalSizeClass: .compact),
            "iPhone 横屏（宽而矮）必须保留底部 TabBar，不能切成 iPad 三栏"
        )
    }

    func testPhoneInPortraitKeepsPhoneLayout() {
        XCTAssertFalse(LayoutIdiom.usesSplitLayout(device: .phone, horizontalSizeClass: .compact,
                                                   verticalSizeClass: .regular))
    }

    // MARK: 另一侧的验收：iPad 仍然三栏

    func testPadInRegularWidthUsesSplitLayout() {
        XCTAssertTrue(LayoutIdiom.usesSplitLayout(device: .pad, horizontalSizeClass: .regular,
                                                  verticalSizeClass: .regular))
    }

    /// iPad 分屏/侧拉的窄栏（compact）保持既有行为：回落单栏
    func testPadInCompactWidthKeepsSingleColumn() {
        XCTAssertFalse(LayoutIdiom.usesSplitLayout(device: .pad, horizontalSizeClass: .compact,
                                                   verticalSizeClass: .regular),
                       "iPad 侧拉窄栏回落到单栏是既有行为，本次不改变")
    }

    // MARK: 边界

    /// 宽度未知时保守走单栏：宁可少切一次三栏，也不要误切
    func testUnknownSizeClassFallsBackToSingleColumn() {
        XCTAssertFalse(LayoutIdiom.usesSplitLayout(device: .pad, horizontalSizeClass: nil))
        XCTAssertFalse(LayoutIdiom.usesSplitLayout(device: .phone, horizontalSizeClass: nil))
    }

    /// 2026-10-22 折叠屏适配后：**设备种类不再参与判定**。
    /// Mac 上的 iPad App 窗口本就是「宽而高」，走分栏是对的（旧规则要求 idiom == .pad 才分栏）。
    func testDeviceKindNoLongerDecidesSplitLayout() {
        for device in [LayoutIdiom.Device.mac, .other, .phone, .pad] {
            XCTAssertTrue(LayoutIdiom.usesSplitLayout(device: device,
                                                      horizontalSizeClass: .regular,
                                                      verticalSizeClass: .regular),
                          "\(device) 在宽而高时都应走分栏")
        }
    }

    // MARK: 折叠屏（iPhone Duo，2026-10-22 适配新增）

    /// 横屏手机是「宽而矮」：即使宽度 regular，也必须保持手机布局（P3-2 意图不变）
    func testPhoneLandscapeStaysPhoneLayoutViaVerticalClass() {
        XCTAssertFalse(
            LayoutIdiom.usesSplitLayout(device: .phone,
                                        horizontalSizeClass: .regular,
                                        verticalSizeClass: .compact),
            "宽而矮（横屏手机）必须保留底部 TabBar 布局"
        )
    }

    /// 折叠屏展开是「宽而高」：应走分栏 —— 这是本次适配的目标
    func testUnfoldedFoldableUsesSplitLayout() {
        XCTAssertTrue(
            LayoutIdiom.usesSplitLayout(device: .phone,
                                        horizontalSizeClass: .regular,
                                        verticalSizeClass: .regular),
            "折叠屏展开（宽而高）应启用分栏，否则内屏只能当大号手机用"
        )
    }

    /// 折叠屏合起（外屏 5.4 英寸）是窄的：必须单栏
    func testFoldedFoldableKeepsSingleColumn() {
        XCTAssertFalse(
            LayoutIdiom.usesSplitLayout(device: .phone,
                                        horizontalSizeClass: .compact,
                                        verticalSizeClass: .regular),
            "外屏较窄时必须单栏"
        )
    }

    // MARK: 反例守卫：证明这条修复针对的是真实差异

    /// 若只按宽度判（原实现），iPhone 横屏会被判成"分栏"——这正是缺陷本身。
    /// 这条把「两种判据在 iPhone 横屏上结论不同」写死：将来谁把判据改回宽度，
    /// 上面的 testPhoneInLandscapeKeepsPhoneLayout 会红，而这条说明它红得有道理。
    func testWidthOnlyPredicateWouldMisclassifyPhoneLandscape() {
        let sizeClassOnly = { (h: UserInterfaceSizeClass?) in h == .regular }
        XCTAssertTrue(sizeClassOnly(.regular), "只按宽度时 iPhone 横屏=regular → 被判成分栏（缺陷）")
        XCTAssertNotEqual(
            sizeClassOnly(.regular),
            LayoutIdiom.usesSplitLayout(device: .phone, horizontalSizeClass: .regular,
                                        verticalSizeClass: .compact),
            "新判据必须在 iPhone 横屏上给出与旧判据不同的结论（否则这次修复等于没做）"
        )
    }

    // MARK: 接线守卫（为什么退一步扫源码）

    /// 两个布局判据必须走 `LayoutIdiom`，不能退回「按宽度判」。
    ///
    /// 这两处判据都在 SwiftUI 视图里（`AdaptiveRootView.body` 与 `CalendarMonthView.isIPadSplit`），
    /// 单测构造不出带 environment 的 View，所以退一步扫源码。扫描范围**只限这两处各一行**，
    /// 格式漂移风险很低；真漂了这条会红，并且下面的说明会告诉你怎么改。
    ///
    /// 为什么值得这么麻烦：P3-2 的验收是**行为**（iPhone 横屏保留 TabBar），
    /// 而按宽度判的写法恰恰会让这条验收失效——不加守卫的话，谁把它改回去都没人发现。
    func testLayoutDecisionSitesGoThroughLayoutIdiom() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/LunisolarCalendarTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // <repo>

        let sites: [(path: String, expected: String)] = [
            ("Sources/LunisolarCalendarApp/App/LunisolarCalendarApp.swift",
             "if LayoutIdiom.usesSplitLayout(horizontalSizeClass: hSizeClass, verticalSizeClass: vSizeClass) {"),
            ("Sources/LunisolarCalendarApp/Views/CalendarMonthView.swift",
             "private var isIPadSplit: Bool { LayoutIdiom.usesSplitLayout(horizontalSizeClass: hSizeClass, verticalSizeClass: vSizeClass) }"),
        ]

        for site in sites {
            let url = repoRoot.appendingPathComponent(site.path)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                throw XCTSkip("读不到 \(site.path)（该守卫只在仓库源码树下运行）")
            }
            // 只看**代码**行：注释里正该出现「不要用 hSizeClass == .regular」这种说明，
            // 第一版守卫没排除注释，结果被自己的解释性注释判红（已修）。
            let code = text
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")

            XCTAssertTrue(code.contains(site.expected),
                          "\(site.path) 的布局判据应走 LayoutIdiom（P3-2）。若只是格式变了，请同步本测试的 expected 字符串")
            XCTAssertFalse(code.contains("hSizeClass == .regular"),
                           "\(site.path) 的**代码**里出现了按宽度判分栏的写法——iPhone Plus/Max 横屏会被误判成 iPad（P3-2）")
        }
    }

    /// 当前设备形态在本机（模拟器/宿主）应是可判定的具体值，而不是 .other。
    /// `@MainActor`：`LayoutIdiom.current` 读的是主线程隔离的 `UIDevice`。
    @MainActor
    func testCurrentDeviceIsResolved() {
        XCTAssertNotEqual(LayoutIdiom.current, .other,
                          "拿不到设备形态说明 UIDevice 分支没生效——那会让所有设备都走单栏")
    }
}
