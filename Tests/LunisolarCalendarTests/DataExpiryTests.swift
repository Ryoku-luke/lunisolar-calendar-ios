import XCTest
@testable import LunisolarCalendarApp

// MARK: - 数据集到期防线（开发期可见）
//
// 三份内置数据都会**静默降级**：过期后不报错，只是节气倒计时整体消失 /
// 放假安排全变成普通日 / 黄历落到算法兜底。用户看不出异常，我们也收不到信号。
//
// 这道防线刻意放在**测试**而不是运行时横幅：这是开发者要在到期前处理的事，
// 在用户 App 里弹「数据过期」既没用又吓人。
//
// 两档阈值：
//   · 距可信边界 < 30 天（或已越过）→ **测试失败**：必须现在补数据
//   · 距可信边界 < 120 天           → 打印醒目告警，不失败（留出准备时间）
//
// 30 天的依据：放假安排每年约 11 月底公布，2027-01-01 往前 30 天是 2026-12-02——
// 那时数据已经拿得到，所以失败是**可行动**的，而不是提前两个月制造噪音。
//
// 补数据流程见 `docs/DATA_UPDATE_RUNBOOK.md`。

/// 到期后的性质：决定它该判失败还是只告警
private enum ExpirySeverity {
    /// 过期后**用户可见地出错**（节气消失 / 放假安排变普通日）
    case correctness
    /// 过期后只是退化（质量不变，例如黄历落到同一算法的兜底）
    case degradation
}

private struct DatasetWindow {
    let name: String
    /// 最后一个「答案仍然可信」的日子；nil = 读不到边界（本身就是故障）
    let trustedThrough: Date?
    let severity: ExpirySeverity
    /// 到期表现 + 去哪儿补
    let remedy: String
}

final class DataExpiryTests: XCTestCase {

    private static let hardFailDays = 30
    private static let warnDays = 120

    private let cal = Calendar(identifier: .gregorian)
    private let utc = TimeZone(identifier: "UTC")!

    private func day(_ key: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = utc
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: key)
    }

    private func text(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = utc
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    // MARK: - 各数据集的「可信边界」

    /// 放假安排的可信边界 = **下一个缺失年份的 1 月 1 日**（当前是 2027-01-01）。
    ///
    /// 为什么不直接用数据末日（2026-10-10）：那个日期之后的 11–12 月在中国本就没有
    /// 法定节假日，`.normal` 是**正确答案**，不是降级。真正的悬崖是新一年的元旦——
    /// 这也正是审查报告列的到期日。
    ///
    /// 这条推导依赖「11–12 月没有节假日条目」，由
    /// `testNovemberAndDecemberHaveNoHolidayEntries` 直接验证（而不是靠人记得）。
    private func holidayTrustedThrough() -> (end: Date?, missingYear: Int) {
        guard let lastDay = day(HolidayProvider.dataCoverage.end) else { return (nil, 0) }
        let lastYear = cal.component(.year, from: lastDay)
        let missingYear = lastYear + 1
        return (day(String(format: "%04d-01-01", missingYear)), missingYear)
    }

    private func windows() -> [DatasetWindow] {
        let solar = SolarTermProvider.dataCoverage
        let holiday = holidayTrustedThrough()
        let huangli = HuangliDBProvider.dataCoverage.flatMap { day($0.end) }

        return [
            DatasetWindow(
                name: "节气表（SolarTermProvider）",
                trustedThrough: solar?.end,
                severity: .correctness,
                remedy: "过期后 nextTerm 返回 nil、节气倒计时整体消失。按 DATA_UPDATE_RUNBOOK 补表"),
            DatasetWindow(
                name: "放假安排（HolidayProvider）",
                trustedThrough: holiday.end,
                severity: .correctness,
                remedy: """
                过期后所有日期返回 .normal（放假与调休全部消失）。按《国务院办公厅关于 \
                \(holiday.missingYear) 年部分节假日安排的通知》补 holidayData，\
                并同步 HolidayProviderTests 的覆盖断言（2027 那条已是自更新写法）
                """),
            DatasetWindow(
                name: "黄历离散库（HuangliDBProvider）",
                trustedThrough: huangli,
                severity: .degradation,
                remedy: "过期后落到 HuangliGenerator 算法兜底（同一算法，质量不变）→ 只告警；用 Tools/gen_huangli_db 重新生成"),
        ]
    }

    // MARK: - 到期检查

    func testDatasetsDoNotExpireSilently() {
        let now = Date()
        var warnings: [String] = []
        var failures: [String] = []

        for window in windows() {
            guard let end = window.trustedThrough else {
                failures.append("【\(window.name)】读不到覆盖范围（边界访问器返回 nil）——数据或加载已坏。\(window.remedy)")
                continue
            }
            let days = cal.dateComponents([.day], from: now, to: end).day ?? 0
            let line = "【\(window.name)】可信至 \(text(end))，还剩 \(days) 天。\(window.remedy)"

            if days < Self.hardFailDays, window.severity == .correctness {
                failures.append(line)
            } else if days < Self.warnDays {
                warnings.append(line)
            }
        }

        for warning in warnings {
            print("⚠️ 数据到期预警 —— \(warning)")
        }

        XCTAssertTrue(failures.isEmpty, """
        内置数据即将到期（或已过期），且到期后是**静默**降级：用户看不到报错，只会发现功能不对。
        """ + "\n" + failures.joined(separator: "\n") + "\n\n补数据流程：docs/DATA_UPDATE_RUNBOOK.md")
    }

    // MARK: - 边界与推导自身的守卫

    /// 三个数据集都该能报出自己的覆盖范围。
    /// 没有这条，上面那条会因为「读不到边界」而报一个看不出原因的失败。
    func testAllDatasetsReportTheirCoverage() {
        XCTAssertNotNil(SolarTermProvider.dataCoverage, "节气表应能报出覆盖范围")
        XCTAssertNotNil(HuangliDBProvider.dataCoverage, "黄历离散库应能报出覆盖范围")
        XCTAssertFalse(HolidayProvider.dataCoverage.start.isEmpty, "放假安排应能报出覆盖范围")
        XCTAssertLessThan(HolidayProvider.dataCoverage.start, HolidayProvider.dataCoverage.end)
        if let solar = SolarTermProvider.dataCoverage {
            XCTAssertLessThan(solar.start, solar.end, "节气表首末条应有序")
        }
    }

    /// 直接验证 `holidayTrustedThrough()` 的推导依据：数据末日所在年份的 11–12 月
    /// 必须**没有任何**节假日/调休记录。哪天数据里出现了，这条先红，
    /// 提醒把 holidayEnd 从「次年 1/1」改回「数据末日」。
    func testNovemberAndDecemberHaveNoHolidayEntries() throws {
        let lastDay = try XCTUnwrap(day(HolidayProvider.dataCoverage.end),
                                    "放假数据的末日 key 解析失败：\(HolidayProvider.dataCoverage.end)")
        let year = cal.component(.year, from: lastDay)

        var dc = DateComponents()
        dc.year = year; dc.month = 11; dc.day = 1
        dc.timeZone = utc
        let nov1 = try XCTUnwrap(cal.date(from: dc))

        for offset in 0..<61 {   // 11/1 ~ 12/31
            let d = try XCTUnwrap(cal.date(byAdding: .day, value: offset, to: nov1))
            XCTAssertEqual(HolidayProvider.info(for: d).type, .normal,
                           "\(text(d)) 有节假日/调休记录 → DataExpiryTests 的 holidayEnd 推导需改成「数据末日」")
        }
    }
}
