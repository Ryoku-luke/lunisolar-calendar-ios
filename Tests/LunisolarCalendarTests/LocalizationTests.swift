import XCTest
@testable import LunisolarCalendarApp

// MARK: - 本地化完整性（执行计划 P3-3）
//
// 这一层此前**完全没有测试**：4 张 `.strings` 表 472 个 key，key 是否齐备、
// 源码里查的 key 是否真的存在，全靠人眼。于是漏了两类：
//   1. `NSLocalizedString("…")` 查了表里没有的 key（3 条 iPad 详情占位副标题）——
//      英文界面直接显示中文；
//   2. `Text("最高\(x)° 最低\(y)°")` 走 LocalizedStringKey 查表，但 4 张表都没有这条 key。
//
// 本组测试把三类检查固定下来（都在源码/资源层，不需要模拟器）：
//   A. 四张表 key 集合一致、无重复、无空翻译；
//   B. 源码里**显式查表**的 key（NSLocalizedString / L10n.str）在四张表里都存在；
//   C. `Text("字面量")` 的 key 也存在（少量刻意不翻译的走白名单）；
//   D. `Text("含中文的\(插值)")` 必须进白名单——插值后的 key 形如 `%@/%d`，
//      源码级无法可靠推断，所以用"必须显式声明"代替"自动判定"。
//
// 不覆盖（诚实说明）：纯插值（不含中文）的字面量、以及 `.stringsdict` 复数规则。

final class LocalizationTests: XCTestCase {

    private static let languages = ["en", "zh-Hans", "zh-Hant", "ja"]

    /// 刻意**不翻译**的 `Text` 字面量：key 与理由
    private static let untranslatedTextLiterals: [String: String] = [
        "© 2026 Qinghe Studio. All rights reserved.": "版权行：各语言统一英文",
        "—": "占位破折号，无语言学含义",
    ]

    /// `Text("含中文的\(插值)")` 白名单：字面量 → 理由
    private static let interpolatedChineseLiterals: [String: String] = [
        "\\(selLunar.yearGanZhi)年": "干支纪年属历法专名，年后缀随中文（与农历月/日名同一政策）",
    ]

