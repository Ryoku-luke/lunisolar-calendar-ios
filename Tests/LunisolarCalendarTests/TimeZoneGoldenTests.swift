import XCTest
import LunarCore
@testable import LunisolarCalendarApp

// MARK: - 跨时区 Golden Tests（文档 #7 时区统一 / #38 时区用例）

/// 三类日期口径（docs #7）必须互不串味：
/// - 历法数据（节气 / 黄历 / 干支）以 Asia/Shanghai 为锚，设备时区不得改变其判定；
/// - 节气时刻是"绝对时刻"，不同时区只是墙上时间读数不同；
/// - 用户数据（黄历按用户点选的那一天）以设备本地日历日为准。
///
/// 通过 NSTimeZone.default 覆写模拟海外设备（影响 Calendar(identifier:) 与未显式设 tz 的
/// DateFormatter），逐条锁定上述语义——任何实现回退都会在此暴露。
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

    // MARK: - 1. 干支年边界（立春 = Asia/Shanghai 绝对时刻）

    /// 2026 立春 = 02-04 04:02 Asia/Shanghai：
    /// 03:59 属乙巳（2025 年柱）、04:03 属丙午（2026 年柱）——四种设备时区下结论必须一致。
    func testGanZhiYearBoundaryIsDeviceTimeZoneIndependent() {
        let before = instant(2026, 2, 4, 3, 59, tz: "Asia/Shanghai")
        let after = instant(2026, 2, 4, 4, 3, tz: "Asia/Shanghai")

        for deviceTZ in deviceTimeZones {
            withDeviceTimeZone(deviceTZ) {
                XCTAssertEqual(YearBoundaryProvider.effectiveGanZhiYear(for: before), 2025,
                               "设备时区 \(deviceTZ)：立春前应为 2025 年柱")
                XCTAssertEqual(YearBoundaryProvider.effectiveGanZhiYear(for: after), 2026,
                               "设备时区 \(deviceTZ)：立春后应为 2026 年柱")
                XCTAssertEqual(YearBoundaryProvider.ganZhiString(for: before), "乙巳",
                               "设备时区 \(deviceTZ)：立春前应为乙巳")
                XCTAssertEqual(YearBoundaryProvider.ganZhiString(for: after), "丙午",
                               "设备时区 \(deviceTZ)：立春后应为丙午")
            }
        }
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
                               "设备时区 \(deviceTZ)：立春当天应识别为立春（按上海日界）")
            }
        }
    }

    /// 上海日界附近的绝对时刻：上海 23:30 已是"当天"，纽约仍是前一日 10:30 —— termOn 按上海判定
    func testSolarTermDayBoundaryUsesShanghaiCalendar() {
        // 2026-02-04 立春当天，上海 23:30（= 同日 15:30 UTC）
        let shLateNight = instant(2026, 2, 4, 23, 30, tz: "Asia/Shanghai")
        XCTAssertEqual(SolarTermProvider.termOn(shLateNight), "立春",
                       "上海口径下 02-04 全天都是立春日")

        // 上海 02-03 23:30（立春前 4.5 小时）
        let shBefore = instant(2026, 2, 3, 23, 30, tz: "Asia/Shanghai")
        XCTAssertNil(SolarTermProvider.termOn(shBefore),
                     "02-03 不是立春日，不应误判")
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
