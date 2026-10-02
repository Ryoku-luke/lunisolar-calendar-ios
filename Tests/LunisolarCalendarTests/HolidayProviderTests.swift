import XCTest
@testable import LunisolarCalendarApp

// MARK: - 法定节假日 / 调休 Provider 测试
// 断言依据：《国务院办公厅关于2026年部分节假日安排的通知》(国办发明电〔2025〕7号)

final class HolidayProviderTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var dc = DateComponents()
        dc.year = y; dc.month = m; dc.day = d
        return cal.date(from: dc)!
    }

    // MARK: 2026 官方安排锚点

    func test2026NewYear() {
        // 元旦 1/1(周四)-1/3(周六) 放假共3天；1/4(周日) 上班
        for day in 1...3 {
            XCTAssertEqual(HolidayProvider.info(for: date(2026, 1, day)).type, .holiday, "1/\(day) 应为元旦假期")
        }
        XCTAssertEqual(HolidayProvider.info(for: date(2026, 1, 4)).type, .workday, "1/4 应为元旦调休补班")
    }

    func test2026SpringFestival() {
        // 春节 2/15(周日)-2/23(周一) 放假共9天；2/14、2/28 补班；2/24 恢复正常上班
        for day in 15...23 {
            XCTAssertEqual(HolidayProvider.info(for: date(2026, 2, day)).type, .holiday, "2/\(day) 应为春节假期")
        }
        XCTAssertEqual(HolidayProvider.info(for: date(2026, 2, 14)).type, .workday, "2/14 应为春节调休补班")
        XCTAssertEqual(HolidayProvider.info(for: date(2026, 2, 28)).type, .workday, "2/28 应为春节调休补班")
        XCTAssertEqual(HolidayProvider.info(for: date(2026, 2, 24)).type, .normal, "2/24 春节假期已结束，应为普通日")
    }

    func test2026LabourDay() {
        // 劳动节 5/1(周五)-5/5(周二) 放假共5天；5/9(周六) 补班；4/26 不是补班日
        for day in 1...5 {
            XCTAssertEqual(HolidayProvider.info(for: date(2026, 5, day)).type, .holiday, "5/\(day) 应为劳动节假期")
        }
        XCTAssertEqual(HolidayProvider.info(for: date(2026, 5, 9)).type, .workday, "5/9 应为劳动节调休补班")
        XCTAssertEqual(HolidayProvider.info(for: date(2026, 4, 26)).type, .normal, "4/26 官方无调休，应为普通日")
    }

    func test2026MidAutumnAndNationalDay() {
        // 中秋 9/25-9/27 放假共3天；国庆 10/1(周四)-10/7(周三) 放假共7天；
        // 9/20(周日)、10/10(周六) 补班；10/8 恢复正常上班
        for day in 25...27 {
            XCTAssertEqual(HolidayProvider.info(for: date(2026, 9, day)).type, .holiday, "9/\(day) 应为中秋节假期")
        }
        for day in 1...7 {
            XCTAssertEqual(HolidayProvider.info(for: date(2026, 10, day)).type, .holiday, "10/\(day) 应为国庆假期")
        }
        XCTAssertEqual(HolidayProvider.info(for: date(2026, 9, 20)).type, .workday, "9/20 应为国庆调休补班")
        XCTAssertEqual(HolidayProvider.info(for: date(2026, 10, 10)).type, .workday, "10/10 应为国庆调休补班")
        XCTAssertEqual(HolidayProvider.info(for: date(2026, 10, 8)).type, .normal, "10/8 国庆假期已结束，应为普通日")
    }

    // MARK: 覆盖范围

    func testDataCoverageExtendsThrough2026() {
        let c = HolidayProvider.dataCoverage
        XCTAssertEqual(c.start, "2025-01-01", "内置数据应从 2025-01-01 开始")
        XCTAssertEqual(c.end, "2026-10-10", "内置数据必须覆盖到 2026-10-10（最后一个补班日）")
        XCTAssertFalse(HolidayProvider.dataCoverageDescription.isEmpty)
    }

    /// 2027 元旦：**自更新**用例（补 2027 数据的人不需要记得回来改这条测试）。
    ///
    /// 旧版本把「2027-01-01 == .normal」写成永久断言——那等于把「数据悬崖」当成了契约：
    /// 补完 2027 数据那天它必然红，而红的原因不是代码错，是测试没跟上
    /// （见 docs/DATA_UPDATE_RUNBOOK.md）。现在按数据实际覆盖到哪儿来判：
    /// 没覆盖就要求「不许编造、退回普通日」，覆盖了就要求「元旦必须是假期」。
    func test2027NewYearReflectsDataStage() {
        let info = HolidayProvider.info(for: date(2027, 1, 1))
        // key 零填充，字典序即日期序（与 HolidayProvider.dataCoverage 同一套约定）
        if HolidayProvider.dataCoverage.end < "2027-01-01" {
            XCTAssertEqual(info.type, .normal, "2027 安排尚未发布时不得编造数据，应退回普通日")
            XCTAssertEqual(info.name, "")
        } else {
            XCTAssertEqual(info.type, .holiday, "2027 数据已覆盖，元旦应为假期")
            XCTAssertEqual(info.name, "元旦")
        }
    }

    // MARK: 2025 锚点抽查（《国务院办公厅关于2025年部分节假日安排的通知》）

    func test2025Anchors() {
        XCTAssertEqual(HolidayProvider.info(for: date(2025, 10, 1)).type, .holiday, "2025-10-01 国庆假期")
        XCTAssertEqual(HolidayProvider.info(for: date(2025, 9, 28)).type, .workday, "2025-09-28 国庆调休补班")
        XCTAssertEqual(HolidayProvider.info(for: date(2025, 10, 11)).type, .workday, "2025-10-11 国庆调休补班")
        XCTAssertEqual(HolidayProvider.info(for: date(2025, 2, 4)).type, .holiday, "2025-02-04 春节假期最后一天")
    }
}