    // MARK: - 工具

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/LunisolarCalendarTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // <repo>
    }

    private func tableRaw(_ language: String) throws -> String {
        let url = repoRoot.appendingPathComponent(
            "Sources/LunisolarCalendarApp/Resources/\(language).lproj/Localizable.strings")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// 解析 `.strings`：返回 key → value，并统计无法解析的行（防止解析器与实际文件悄悄错位）
    private func parse(_ language: String) throws -> (pairs: [(key: String, value: String)], unparsed: [String]) {
        let raw = try tableRaw(language)
        let pattern = #"^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;"#
        let regex = try NSRegularExpression(pattern: pattern)
        var pairs: [(String, String)] = []
        var unparsed: [String] = []

        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(line).trimmingCharacters(in: .whitespaces)
            if text.isEmpty || text.hasPrefix("/*") || text.hasPrefix("//") || text.hasPrefix("*") { continue }
            let ns = String(line) as NSString
            if let m = regex.firstMatch(in: String(line), range: NSRange(location: 0, length: ns.length)) {
                let key = ns.substring(with: m.range(at: 1))
                let value = ns.substring(with: m.range(at: 2))
                pairs.append((key, value))
            } else {
                unparsed.append(text)
            }
        }
        return (pairs, unparsed)
    }

    /// 源码里所有 `.swift` 文件的内容
    private func sourceFiles() -> [(name: String, text: String)] {
        let root = repoRoot.appendingPathComponent("Sources/LunisolarCalendarApp")
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        var out: [(String, String)] = []
        for case let url as URL in e where url.pathExtension == "swift" {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                out.append((url.lastPathComponent, text))
            }
        }
        return out
    }

    /// 去掉注释行再扫源码。
    ///
    /// ⚠️ 必须做这一步：本文件第一版扫到了**自己写在代码里的解释性注释**
    /// （注释里引用了 `Text("最高\(max)° 最低\(min)°")` 作为反例）而误报。
    /// 只按**行首**判断注释，不做行内截断——行内截断会把 `"qinghe://…"` 这类
    /// 含 `//` 的字面量截坏，反而制造假阳性。
    private func codeOnly(_ text: String) -> String {
        var inBlockComment = false
        return text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if inBlockComment {
                if trimmed.contains("*/") { inBlockComment = false }
                return ""
            }
            if trimmed.hasPrefix("/*") {
                if !trimmed.contains("*/") { inBlockComment = true }
                return ""
            }
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") { return "" }
            return String(line)
        }.joined(separator: "\n")
    }

    private func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            m.numberOfRanges > 1 ? ns.substring(with: m.range(at: 1)) : nil
        }
    }

    // MARK: - A. 四张表本身

    func testLanguageTablesHaveIdenticalKeySets() throws {
        var sets: [String: Set<String>] = [:]
        for language in Self.languages {
            let (pairs, unparsed) = try parse(language)
            XCTAssertTrue(unparsed.isEmpty,
                          "\(language).strings 有 \(unparsed.count) 行无法解析（解析器与实际文件已错位）：\(unparsed.prefix(3))")
            sets[language] = Set(pairs.map(\.key))
            XCTAssertFalse(pairs.isEmpty, "\(language).strings 不允许为空")
        }
        let base = try XCTUnwrap(sets["zh-Hans"])
        for language in Self.languages where language != "zh-Hans" {
            let other = try XCTUnwrap(sets[language])
            XCTAssertEqual(other, base, """
            \(language) 与 zh-Hans 的 key 集合不一致：\
            缺 \(base.subtracting(other).sorted().prefix(5))，\
            多 \(other.subtracting(base).sorted().prefix(5))
            """)
        }
    }

    func testNoDuplicateKeysWithinATable() throws {
        for language in Self.languages {
            let (pairs, _) = try parse(language)
            let keys = pairs.map(\.key)
            let duplicates = Dictionary(grouping: keys, by: { $0 }).filter { $0.value.count > 1 }.keys
            XCTAssertTrue(duplicates.isEmpty,
                          "\(language).strings 有重复 key（.strings 会静默取最后一条）：\(duplicates.sorted().prefix(5))")
        }
    }

    func testNoEmptyTranslations() throws {
        for language in Self.languages {
            let (pairs, _) = try parse(language)
            let empty = pairs.filter { $0.value.trimmingCharacters(in: .whitespaces).isEmpty }.map(\.key)
            XCTAssertTrue(empty.isEmpty, "\(language).strings 有空翻译：\(empty.prefix(5))")
        }
    }

    // MARK: - B. 源码里显式查表的 key

    func testExplicitKeysUsedInSourceExistInAllTables() throws {
        var tables: [String: Set<String>] = [:]
        for language in Self.languages { tables[language] = Set(try parse(language).pairs.map(\.key)) }

        var used: [String: Set<String>] = [:]
        for file in sourceFiles() {
            let code = codeOnly(file.text)
            for key in matches(#"(?:NSLocalizedString|L10n\.str)\(\s*"((?:[^"\\]|\\.)*)""#, in: code) {
                used[key, default: []].insert(file.name)
            }
        }
        XCTAssertGreaterThan(used.count, 200, "扫到的 key 太少（\(used.count)），正则或目录结构可能变了")

        for language in Self.languages {
            let missing = used.filter { !(tables[language] ?? []).contains($0.key) }
            XCTAssertTrue(missing.isEmpty, """
            \(language).strings 缺少源码里查的 \(missing.count) 个 key（界面会显示中文 key）：
            \(missing.sorted { $0.key < $1.key }.prefix(5).map { "「\($0.key)」← \($0.value.sorted())" })
            """)
        }
    }

    // MARK: - C. Text("字面量") 的 key

    func testTextLiteralKeysUsedInSourceExistInAllTables() throws {
        var tables: [String: Set<String>] = [:]
        for language in Self.languages { tables[language] = Set(try parse(language).pairs.map(\.key)) }

        var used: [String: Set<String>] = [:]
        for file in sourceFiles() {
            // 只取**不含插值**的字面量：含插值的 key 形如 %@/%d，源码级推不准（见 D 段）
            let code = codeOnly(file.text)
            for literal in matches(#"\bText\(\s*"((?:[^"\\]|\\.)*)"\s*\)"#, in: code) where !literal.contains("\\(") {
                used[literal, default: []].insert(file.name)
            }
        }

        for (literal, files) in used {
            if let reason = Self.untranslatedTextLiterals[literal] {
                XCTAssertFalse(reason.isEmpty, "白名单条目必须写理由：\(literal)")
                continue
            }
            for language in Self.languages {
                XCTAssertTrue((tables[language] ?? []).contains(literal),
                              "\(language).strings 缺 `Text(\"\(literal)\")` 的 key ← \(files.sorted())")
            }
        }
    }

    // MARK: - D. Text("含中文的\(插值)") 必须显式声明

    /// 这一类正是 P3-3 漏掉的第二处（天气高低温）：`Text("最高\(x)° 最低\(y)°")` 走查表，
    /// 但表里没有对应 key。源码级推不出插值后的 key（%@ / %d / %lld 取决于类型），
    /// 所以这里要求：**含中文的插值 Text 必须在白名单里写明理由**，否则新增一处就红。
    func testInterpolatedTextLiteralsWithChineseAreAllowlisted() {
        var offenders: [String: Set<String>] = [:]
        for file in sourceFiles() {
            let code = codeOnly(file.text)
            for literal in matches(#"\bText\(\s*"((?:[^"\\]|\\.)*)""#, in: code) {
                guard literal.contains("\\("), literal.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) })
                else { continue }
                if Self.interpolatedChineseLiterals[literal] != nil { continue }
                offenders[literal, default: []].insert(file.name)
            }
        }
        XCTAssertTrue(offenders.isEmpty, """
        这些 `Text("…")` 字面量含中文又有插值，会走 LocalizedStringKey 查表，但插值后的 key 无法源码级推断。
        请二选一：①改成显式 NSLocalizedString（推荐，B 段的检查会覆盖它）；
        ②确属不该翻译的（历法专名等）就加进 interpolatedChineseLiterals 白名单并写明理由。
        当前未声明的：\(offenders.map { "「\($0.key)」← \($0.value.sorted())" })
        """)
    }

    // MARK: - 月份名（P3-3 第一处）

    func testMonthLabelIsLocalizedForEveryLanguage() throws {
        let cal = Calendar(identifier: .gregorian)
        let september = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 9, day: 15)))

        XCTAssertEqual(MonthLabel.name(for: september, locale: Locale(identifier: "en_US")), "Sep",
                       "英文必须是月名——原先写死「9月」（P3-3）")
        XCTAssertEqual(MonthLabel.name(for: september, locale: Locale(identifier: "zh_Hans_CN")), "9月")
        XCTAssertEqual(MonthLabel.name(for: september, locale: Locale(identifier: "ja_JP")), "9月")
        XCTAssertEqual(MonthLabel.name(for: september, locale: Locale(identifier: "zh_Hant_TW")), "9月")
    }

    /// 接线守卫：月历标题必须走 `MonthLabel`，不能退回写死的「\(月)月」。
    ///
    /// 标题那行在 SwiftUI 视图里（`CalendarMonthView.monthHeader`），单测构造不出该 View，
    /// 所以退一步扫源码——只查这一处、且只看代码行（注释里正该出现旧写法作为反例）。
    /// 与 `LayoutIdiomTests` 里的接线守卫同一套路与同一理由。
    func testMonthHeaderUsesMonthLabel() throws {
        let url = repoRoot.appendingPathComponent("Sources/LunisolarCalendarApp/Views/CalendarMonthView.swift")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw XCTSkip("读不到 CalendarMonthView.swift（该守卫只在仓库源码树下运行）")
        }
        let code = codeOnly(text)
        XCTAssertTrue(code.contains("MonthLabel.name(for: currentMonth)"),
                      "月历标题应走 MonthLabel（locale 感知）")
        // 用原始字符串写目标片段：`\(` 在这里是字面量，不会被当成插值
        XCTAssertFalse(code.contains(#""\(currentMonth.month)月""#),
                       "月历标题退回了写死的「\\(月)月」——英文界面会显示中文（P3-3）")
    }

    /// 日历必须固定公历：系统区域用伊斯兰历/佛历时，月名不能跟着变
    /// （否则标题写「ربيع الأول」而下面的网格是公历 9 月，两处对不上）。
    func testMonthLabelKeepsGregorianCalendarForNonGregorianLocales() throws {
        let cal = Calendar(identifier: .gregorian)
        let september = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 9, day: 15)))
        let locale = Locale(identifier: "ar_SA")

        let unpinned = DateFormatter()
        unpinned.locale = locale
        unpinned.setLocalizedDateFormatFromTemplate("MMMM")
        guard unpinned.calendar.identifier != .gregorian else {
            throw XCTSkip("本机 \(locale.identifier) 的默认日历就是公历，这条守卫无法区分（环境相关）")
        }

        XCTAssertNotEqual(MonthLabel.name(for: september, locale: locale), unpinned.string(from: september),
                          "MonthLabel 必须把日历固定为公历——不能输出该 locale 默认历法的月名")
    }
}
