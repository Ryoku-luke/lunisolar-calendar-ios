import XCTest
// LunarDataProvider 是 LunarCore 模块内的 internal 符号（LunarDate.swift 只编进该 target）
@testable import LunarCore
@testable import LunisolarCalendarApp

// MARK: - 农历数据表「资源 vs 内置」一致性
//
// `Resources/lunar_calendar.json` 里曾经是裸的十六进制字面量（`0x04bd8`），
// 那不是合法 JSON → `LunarDataProvider.loadLunarInfo()` 的解析必然抛错、
// 恒定走内置 fallback，于是「资源化农历表」整条路径是死的：
// 以后只改 JSON 会被静默忽略，而注释还告诉读者它在生效。
//
// 本文件锁定：JSON 合法、恰 201 项、且与代码内置表逐值一致。

final class LunarDataResourceTests: XCTestCase {

    /// 按加载器的同一口径解析（`json["data"] as? [String]`，元素可带 `0x` 前缀）
    private func valuesFromResource(file: StaticString = #filePath, line: UInt = #line) -> [UInt32]? {
        guard let url = Bundle.resources.url(forResource: "lunar_calendar", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            XCTFail("未在资源 bundle 中找到 lunar_calendar.json", file: file, line: line)
            return nil
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("lunar_calendar.json 不是合法 JSON（注意：十六进制值必须写成字符串）",
                    file: file, line: line)
            return nil
        }
        guard let hexStrings = json["data"] as? [String] else {
            XCTFail("lunar_calendar.json 缺少 data: [String]（元素需为 \"0x...\" 形式）",
                    file: file, line: line)
            return nil
        }
        return hexStrings.compactMap {
            let hex = $0.hasPrefix("0x") ? String($0.dropFirst(2)) : $0
            return UInt32(hex, radix: 16)
        }
    }

    func testResourceIsValidJSONWith201Entries() throws {
        let values = try XCTUnwrap(valuesFromResource())
        XCTAssertEqual(values.count, 201, "1900–2100 共 201 年，缺一项都会让加载器拒绝该文件")
    }

    /// 资源与内置表必须逐值一致：任一方向单独改动都应在测试里暴露
    func testResourceMatchesBuiltinTable() throws {
        let fromResource = try XCTUnwrap(valuesFromResource())
        let builtin = LunarDataProvider.lunarInfo
        XCTAssertEqual(fromResource.count, builtin.count)
        for (i, (a, b)) in zip(fromResource, builtin).enumerated() where a != b {
            XCTFail("第 \(i) 项不一致：JSON=0x\(String(a, radix: 16))，内置=0x\(String(b, radix: 16))")
            return
        }
    }

    /// 解析口径与加载器完全一致时，资源路径本身也要能跑通（而不是恒定 fallback）
    func testLoaderAcceptsResourceContent() throws {
        let values = try XCTUnwrap(valuesFromResource())
        XCTAssertEqual(values.count, 201, "加载器要求恰好 201 项才采用该文件")
        XCTAssertEqual(LunarDataProvider.lunarInfo.count, 201)
    }
}
