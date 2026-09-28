import XCTest
import LunarCore
@testable import LunisolarCalendarApp

// MARK: - 跨时区 Golden Tests（文档 #7 时区统一 / #38 时区用例）

/// 两类日期口径（docs #7）必须互不串味：
/// - **「哪一天」一律按设备本地日历日**（`Calendar(identifier: .gregorian)`）。这是刻意的口径，
///   不是遗漏：`HuangliDBProvider.dayKey` 曾用 Asia/Shanghai 去格式化"设备本地午夜"这一时刻，
///   结果 UTC+13 设备把本地 02-04 映射成 02-03、取到前一天的宜忌（见该函数注释），
///   现已统一为"取日历分量"；
/// - 节气**时刻**是"绝对时刻"，不同时区只是墙上读数不同；但某一节气**算哪一天**同样按
///   设备本地日归属（上海 04:02 交节算 02-04，纽约当地 15:02 交节算 02-03，各自都对）。
///
/// ⚠️ 推论：同一个绝对时刻在不同时区设备上属于不同的"日"，答案本就允许不同。因此用例必须
/// **按各时区各自的本地日**构造时刻，不能拿一个"上海构造的时刻"去断言所有时区。
/// 这里踩过坑：原先两条用例按"上海锚"写，靠本机时区恰好是 Asia/Shanghai 才通过，
/// CI（runner 时区为 UTC）与任何非上海时区都会失败——日期边界的测试必须跨时区自证。
///
/// 通过 NSTimeZone.default 覆写模拟海外设备（影响 `Calendar(identifier:)` 与未显式设 tz 的
/// DateFormatter），逐条锁定上述语义——任何实现回退都会在此暴露。
///
/// ⚠️ 例外：`Calendar.gregorian`（农历换算用的那一份）是**进程启动时冻结的 `static let`**，
/// 覆写对它无效；农历/干支的跨时区验证只能换时区跑整个测试进程（CI 按 4 个时区各跑一遍）。
final class TimeZoneGoldenTests: XCTestCase {

    // MARK: - 工具

