import XCTest
import SwiftUI
import LunarCore
@testable import LunisolarCalendarApp

// MARK: - 选中日格子的可读性（UI_DESIGN_REVIEW P3-1）
//
// 审查报告点名的真实缺陷：选中一个节日日时，格子填充用的是**装饰层**的节日原色
// （`cell.festivalTint`），而格内文字是**白字** —— 于是
//   儿童节 #FDD835 1.40:1 ／ 中秋 #F9A825 1.97:1 ／ 劳动节 #FB8C00 2.37:1
// 白字压在浅色节日底上几乎看不见。
//
// 与 `AccentContrastTests` 的分工（那条报告意见是「只测助手函数」）：
// 这里跑的是**真实路径**——遍历 `FestivalManager` 的真实节日色，
// 走视图实际使用的那个函数（`AccentContrast.bestForeground` /
// `Color.selectedCellForeground`），断言选中态前景色达标。
//
// 选的是「按亮度挑白/黑」而不是「把填充压暗到白字达标」：
// 后者会把儿童节黄、中秋金洗掉（节日识别度正是这两个颜色的价值）。

final class SelectedCellContrastTests: XCTestCase {

    // MARK: 真实路径（视图用的就是 SelectedCellForeground.resolve）

    /// 全部节日色 → 选中格文字色 → 对比度必须 ≥ 4.5:1。
    /// 这里逐色比对「视图真正拿到的那个颜色」与「黑/白里更优的一支」一致。
    func testSelectedCellForegroundMeetsAAForEveryFestivalAccent() {
        let all = FestivalManager.allAccentHexes
        XCTAssertFalse(all.isEmpty, "节日色列表不允许为空（否则这条等于没跑）")

        for hex in all {
            let resolved = SelectedCellForeground.resolve(festivalHex: hex)
            let best = AccentContrast.bestForeground(hex: hex)
            XCTAssertEqual(resolved, Color(hex: best.hex),
                           "\(hex) 的选中格文字色应为 \(best.hex)")
            XCTAssertGreaterThanOrEqual(
                best.ratio, AccentContrast.threshold,
                "\(hex) 的选中格文字色 \(best.hex) 只有 \(String(format: "%.2f", best.ratio)):1（要求 ≥ 4.5:1）"
            )
        }
    }

    /// 无节日日：决策点返回白色（品牌色填充 + 白字的既有视觉契约，缺口见下方 D8 那条）
    func testSelectedCellForegroundWithoutFestivalIsWhite() {
        XCTAssertEqual(SelectedCellForeground.resolve(festivalHex: nil), .white)
    }

    /// 决策点与「选中」无关：它只回答"在这天的节日色上该用什么字色"，
    /// 选中与否由视图决定。这里把这条边界写清楚，避免以后有人把 isSelected 混进来。
    func testResolveDependsOnlyOnFestivalColor() {
        XCTAssertEqual(SelectedCellForeground.resolve(festivalHex: "#FDD835"),
                       SelectedCellForeground.resolve(festivalHex: "#FDD835"))
        XCTAssertNotEqual(SelectedCellForeground.resolve(festivalHex: "#FDD835"),
                          SelectedCellForeground.resolve(festivalHex: nil))
    }

    /// 报告点名的两个最差样本：现在必须被判成**黑字**，且余量很大（不再是 1.40 / 1.97）
    func testReportedOffendersNowGetBlackText() {
        for (hex, name) in [("#FDD835", "儿童节黄"), ("#F9A825", "中秋金")] {
            let chosen = AccentContrast.bestForeground(hex: hex)
            XCTAssertEqual(chosen.hex, "#000000", "\(name) \(hex) 应选黑字")
            XCTAssertGreaterThanOrEqual(chosen.ratio, 9.0,
                                        "\(name) 黑字余量应远高于门槛，实际 \(String(format: "%.2f", chosen.ratio)):1")
        }
    }

    /// 反例守卫：**原实现**（一律白字）在这些颜色上必须仍然不达标。
    /// 否则说明节日表被改过、或有人把这条修复回滚了，而上面几条却还绿着。
    func testAlwaysWhiteRegressionIsStillDetectable() {
        let failing = FestivalManager.allAccentHexes.filter {
            AccentContrast.whiteOn(hex: $0) < AccentContrast.threshold
        }
        XCTAssertGreaterThanOrEqual(failing.count, 5,
                                    "原本 10 个节日色白字不达标，现在只剩 \(failing.count) 个——节日表是否被改过？")
        XCTAssertLessThan(AccentContrast.whiteOn(hex: "#FDD835"), 2.0, "儿童节黄：白字应仍是最差一档")
    }

