import XCTest
import LunarCore
@testable import LunisolarCalendarApp

// MARK: - CalendarDaySummary：当日派生数据的单一来源（收口）
//
// 这些断言钉的是**契约**，不是新逻辑：summary 只把既有生成器的结果算一次装起来，
// 所以它的每个字段都必须逐字等于直接调用生成器的结果；而视图依赖的
// `primaryFestival` / `accentHex` 必须继续取 `festivals.first`
// （不是 `FestivalManager.primaryFestival(on:)` 那套「大节日优先」排序），
// 否则选中日卡片 / 详情页的节日配色与主节日会变。

final class CalendarDaySummaryTests: XCTestCase {

    private let cal = Calendar(identifier: .gregorian)

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var dc = DateComponents()
        dc.year = y; dc.month = m; dc.day = d
        return cal.date(from: dc)!
    }

    /// 取样：中秋（农历节日 + 法定假）、春节（农历节日 + 法定假）、清明（交节 + 法定假）、
    /// 普通日、农历越界日
    private var samples: [(label: String, day: Date)] {
        [
            ("2026 中秋", date(2026, 9, 25)),
            ("2026 春节", date(2026, 2, 17)),
            ("2026 清明交节", date(2026, 4, 5)),
            ("2026 普通日", date(2026, 9, 30)),
            ("1899 农历越界日", date(1899, 12, 31)),
        ]
    }

    // MARK: - 1. summary 的每个字段 == 直接调用生成器

    func testSummaryFieldsMatchDirectGeneratorCalls() {
        for (label, day) in samples {
            let summary = CalendarDaySummary(date: day)
            let lunar = day.lunar
            XCTAssertEqual(summary.date, day, "[\(label)] date 应原样保留")
            XCTAssertEqual(summary.lunar, lunar,
                           "[\(label)] lunar 应与 Date.lunar 一致")
            XCTAssertEqual(summary.huangli, HuangliGenerator.generate(for: day),
                           "[\(label)] huangli 应与 HuangliGenerator.generate(for:) 一致")
            XCTAssertEqual(summary.festivals, FestivalManager.festivals(on: day, lunar: lunar),
                           "[\(label)] festivals 应与 FestivalManager.festivals(on:lunar:) 一致")
            XCTAssertEqual(summary.solarTermName, SolarTermProvider.termOn(day),
                           "[\(label)] solarTermName 应与 SolarTermProvider.termOn(_:) 一致")
            XCTAssertEqual(summary.holidayType, HolidayProvider.info(for: day).type,
                           "[\(label)] holidayType 应与 HolidayProvider.info(for:).type 一致")
        }
    }

    /// 取样日期确实覆盖到各分支（否则上面那条断言可能全落在同一个分支上）
    func testSampleDatesCoverEachBranch() throws {
        XCTAssertEqual(CalendarDaySummary(date: date(2026, 9, 25)).holidayType, .holiday)
        XCTAssertEqual(CalendarDaySummary(date: date(2026, 2, 17)).holidayType, .holiday)
        XCTAssertEqual(CalendarDaySummary(date: date(2026, 4, 5)).holidayType, .holiday)
        XCTAssertEqual(CalendarDaySummary(date: date(2026, 9, 30)).holidayType, .normal)
        XCTAssertEqual(CalendarDaySummary(date: date(1899, 12, 31)).holidayType, .normal)

        // Festival.name 是原始中文（本地化走 localizedName），与系统语言无关
        XCTAssertEqual(CalendarDaySummary(date: date(2026, 9, 25)).festivals.map(\.name), ["中秋节"])
        XCTAssertEqual(CalendarDaySummary(date: date(2026, 2, 17)).festivals.map(\.name), ["春节"])
        XCTAssertEqual(CalendarDaySummary(date: date(2026, 9, 30)).festivals, [])

        // 节气：用节气自身的交节时刻构造日期，避开「按设备时区取当天」的漂移
        let termInstant = try XCTUnwrap(SolarTermProvider.termDate(year: 2026, index: 6))
        XCTAssertNotNil(CalendarDaySummary(date: termInstant).solarTermName,
                        "交节时刻当天的 solarTermName 不应为 nil")
        XCTAssertNil(CalendarDaySummary(date: date(2026, 9, 30)).solarTermName)
    }

    // MARK: - 2. 视图依赖的契约：primaryFestival / accentHex 取 festivals.first

    func testPrimaryFestivalAndAccentHexAreFirstFestival() {
        for (label, day) in samples {
            let summary = CalendarDaySummary(date: day)
            XCTAssertEqual(summary.primaryFestival, summary.festivals.first,
                           "[\(label)] primaryFestival 必须等于 festivals.first")
            XCTAssertEqual(summary.accentHex, summary.festivals.first?.accentHex,
                           "[\(label)] accentHex 必须等于 festivals.first?.accentHex")
        }
    }

    /// 2031-10-01 = 国庆节（公历）+ 中秋节（农历）：区间内少见的同日双节日，
    /// 用它钉住 `festivals` 的既有顺序（公历 → 农历 → 节气）与「强调色取首项」——
    /// 这天装饰色必须是国庆红，不是中秋金。
    /// 该日期不受设备时区影响：公历节日按本地年月日命中，农历也由本地年月日推出。
    func testOverlappingFestivalsKeepGeneratorOrder() {
        let summary = CalendarDaySummary(date: date(2031, 10, 1))
        XCTAssertEqual(summary.festivals.map(\.name), ["国庆节", "中秋节"])
        XCTAssertEqual(summary.primaryFestival?.name, "国庆节")
        XCTAssertEqual(summary.accentHex, "#D7282E",
                       "强调色应取自 festivals.first（国庆节），而不是中秋节的金色")
    }

    // MARK: - 3. 农历越界

    func testLunarUnsupportedFlag() {
        let outOfRange = CalendarDaySummary(date: date(1899, 12, 31))
        XCTAssertEqual(outOfRange.lunar, .unsupported)
        XCTAssertTrue(outOfRange.isLunarUnsupported)

        for (label, day) in samples where !label.hasPrefix("1899") {
            XCTAssertFalse(CalendarDaySummary(date: day).isLunarUnsupported,
                           "[\(label)] 区间内日期不应被判为农历越界")
        }
    }

    // MARK: - 4. events 由调用方传入、原样透传（本类型不依赖 store）

    func testEventsArePassedThroughVerbatim() {
        let day = date(2026, 9, 25)
        let sameDay = CalendarEvent(title: "中秋聚餐", startDate: day)
        let anotherDay = CalendarEvent(title: "另一天的事", startDate: date(2026, 9, 30))

        let summary = CalendarDaySummary(date: day, events: [sameDay, anotherDay])
        // 不做按日过滤：过滤是 EventStore 的职责，summary 只负责装
        XCTAssertEqual(summary.events, [sameDay, anotherDay])

        XCTAssertEqual(CalendarDaySummary(date: day).events, [],
                       "events 默认值为空数组")
    }
}
