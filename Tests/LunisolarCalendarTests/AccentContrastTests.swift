import XCTest
import SwiftUI
@testable import LunisolarCalendarApp

/// 节日强调色的对比度审计（UI_DESIGN_REVIEW P0-4 的验收）。
///
/// 报告的验收要求是「对全部节日 accentHex 跑对比度脚本（浅色/深色各一遍），
/// 控件白字 ≥ 4.5:1」。这里把它做成**单测**而不是一次性脚本：
/// 节日表一改、有人加了个新节日色，这条会立刻红——脚本做不到这一点。
///
/// 判据（WCAG 2.1 AA 正文）：
/// - **控件层·填充**（带白字的按钮）：白字压在该色上 ≥ 4.5:1；
/// - **控件层·着色**（tint 的文字/图标）：浅色模式对白底 ≥ 4.5:1、深色模式对黑底 ≥ 4.5:1。
///
/// 装饰层（页面染色、描边、格子染色）不受约束——那正是 P0-4「分层」的另一半。
final class AccentContrastTests: XCTestCase {

    private let white = "#FFFFFF"
    private let black = "#000000"

    // MARK: 全量审计

    /// 全部节日色都必须能推导出达标的**填充**色
    func testAllFestivalAccentsYieldCompliantControlFill() {
        let all = FestivalManager.allAccentHexes
        XCTAssertFalse(all.isEmpty, "节日色列表不允许为空（否则这条测试等于没跑）")

        for hex in all {
            let safe = AccentContrast.darkenedForWhiteText(hex: hex)
            let ratio = AccentContrast.whiteOn(hex: safe)
            XCTAssertGreaterThanOrEqual(
                ratio, AccentContrast.threshold,
                "\(hex) 的控件填充色 \(safe) 白字对比度只有 \(String(format: "%.2f", ratio)):1（要求 ≥ 4.5:1）"
            )
        }
    }

    /// 全部节日色都必须能推导出达标的**着色**色（浅色模式：对白底）
    func testAllFestivalAccentsYieldCompliantControlTintOnLight() {
        for hex in FestivalManager.allAccentHexes {
            let safe = AccentContrast.darkenedForWhiteText(hex: hex)
            let ratio = AccentContrast.ratio(safe, white)
            XCTAssertGreaterThanOrEqual(
                ratio, AccentContrast.threshold,
                "\(hex) 的浅色模式 tint \(safe) 对白底只有 \(String(format: "%.2f", ratio)):1"
            )
        }
    }

    /// 全部节日色都必须能推导出达标的**着色**色（深色模式：对黑底）
    func testAllFestivalAccentsYieldCompliantControlTintOnDark() {
        for hex in FestivalManager.allAccentHexes {
            let safe = AccentContrast.lightenedForDarkBackground(hex: hex)
            let ratio = AccentContrast.ratio(safe, black)
            XCTAssertGreaterThanOrEqual(
                ratio, AccentContrast.threshold,
                "\(hex) 的深色模式 tint \(safe) 对黑底只有 \(String(format: "%.2f", ratio)):1"
            )
        }
    }

    // MARK: 前提校验（防止上面的测试因为「输入为空/全过」而变成假绿）

    /// 确认「确实有一批节日色**原始**就不达标」——否则上面三条测试可能是空转
    /// （比如有人把阈值改小、或节日表被清空）。这条把「问题真实存在」钉住。
    func testRawFestivalAccentsDoActuallyViolateTheThreshold() {
        let failing = FestivalManager.allAccentHexes.filter {
            AccentContrast.whiteOn(hex: $0) < AccentContrast.threshold
        }
        XCTAssertGreaterThanOrEqual(
            failing.count, 5,
            """
            原本应有多个节日色白字不达标（实测 10 个），现在只剩 \(failing.count) 个。
            若这是有意的（例如统一调深了节日色），请同步更新本断言与 P0-4 的文档记录；
            若不是，说明节日表被改动过、需要复核。
            """
        )
        // 报告点名的两个最差样本，单独锁住（它们仍是「必须被修正」的输入）
        XCTAssertLessThan(AccentContrast.whiteOn(hex: "#FDD835"), 2.0, "儿童节黄应属最差一档")
        XCTAssertLessThan(AccentContrast.whiteOn(hex: "#F9A825"), 2.5, "中秋金应属最差一档")
    }

    // MARK: 纯函数行为

    /// 已达标的不动：不能把本来就合规的节日色也一起改掉（否则是无谓的视觉变更）
    func testAlreadyCompliantColorIsReturnedUnchanged() {
        let ok = "#C41A1A"   // 春节红，白字 5.98:1
        XCTAssertEqual(AccentContrast.darkenedForWhiteText(hex: ok), ok,
                       "已达标的白字对比度颜色不应被改动")
    }

    func testContrastRatioIsSymmetricAndKnownValues() {
        XCTAssertEqual(AccentContrast.ratio(white, black), 21.0, accuracy: 0.01,
                       "黑白对比度应为 21:1（WCAG 的上限，用来校验公式没错）")
        XCTAssertEqual(AccentContrast.ratio(white, white), 1.0, accuracy: 0.001)
        XCTAssertEqual(AccentContrast.ratio("#F9A825", white),
                       AccentContrast.ratio(white, "#F9A825"), accuracy: 0.001)
    }

    /// 压暗是单调的：压暗后的色必须比原色更暗（保色相、只降亮度）
    func testDarkeningOnlyReducesLuminance() {
        let gold = "#F9A825"
        let safe = AccentContrast.darkenedForWhiteText(hex: gold)
        XCTAssertLessThan(AccentContrast.relativeLuminance(hex: safe),
                          AccentContrast.relativeLuminance(hex: gold))
        // 色相关系保持：原色 R>G>B，压暗后仍应 R>G>B
        let (r, g, b) = AccentContrast.components(safe)
        XCTAssertGreaterThan(r, g)
        XCTAssertGreaterThan(g, b)
    }

    // MARK: 分层类型的接线

    /// 中秋当天：装饰层仍是节日金，控件层必须换到达标色
    func testDayAccentLayersDifferOnFestivalDay() {
        let midAutumn = DateComponents(calendar: Calendar(identifier: .gregorian),
                                       year: 2026, month: 9, day: 25).date!
        let accent = DayAccent(date: midAutumn)
        XCTAssertNotEqual(accent.decorative, accent.controlFill,
                          "中秋金的白字对比度只有 1.97:1，控件填充色必须与装饰色不同")
    }

    /// 无节日当天：三层都应回落 appTint（不引入多余的颜色分歧）
    func testDayAccentFallsBackToAppTintWithoutFestival() {
        // 2026-09-30：前一个节气是 9/23 秋分、后一个是 10/8 寒露，中秋（9/25）也过了
        // —— 这一天既非公历/农历节日，也不在交节日，是干净的对照组。
        // （最初写的是 9/23，结果那天正是秋分，测试如实报错。）
        let plain = DateComponents(calendar: Calendar(identifier: .gregorian),
                                   year: 2026, month: 9, day: 30).date!
        let accent = DayAccent(date: plain)
        XCTAssertEqual(accent.decorative, Color.appTint)
        XCTAssertEqual(accent.controlFill, Color.appTint)
    }
}
