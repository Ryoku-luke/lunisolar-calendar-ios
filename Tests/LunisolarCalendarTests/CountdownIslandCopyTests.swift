import XCTest
@testable import LunisolarCalendarApp

// MARK: - 倒数日「灵动岛」文案的用词约束（把人工审计升级成守卫）
//
// 约束来自 2026-10-05 的文案规范化：
//   ① 不再用行话「上岛 / 下岛 / 在岛上」；
//   ② 英/日提到该区域必须写全称 "Dynamic Island"，不能只写 "Island"；
//   ③ 该区域是**硬件显示位置**，不得表述为可"开启/关闭"（用户能开关的是 App 的时间胶囊）。
// 这些此前只活在我的一次性脚本里 —— 脚本跑完就没了，下次没人拦得住；放进测试才留得住。

final class CountdownIslandCopyTests: XCTestCase {

    private static let locales = ["zh-Hans", "zh-Hant", "en", "ja"]

    /// 仓库根 → 语言资源目录（按源码路径读取，与既有本地化测试一致；
    /// 测试 target 没有资源，不能用 Bundle.module）
    private var resourcesDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // LunisolarCalendarTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // 仓库根
            .appendingPathComponent("Sources/LunisolarCalendarApp/Resources")
    }

    /// 取某语言表里所有「值」（用正则在源码上解析，避开转义陷阱）
    private func values(_ locale: String) throws -> [String] {
        let url = resourcesDir.appendingPathComponent("\(locale).lproj/Localizable.strings")
        let text = try String(contentsOf: url, encoding: .utf8)
        let re = try NSRegularExpression(
            pattern: #"^"(?:[^"\\]|\\.)*"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;$"#, options: [.anchorsMatchLines])
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range(at: 1))
        }
    }

    func testNoColloquialIslandTermsInAnyValue() throws {
        for locale in Self.locales {
            for value in try values(locale) {
                for word in ["上岛", "下岛", "在岛上"] {
                    XCTAssertFalse(value.contains(word), "[\(locale)] 值里仍有行话「\(word)」：\(value)")
                }
            }
        }
    }

    func testEnglishAndJapaneseUseFullDynamicIslandName() throws {
        for locale in ["en", "ja"] {
            for value in try values(locale) {
                var rest = value[...]
                while let r = rest.range(of: "Island") {
                    XCTAssertTrue(rest[rest.startIndex..<r.lowerBound].hasSuffix("Dynamic "),
                                  "[\(locale)] 出现单独的 Island（应写 Dynamic Island）：\(value)")
                    rest = rest[r.upperBound...]
                }
            }
        }
    }

    func testIslandIsNeverDescribedAsSomethingYouTurnOnOrOff() throws {
        for locale in Self.locales {
            for value in try values(locale) {
                for phrase in ["灵动岛未开启", "Dynamic Island Is Off", "Dynamic Island がオフ"] {
                    XCTAssertFalse(value.contains(phrase), "[\(locale)] 把硬件位置说成可开关：\(value)")
                }
            }
        }
    }
}
