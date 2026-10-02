import XCTest
@testable import LunisolarCalendarApp

// MARK: - UI 测试标识副本的防漂移测试
//
// `LunisolarCalendarUITests` 没有链接 App 的框架模块，无法 `import LunisolarCalendarApp`，
// 因此 `LunisolarCalendarUITests.swift` 里留了一份 `AccessibilityID` 的**字面量副本**
// （`private enum ID`）。原来的假设是「失配不会静默——找不到元素就是测试红」。
//
// 2026-10-02 实锤这个假设不成立：Flow 3d 新增 `aiGoToCreatedDay` 时只改了 App 侧，
// 副本没跟。结果不是「测试红」，而是 **UI 测试 target 根本编译不过**；而 UI 测试 target
// 不在 SwiftPM 包里，`swift test` 完全看不见它——本地 356 个测试全绿，直到 xcodebuild 才炸。
//
// 本测试直接把那份副本从源码里读出来对照 `AccessibilityID`，让漂移在 `swift test` 阶段暴露。

final class UITestIDMirrorTests: XCTestCase {

    /// `<repo>/LunisolarCalendarUITests/LunisolarCalendarUITests.swift`
    private static let uiTestSourcePath = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // Tests/LunisolarCalendarTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // <repo>
        .appendingPathComponent("LunisolarCalendarUITests/LunisolarCalendarUITests.swift")
        .path

    /// 副本枚举体（`private enum ID { ... }` 的内容）。
    /// 用 `\n}\n` 定界：枚举体内部的函数右括号都带缩进，只有枚举自己的右括号顶格。
    private func mirrorBody() throws -> String {
        let path = Self.uiTestSourcePath
        guard let source = try? String(contentsOfFile: path, encoding: .utf8) else {
            throw XCTSkip("读不到 UI 测试源码（\(path)）：该守卫只在仓库源码树下运行")
        }
        guard let start = source.range(of: "private enum ID {") else {
            throw XCTSkip("UI 测试源码里已找不到 `private enum ID {`——若副本被删除，请连同本测试一起删")
        }
        let body = source[start.upperBound...]
        guard let end = body.range(of: "\n}\n") else {
            throw XCTSkip("UI 测试里的 `private enum ID` 体结构变了，本测试的界标需要同步更新")
        }
        return String(body[..<end.lowerBound])
    }

    private func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map { match in
            (0..<match.numberOfRanges).map { index in
                guard let r = Range(match.range(at: index), in: text) else { return "" }
                return String(text[r])
            }
        }
    }

    /// 副本里 `static let name = "value"` 的 name → value
    private func mirrorConstants() throws -> [String: String] {
        var result: [String: String] = [:]
        for groups in matches(#"static let (\w+) = "([^"]*)""#, in: try mirrorBody()) where groups.count == 3 {
            result[groups[1]] = groups[2]
        }
        return result
    }

    // MARK: - 断言

    /// 副本声明的每个字面量必须真的存在于 App 侧目录。
    /// 这条挡住的是**改值/改名**漂移：副本仍是合法字符串，但 App 侧已经没有这个标识了，
    /// UI 测试会稳定地找不到元素（或更糟：找到别的元素）。
    func testEveryMirrorLiteralExistsInAppCatalog() throws {
        let constants = try mirrorConstants()
        XCTAssertFalse(constants.isEmpty, "没有解析到任何副本常量——本测试的解析正则可能已失效")

        let catalog = Set(AccessibilityID.all)
        for (name, value) in constants.sorted(by: { $0.key < $1.key }) {
            XCTAssertTrue(catalog.contains(value),
                          "UI 测试副本 ID.\(name) = \"\(value)\" 不在 App 侧 AccessibilityID.all 里："
                          + "要么 App 侧删/改了标识，要么副本写错了")
        }
    }

    /// UI 测试里引用到的每个 `ID.<name>` 都必须在副本里定义。
    /// 这条正是 2026-10-02 那次失败的形态（引用在前、定义漏加）——只是那次是编译错误，
    /// 而编译错误只有 xcodebuild 会报。
    func testEveryReferencedMirrorNameIsDefined() throws {
        let constants = try mirrorConstants()
        let functions = Set(matches(#"static func (\w+)\("#, in: try mirrorBody()).compactMap { $0.count == 2 ? $0[1] : nil })
        XCTAssertFalse(functions.isEmpty, "副本里的 `monthDay` 动态标识函数不见了")

        let source = try String(contentsOfFile: Self.uiTestSourcePath, encoding: .utf8)
        var referenced = Set<String>()
        for groups in matches(#"\bID\.(\w+)"#, in: source) where groups.count == 2 {
            referenced.insert(groups[1])
        }
        XCTAssertFalse(referenced.isEmpty, "没有解析到任何 `ID.<name>` 引用——解析正则可能已失效")

        for name in referenced.sorted() {
            XCTAssertTrue(constants.keys.contains(name) || functions.contains(name),
                          "UI 测试引用了 ID.\(name)，但 `private enum ID` 副本里没有定义它："
                          + "在副本里补上（值必须与 App 侧 AccessibilityID.\(name) 一致），否则 UI 测试 target 编译不过")
        }
    }

    func testMirrorHasNoDuplicateNamesOrValues() throws {
        let body = try mirrorBody()
        let names = matches(#"static let (\w+) = "([^"]*)""#, in: body).compactMap { $0.count == 3 ? $0[1] : nil }
        let values = matches(#"static let (\w+) = "([^"]*)""#, in: body).compactMap { $0.count == 3 ? $0[2] : nil }
        XCTAssertEqual(Set(names).count, names.count, "副本里有重名常量")
        XCTAssertEqual(Set(values).count, values.count, "副本里有重复的字面量值")
    }

    /// 副本的 `monthDay` 格式必须与 App 侧逐位一致：
    /// 格式漂移是**静默**的（不报错、不编译失败，就是点不到日期格）。
    func testMonthDayFormatMatchesAppSide() throws {
        let formats = matches(#"String\(format: "([^"]*)""#, in: try mirrorBody())
        XCTAssertEqual(formats.count, 1, "副本里应当恰好有一处 monthDay 格式串")
        let mirrorFormat = try XCTUnwrap(formats.first?.last)

        for (year, month, day) in [(2026, 1, 1), (2026, 9, 6), (2026, 10, 1), (2024, 12, 31)] {
            let produced = String(format: mirrorFormat, year, month, day)
            XCTAssertEqual(produced, AccessibilityID.monthDay(year: year, month: month, day: day),
                           "UI 测试副本的 monthDay 格式与 App 侧不一致（y\(year)m\(month)d\(day)）")
        }
    }
}
