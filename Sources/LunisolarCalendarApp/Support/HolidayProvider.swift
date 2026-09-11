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
/// 数据每年由国务院发布，此处内置 2025–2026 年安排。
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

        // ── 2026 年 ──（基于已公布的 2026 放假安排预估，以国务院公告为准）
        // 元旦
        d["2026-01-01"] = (true, "元旦")
        d["2026-01-02"] = (true, "元旦")
        d["2026-01-03"] = (true, "元旦")
        // 春节 (2026-02-17 = 正月初一)
        d["2026-02-15"] = (false, "春节")  // 调休补班（周日）
        d["2026-02-28"] = (false, "春节")  // 调休补班（周六）
        for day in 16...22 { d["2026-02-\(String(format: "%02d", day))"] = (true, "春节") }
        for day in 23...24 { d["2026-02-\(String(format: "%02d", day))"] = (true, "春节") }
        // 清明
        d["2026-04-04"] = (true, "清明节")
        d["2026-04-05"] = (true, "清明节")
        d["2026-04-06"] = (true, "清明节")
        // 劳动节
        d["2026-04-26"] = (false, "劳动节")  // 调休补班（周日）
        for day in 1...5 { d["2026-05-\(String(format: "%02d", day))"] = (true, "劳动节") }
        // 端午
        d["2026-06-19"] = (true, "端午节")
        d["2026-06-20"] = (true, "端午节")
        d["2026-06-21"] = (true, "端午节")
        // 中秋
        d["2026-09-25"] = (true, "中秋节")
        d["2026-09-26"] = (true, "中秋节")
        d["2026-09-27"] = (true, "中秋国庆") // 双节重叠，合并展示
        // 国庆：先写 8 天放假，再覆盖调休补班（补班优先级更高，避免被放假循环静默覆盖）
        for day in 1...8 { d["2026-10-\(String(format: "%02d", day))"] = (true, "国庆节") }
        // 调休补班（在放假循环之后写入，确保补班不会被覆盖）
        d["2026-10-10"] = (false, "国庆节调休") // 调休补班（周六）
        // 注意：2026 年国庆实际补班安排以国务院公告为准；若 10-04 真为补班日请取消下行注释
        // d["2026-10-04"] = (false, "国庆节调休")

        return d
    }()

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

    /// 是否为法定假日。
    public static func isHoliday(_ date: Date) -> Bool {
        info(for: date).type == .holiday
    }

    /// 是否为调休补班日。
    public static func isWorkday(_ date: Date) -> Bool {
        info(for: date).type == .workday
    }
}