    /// 「挑白/黑」这条路能成立的数学前提：**任一**填充色下，总有一支 ≥ 4.5:1。
    /// 最坏点是两者相等的亮度（≈0.179），此时约 4.58:1。
    /// 用亮度扫描把它钉住——若哪天有人把拾色逻辑改成"只挑更暗的那支"，这条会红。
    func testBlackOrWhiteAlwaysClearsAAForAnyFill() {
        for step in 0...100 {
            let v = Double(step) / 100.0
            let hex = String(format: "#%02X%02X%02X",
                             Int((v * 255).rounded()), Int((v * 255).rounded()), Int((v * 255).rounded()))
            let chosen = AccentContrast.bestForeground(hex: hex)
            XCTAssertGreaterThanOrEqual(chosen.ratio, AccentContrast.threshold,
                                        "灰阶 \(hex) 挑出来的 \(chosen.hex) 只有 \(String(format: "%.2f", chosen.ratio)):1")
        }
    }

    /// 拾色只在这两种情况间切换，不会返回别的颜色（视图拿它当白/黑用）
    func testBestForegroundOnlyReturnsWhiteOrBlack() {
        for hex in FestivalManager.allAccentHexes {
            XCTAssertTrue(["#FFFFFF", "#000000"].contains(AccentContrast.bestForeground(hex: hex).hex))
        }
    }

    // MARK: 接线（真实节日 + 真实派生工厂）

    /// 中秋（2026-09-25）走 `GridCellModel.derive`（月历网格用的就是它）：
    /// 填充必须仍是节日**原色**（装饰层不动），选中字色必须是黑色。
    /// 这条覆盖的正是审查报告说的「真实路径」——不是只对着助手函数跑。
    func testMidAutumnCellKeepsDecorativeFillAndGetsBlackForeground() throws {
        let cal = Calendar(identifier: .gregorian)
        let midAutumn = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 9, day: 25)))
        let festivals = FestivalManager.festivals(on: midAutumn, lunar: midAutumn.lunar)
        XCTAssertFalse(festivals.isEmpty, "2026-09-25 应是中秋（数据没了这条就失去意义）")

        let cell = GridCellModel.derive(
            date: midAutumn,
            inCurrentMonth: true,
            lunar: midAutumn.lunar,
            huangli: HuangliGenerator.generate(for: midAutumn),
            festivals: festivals,
            holidayType: .holiday,
            eventCount: 0,
            eventPriorities: []
        )

        let accentHex = try XCTUnwrap(festivals.first { $0.kind != .solarTerm }?.accentHex)
        XCTAssertEqual(cell.festivalTint, Color(hex: accentHex),
                       "填充仍是节日原色（压暗会把中秋金洗掉）")
        XCTAssertEqual(cell.selectedForeground, Color(hex: "#000000"),
                       "中秋金上必须用黑字（原实现固定白字，只有 1.97:1）")
        XCTAssertGreaterThanOrEqual(
            AccentContrast.ratio("#000000", accentHex), AccentContrast.threshold,
            "中秋格选中态的实际对比度必须达标")
    }

    /// 儿童节（2026-06-01）：同一路径，报告里最差的那个（1.40:1）
    func testChildrensDayCellGetsBlackForeground() throws {
        let cal = Calendar(identifier: .gregorian)
        let day = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let festivals = FestivalManager.festivals(on: day, lunar: day.lunar)
        let cell = GridCellModel.derive(
            date: day, inCurrentMonth: true, lunar: day.lunar,
            huangli: HuangliGenerator.generate(for: day), festivals: festivals,
            holidayType: .normal, eventCount: 0, eventPriorities: []
        )
        XCTAssertEqual(cell.selectedForeground, Color(hex: "#000000"),
                       "儿童节黄上必须用黑字（原实现固定白字，只有 1.40:1）")
    }

    // MARK: 已知缺口（不在本次修复范围，钉住现状）

    /// `appTint`（#4B6FF2）当选中填充 + 白字只有 **4.33:1**，本就低于 AA 4.5。
    /// 本次只修了节日填充这条路：无节日日的选中格仍沿用品牌色填充 + 白字（视觉契约），
    /// 不透明化之后 lunar 行从 3.83 提升到 4.33，但仍是缺口。
    ///
    /// 这条**故意钉住现状**：真要动品牌色就得先裁决 D8（改填充色 vs 改成黑字）。
    /// D8 已修（2026-10-04）：选中日填充改用 `SelectedCellFill`——品牌色按「白字 AA」
    /// 压到**刚好够**（亮度降约 5%），而不是用原 `appTint`（#4B6FF2 上白字只有 4.33:1）。
    /// 这条从"钉住缺口"翻成"守住达标"：谁把填充改回 `appTint`，它会红。
    func testSelectedFillMeetsAAWithWhiteText() {
        XCTAssertGreaterThanOrEqual(AccentContrast.ratio("#FFFFFF", SelectedCellFill.brandHex),
                                    AccentContrast.threshold,
                                    "选中日填充上的白字必须达 AA")
        XCTAssertLessThan(AccentContrast.ratio("#FFFFFF", "#4B6FF2"), AccentContrast.threshold,
                          "原 appTint 确实不达标——这条记录我们为什么要换")
        XCTAssertNotEqual(SelectedCellFill.brandHex, "#4B6FF2")
    }
}
