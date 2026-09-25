import Foundation

// MARK: - 法定节假日 / 调休日

/// 表示某天的法定属性：放假、补班、或普通。
public enum HolidayType: Sendable, Equatable {
    case holiday       // 法定放假
    case workday       // 调休补班（周末但需上班）
    case normal        // 普通日
}

public struct HolidayInfo: Sendable, Equatable {
    public let type: HolidayType
    public let name: String   // 假期名称（如"春节"），普通日为空
}

/// 法定节假日与调休数据（国务院公布的放假安排）。
/// 数据来源：《国务院办公厅关于2025年部分节假日安排的通知》《国务院办公厅关于2026年部分节假日安排的通知》(国办发明电〔2025〕7号)。
/// 国务院每年发布次年安排（往年约在 11 月底），2027 年安排发布后请按 holidayData 内「── 2027 年 ──」占位补充。
public enum HolidayProvider: Sendable {

    // MARK: - 内置数据

    /// key = "yyyy-MM-dd"，value = (是否放假, 假期名称)
    private static let holidayData: [String: (isOff: Bool, name: String)] = {
        var d: [String: (Bool, String)] = [:]

        // ── 2025 年 ──
        // 元旦
        for day in 1...1 { d["2025-01-\(String(format: "%02d", day))"] = (true, "元旦") }
        d["2025-01-26"] = (false, "春节")  // 调休补班（周日）
        d["2025-02-08"] = (false, "春节")  // 调休补班（周六）
        // 春节
        for day in 28...31 { d["2025-01-\(String(format: "%02d", day))"] = (true, "春节") }
        for day in 1...4  { d["2025-02-\(String(format: "%02d", day))"] = (true, "春节") }
        // 清明
        d["2025-04-04"] = (true, "清明节")
        d["2025-04-05"] = (true, "清明节")
        d["2025-04-06"] = (true, "清明节")
        // 劳动节
        d["2025-04-27"] = (false, "劳动节")  // 调休补班（周日）
        for day in 1...5 { d["2025-05-\(String(format: "%02d", day))"] = (true, "劳动节") }
        // 端午
        d["2025-05-31"] = (true, "端午节")
        d["2025-06-01"] = (true, "端午节")
        d["2025-06-02"] = (true, "端午节")
        // 中秋+国庆
        d["2025-09-28"] = (false, "国庆节")  // 调休补班（周日）
        d["2025-10-11"] = (false, "国庆节")  // 调休补班（周六）
        for day in 1...8 { d["2025-10-\(String(format: "%02d", day))"] = (true, "国庆节") }

        // ── 2026 年 ──（依据《国务院办公厅关于2026年部分节假日安排的通知》国办发明电〔2025〕7号）
        // 元旦：1月1日(周四)至3日(周六)放假共3天，1月4日(周日)上班
        for day in 1...3 { d["2026-01-\(String(format: "%02d", day))"] = (true, "元旦") }
        d["2026-01-04"] = (false, "元旦")  // 调休补班（周日）
        // 春节：2月15日(周日)至23日(周一)放假共9天，2月14日(周六)、2月28日(周六)上班
        d["2026-02-14"] = (false, "春节")  // 调休补班（周六）
        for day in 15...23 { d["2026-02-\(String(format: "%02d", day))"] = (true, "春节") }
        d["2026-02-28"] = (false, "春节")  // 调休补班（周六）
        // 清明：4月4日(周六)至6日(周一)放假共3天
        d["2026-04-04"] = (true, "清明节")
        d["2026-04-05"] = (true, "清明节")
        d["2026-04-06"] = (true, "清明节")
        // 劳动节：5月1日(周五)至5日(周二)放假共5天，5月9日(周六)上班
        for day in 1...5 { d["2026-05-\(String(format: "%02d", day))"] = (true, "劳动节") }
        d["2026-05-09"] = (false, "劳动节")  // 调休补班（周六）
        // 端午：6月19日(周五)至21日(周日)放假共3天
        d["2026-06-19"] = (true, "端午节")
        d["2026-06-20"] = (true, "端午节")
        d["2026-06-21"] = (true, "端午节")
        // 中秋：9月25日(周五)至27日(周日)放假共3天
        d["2026-09-25"] = (true, "中秋节")
        d["2026-09-26"] = (true, "中秋节")
        d["2026-09-27"] = (true, "中秋节")
        // 国庆：10月1日(周四)至7日(周三)放假共7天，9月20日(周日)、10月10日(周六)上班
        d["2026-09-20"] = (false, "国庆节")  // 调休补班（周日）
        for day in 1...7 { d["2026-10-\(String(format: "%02d", day))"] = (true, "国庆节") }
        d["2026-10-10"] = (false, "国庆节")  // 调休补班（周六）

        // ── 2027 年 ──（待国务院办公厅发布 2027 年放假安排后，在此按同样格式补充，并同步更新 dataCoverage 测试）

        return d
    }()

    // MARK: - 数据覆盖范围（用于诊断 / UI 提示 / 测试）

    /// 内置数据最早/最晚日期 key（"yyyy-MM-dd"）。key 按零填充字典序即日期序，min/max 即为覆盖边界。
    public static var dataCoverage: (start: String, end: String) {
        let keys = holidayData.keys
        return (keys.min() ?? "—", keys.max() ?? "—")
    }

    /// 面向用户/文档的覆盖说明。
    public static var dataCoverageDescription: String {
        let c = dataCoverage
        return "节假日数据覆盖 \(c.start) ~ \(c.end)（2027 年安排待国务院发布后补充）"
    }

    // MARK: - 查询

    /// 查询某天的法定属性。
    public static func info(for date: Date) -> HolidayInfo {
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        guard let y = comps.year, let m = comps.month, let d = comps.day else {
            return HolidayInfo(type: .normal, name: "")
        }
        let key = "\(y)-\(String(format: "%02d", m))-\(String(format: "%02d", d))"
        if let entry = holidayData[key] {
            return HolidayInfo(type: entry.isOff ? .holiday : .workday, name: entry.name)
        }
        return HolidayInfo(type: .normal, name: "")
    }

}
