import Foundation

// MARK: - 时区 / 日历统一上下文

/// 文档 #7：全项目日期口径统一入口。
///
/// 三类口径（互不混用）：
/// - `userCalendar`：用户本地日历（默认设备时区）。用于日程 / 纪念日 /
///   农历显示 / 统计分组等"以用户当地时间为准"的业务。
/// - `chinaCalendar` / `chinaTimeZone`：中国历法日历（Asia/Shanghai）。
///   用于节气 / 黄历 / 立春干支边界等"以中国标准时为锚"的历法数据。
/// - `utcTimeZone`：交换格式时区（RFC 5545 ICS 等），与设备无关。
///
/// 规则：历法数据（节气/黄历/干支）一律走 china 口径；
/// 用户数据（日程/生日/倒计时）一律走 user 口径；两者比较时
/// 必须显式转换到同一口径，禁止隐式混用。
public enum QingheCalendarContext {
    /// 中国历法时区（Asia/Shanghai）
    public static let chinaTimeZone: TimeZone = {
        TimeZone(identifier: "Asia/Shanghai") ?? .current
    }()

    /// 用户本地日历：公历 + 设备时区
    public static var userCalendar: Calendar {
        Calendar(identifier: .gregorian)
    }

    /// 中国历法日历：公历 + Asia/Shanghai
    public static var chinaCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = chinaTimeZone
        return cal
    }

    /// 交换 / 序列化时区（ICS 等）
    public static let utcTimeZone: TimeZone = {
        TimeZone(identifier: "UTC") ?? .current
    }()
}
