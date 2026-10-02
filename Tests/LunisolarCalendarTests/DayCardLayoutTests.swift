import XCTest
import SwiftUI
@testable import LunisolarCalendarApp

// MARK: - 日期卡在辅助字号下的重排（执行计划 P3-4）
//
// 缺陷：日期胶囊里的数字用 `AppTheme.Font.numeralXL`（基准 56pt，经 UIFontMetrics
// 按 Dynamic Type 缩放），而胶囊写死了 `.frame(width: 92)` / `(width: 110)`。
// 默认字号够放「31」，辅助字号档位把 56pt 放大 2–3 倍后数字被裁掉 ——
// 用户把字调大，反而看不见日期。
//
// 修法两层：①辅助字号档位改成上下堆叠（数字独占一行）；②胶囊宽度改成 minWidth、
// 数字加 `.fixedSize(horizontal:)`，任何档位下都不会被父级压缩成截断。
//
// 排布决策抽成 `DayCardLayout.axis(for:)`（纯函数）以便单测；
// 两个调用点在 SwiftUI 视图里，另有接线守卫（只看代码行）。

final class DayCardLayoutTests: XCTestCase {

    // MARK: 决策本身

    /// 辅助字号档位必须纵向堆叠（数字独占一行）
    func testAccessibilitySizesStackVertically() {
        for size in DynamicTypeSize.allCases where size.isAccessibilitySize {
            XCTAssertEqual(DayCardLayout.axis(for: size), .vertical,
                           "\(size) 是辅助字号档位，必须纵向堆叠")
        }
    }

    /// 非辅助字号档位保持横排（不引入无谓的视觉变更）
    func testStandardSizesStayHorizontal() {
        for size in DynamicTypeSize.allCases where !size.isAccessibilitySize {
            XCTAssertEqual(DayCardLayout.axis(for: size), .horizontal,
                           "\(size) 不是辅助字号档位，应保持横排")
        }
    }

    /// 全覆盖：每个档位都有明确结论，且恰好 5 个辅助档位（`accessibility1...5`）。
    /// 这条同时锁住"将来新增档位别忘了判定"——枚举加成员时 allCases 会变长，这里会红。
    func testEverySizeIsClassified() {
        let sizes = DynamicTypeSize.allCases
        XCTAssertGreaterThan(sizes.count, 10, "档位太少，枚举可能变了")
        XCTAssertEqual(sizes.filter(\.isAccessibilitySize).count, 5,
                       "辅助字号档位应为 accessibility1…accessibility5")
        XCTAssertEqual(sizes.count,
                       sizes.filter { DayCardLayout.axis(for: $0) == .vertical }.count
                       + sizes.filter { DayCardLayout.axis(for: $0) == .horizontal }.count,
                       "每个档位都必须被判定成横排或竖排")
    }

    /// 分界点：`xxxLarge` 横排、`accessibility1` 竖排（判据换档位时这条会红）
    func testBoundaryBetweenStandardAndAccessibility() {
        XCTAssertEqual(DayCardLayout.axis(for: .xxxLarge), .horizontal)
        XCTAssertEqual(DayCardLayout.axis(for: .accessibility1), .vertical)
    }

    // MARK: 接线守卫（视图里的分支单测够不着）

    /// 两处日期卡必须：①用 adaptiveCardStack ②胶囊用 minWidth 而不是固定 width
    /// ③数字带 fixedSize（不被压缩截断）。
    ///
    /// 与 `LayoutIdiomTests` / `LocalizationTests` 里的接线守卫同一套路与理由：
    /// 这几行都在 SwiftUI 视图里，单测构造不出带 environment 的 View。
    func testDayCardsUseTheAccessibilitySafeLayout() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

        let sites: [(path: String, legacyFixedWidth: String)] = [
            ("Sources/LunisolarCalendarApp/Views/SelectedDayCardView.swift", ".frame(width: 92)"),
            ("Sources/LunisolarCalendarApp/Views/DayDetailView.swift", ".frame(width: 110)"),
        ]

        for site in sites {
            let url = repoRoot.appendingPathComponent(site.path)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                throw XCTSkip("读不到 \(site.path)（该守卫只在仓库源码树下运行）")
            }
            // 只看代码行：注释里正该出现旧写法/说明
            let code = text
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")

            XCTAssertTrue(code.contains("adaptiveCardStack(spacing:"),
                          "\(site.path) 的日期卡应走 adaptiveCardStack（辅助字号下堆叠）")
            XCTAssertTrue(code.contains(".frame(minWidth:"),
                          "\(site.path) 的胶囊应用 minWidth：固定宽度会在辅助字号下裁掉数字")
            XCTAssertFalse(code.contains(site.legacyFixedWidth),
                           "\(site.path) 退回了 \(site.legacyFixedWidth)——数字会被裁掉（P3-4）")
            XCTAssertTrue(code.contains(".fixedSize(horizontal: true, vertical: false)"),
                          "\(site.path) 的日期数字应带 fixedSize，避免被父级压缩成截断")
        }
    }
}