    /// 在指定"设备时区"下执行（NSTimeZone.default 覆写，defer 恢复，避免污染其他用例）
    private func withDeviceTimeZone<T>(_ identifier: String, _ body: () throws -> T) rethrows -> T {
        let saved = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: identifier)!
        defer { NSTimeZone.default = saved }
        return try body()
    }

    /// 构造"某时区墙上时间"对应的绝对时刻
    private func instant(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int, tz: String) -> Date {
        var dc = DateComponents()
        dc.year = y; dc.month = m; dc.day = d; dc.hour = h; dc.minute = min
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: tz)!
        return cal.date(from: dc)!
    }

    private func components(_ date: Date, tz: String) -> [Int] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: tz)!
        let c = cal.dateComponents([.month, .day, .hour, .minute], from: date)
        return [c.month!, c.day!, c.hour!, c.minute!]
    }

    /// 设备时区列表：本土 / UTC / 美洲 / 大洋洲（含 UTC+13，跨日界最容易暴露问题）
    private let deviceTimeZones = ["Asia/Shanghai", "UTC", "America/New_York", "Pacific/Auckland"]

    // MARK: - 1. 干支年以**春节**为界
    //
    // 口径说明：本 App 有意采用「春节换年」（与大众生肖 / 年命习惯一致，见 Huangli.swift 注释）。
    // 原先此处还锁过一套「立春换年柱」的精确实现（YearBoundaryProvider），但它从未接入生产；
    // 2026-09 按决策删除该未启用实现，本用例改为锁定**真正生效**的那条口径。
    //
    // ⚠️ 这里**不能**按"设备时区"遍历断言：农历换算走 `Calendar.gregorian`，而它是进程启动时
    // 就定死时区的 `static let`（性能考虑，见 LunarDate.swift 的注释），`withDeviceTimeZone`
    // 覆写 NSTimeZone.default 对它无效——遍历只会得到同一个答案，看着像通过其实没验到时区维度。
    // 要让农历层在别的时区下被验，只能**换时区跑整个测试进程**（CI 按 4 个时区各跑一遍；
    // 本机可 `TZ=America/New_York swift test`）。所以本用例改为用同一份公历构造墙上时刻，
    // 断言"春节换年"这条规则本身在任何时区下都成立。
    func testGanZhiYearIsSpringFestivalBased() {
        // 用实现内部的那一份公历构造"本地墙上时刻"，结果与跑测试的机器处于哪个时区无关
        let cal = Calendar.gregorian
        func wall(_ y: Int, _ m: Int, _ d: Int) -> Date {
            cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
        }

        // 2026 春节 = 02-17（农历丙午年正月初一）：前一天属乙巳（2025 年柱），当天起属丙午
        let beforeSpringFestival = wall(2026, 2, 16)
        let onSpringFestival = wall(2026, 2, 17)

        let a = ChineseCalendar.lunarDateSafe(from: beforeSpringFestival)
        let b = ChineseCalendar.lunarDateSafe(from: onSpringFestival)
        XCTAssertNotNil(a, "农历转换不应失败")
        XCTAssertNotNil(b)
        XCTAssertEqual(a?.year, 2025, "春节前一天应属农历 2025 年")
        XCTAssertEqual(b?.year, 2026, "春节当天起应属农历 2026 年")
        XCTAssertEqual(a.map { ChineseCalendar.ganZhiOfYear($0.year) }, "乙巳",
                       "春节前一天应为乙巳年柱")
        XCTAssertEqual(b.map { ChineseCalendar.ganZhiOfYear($0.year) }, "丙午",
                       "春节当天起应为丙午年柱")
    }

    // MARK: - 2. 节气：同一绝对时刻，各时区读数不同

    func testSolarTermIsAbsoluteInstantRenderedPerTimeZone() {
        guard let lichun = SolarTermProvider.termDate(year: 2026, index: 2) else {
            XCTFail("缺 2026 立春数据")
            return
        }
        XCTAssertEqual(components(lichun, tz: "Asia/Shanghai"), [2, 4, 4, 2], "上海应为 02-04 04:02")
        XCTAssertEqual(components(lichun, tz: "America/New_York"), [2, 3, 15, 2], "纽约应为 02-03 15:02")
        XCTAssertEqual(components(lichun, tz: "UTC"), [2, 3, 20, 2], "UTC 应为 02-03 20:02")

        for deviceTZ in deviceTimeZones {
            withDeviceTimeZone(deviceTZ) {
                XCTAssertEqual(SolarTermProvider.termDate(year: 2026, index: 2), lichun,
                               "设备时区 \(deviceTZ) 不应改变节气绝对时刻")
                XCTAssertEqual(SolarTermProvider.termOn(lichun), "立春",
                               "设备时区 \(deviceTZ)：交节时刻所在的那一天应识别为立春")
            }
        }
    }

    /// 节气归属哪一天按**设备本地日历日**判定：交节时刻落在哪个本地日，那天全天都算节气日，
    /// 前一天不算。
    ///
    /// 2026 立春交节 = 2026-02-04 04:02 Asia/Shanghai = 2026-02-03 20:02 UTC
    /// —— 同一个绝对时刻，上海算 02-04、纽约算 02-03（当地 15:02），各自都对。
    func testSolarTermDayBoundaryFollowsDeviceLocalDay() {
        guard let lichun = SolarTermProvider.termDate(year: 2026, index: 2) else {
            XCTFail("缺 2026 立春数据")
            return
        }
        for deviceTZ in deviceTimeZones {
            withDeviceTimeZone(deviceTZ) {
                // 注意：日历要在时区覆写之内创建，才会用覆写后的 NSTimeZone.default
                let cal = Calendar(identifier: .gregorian)
                let termDay = cal.startOfDay(for: lichun)
                let nextDay = cal.date(byAdding: .day, value: 1, to: termDay)!
                let prevDay = cal.date(byAdding: .day, value: -1, to: termDay)!

                XCTAssertEqual(SolarTermProvider.termOn(termDay), "立春",
                               "设备时区 \(deviceTZ)：交节时刻所在的本地日整天都算立春日")
                XCTAssertEqual(SolarTermProvider.termOn(nextDay.addingTimeInterval(-1)), "立春",
                               "设备时区 \(deviceTZ)：该本地日的最后一刻仍算立春日")
                XCTAssertNil(SolarTermProvider.termOn(prevDay),
                             "设备时区 \(deviceTZ)：前一本地日不应被判为立春")
            }
        }
    }

    // MARK: - 3. 黄历：按"用户点选的那一日"取数，设备时区不得改变结果

    /// 同一"本地日历日 2026-02-04"，在四种设备时区下应取到同一份黄历（同在离散库覆盖内）。
    func testHuangliForSameLocalDayIsDeviceTimeZoneIndependent() {
        // 各时区"本地 2026-02-04 10:00"对应的绝对时刻不同，但都是本地的 2026-02-04
        let byTZ: [String: (() -> Date)] = [
            "Asia/Shanghai": { self.instant(2026, 2, 4, 10, 0, tz: "Asia/Shanghai") },
            "UTC": { self.instant(2026, 2, 4, 10, 0, tz: "UTC") },
            "America/New_York": { self.instant(2026, 2, 4, 10, 0, tz: "America/New_York") },
            "Pacific/Auckland": { self.instant(2026, 2, 4, 10, 0, tz: "Pacific/Auckland") }
        ]

        var baselineYi: [String]?
        var baselineJi: [String]?
        var baselineTZ = ""
        for deviceTZ in deviceTimeZones {
            let resolved = withDeviceTimeZone(deviceTZ) {
                HuangliDBProvider.resolve(date: byTZ[deviceTZ]!())
            }
            XCTAssertEqual(resolved.source, .discreteDB,
                           "设备时区 \(deviceTZ)：2026-02-04 在离散库覆盖内，应命中 DB")
            guard let day = resolved.huangliDay else {
                XCTFail("设备时区 \(deviceTZ)：黄历不应为 nil")
                continue
            }

            if let baselineYi, let baselineJi {
                XCTAssertEqual(day.yi, baselineYi, "设备时区 \(deviceTZ) 与 \(baselineTZ) 的本地同一天宜项应一致")
                XCTAssertEqual(day.ji, baselineJi, "设备时区 \(deviceTZ) 与 \(baselineTZ) 的本地同一天忌项应一致")
            } else {
                baselineYi = day.yi
                baselineJi = day.ji
                baselineTZ = deviceTZ
            }
        }
        XCTAssertNotNil(baselineYi, "至少应得到一个基准结果")
    }

    /// 相邻本地日必须取到不同黄历（防止"跨时区错位一天"被掩盖）。
    /// 注：本离散库的"宜"按天干粗粒度循环（1827 天仅 9 种组合），相邻日可能完全相同，
    /// 因此这里比较"忌"（逐日变化）——错位一天必然导致忌项变化。
    func testHuangliForAdjacentLocalDaysDiffers() {
        for deviceTZ in deviceTimeZones {
            withDeviceTimeZone(deviceTZ) {
                let day4 = HuangliDBProvider.resolve(date: instant(2026, 2, 4, 10, 0, tz: deviceTZ)).huangliDay
                let day5 = HuangliDBProvider.resolve(date: instant(2026, 2, 5, 10, 0, tz: deviceTZ)).huangliDay
                XCTAssertNotNil(day4); XCTAssertNotNil(day5)
                XCTAssertNotEqual(day4?.ji, day5?.ji,
                                  "设备时区 \(deviceTZ)：相邻两日忌项不应相同（疑似整日错位）")
            }
        }
    }

    /// 离散库覆盖边界（2024-01-01）在海外设备时区下同样应命中 DB，而非静默退化到算法
    func testDiscreteDBRangeEdgesAreDeviceTimeZoneIndependent() {
        for deviceTZ in deviceTimeZones {
            withDeviceTimeZone(deviceTZ) {
                let firstDay = HuangliDBProvider.resolve(date: instant(2024, 1, 1, 12, 0, tz: deviceTZ))
                XCTAssertEqual(firstDay.source, .discreteDB,
                               "设备时区 \(deviceTZ)：2024-01-01 在覆盖区间内，应命中 DB")
            }
        }
    }
}
