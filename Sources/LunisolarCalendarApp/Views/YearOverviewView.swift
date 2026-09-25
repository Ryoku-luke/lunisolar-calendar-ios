#if canImport(SwiftUI)
import SwiftUI
import LunarCore

// MARK: - 迷你月卡网格几何（纯函数，便于单测）

/// 年视图 12 张迷你月卡共用的网格算术。
///
/// 背景：这里曾经**表头与日期格各算各的**——表头按「该月 1 日的星期」旋转整行，
/// 日期格却固定从周日起始，两者错开一整段，于是 10 月 1 日（周四）会落在
/// 写着「一」的那一列下面。现在表头列位与前导空格都由这里算出，口径唯一。
enum MiniMonthGrid {

    /// 列 i（0…6）对应的星期：1=周日 … 7=周六
    static func weekday(atColumn i: Int, weekStart: Int) -> Int {
        (((i + weekStart - 1) % 7) + 7) % 7 + 1
    }

    /// 当月 1 日之前要空出的格数
    /// - Parameters:
    ///   - firstDayWeekday: 该月 1 日的星期（1=周日 … 7=周六）
    ///   - weekStart: 每周起始日（1=周日 / 2=周一），与月视图同一设置
    static func leadingBlanks(firstDayWeekday: Int, weekStart: Int) -> Int {
        (((firstDayWeekday - weekStart) % 7) + 7) % 7
    }

    /// 总格数：前导空格 + 当月天数，向上取整到整行，**至少 5 行**
    /// （保证 12 张月卡等高，避免 2 月这类恰好 4 行的卡片比邻居矮一截）
    static func cellCount(firstDayWeekday: Int, dayCount: Int, weekStart: Int) -> Int {
        let total = leadingBlanks(firstDayWeekday: firstDayWeekday, weekStart: weekStart) + dayCount
        return max(((total + 6) / 7) * 7, 35)
    }
}

// MARK: - 年视图
/// 全年总览：12 个月迷你网格，标注 今日 / 事件 / 节气 / 节日。
/// 点击任意月份 → 回调选中该月（保持原日分量，超出该月天数则取月末），关闭视图回到月视图。
struct YearOverviewView: View {
    @Binding var targetDate: Date
    /// 选中月份后的回调（调用方负责关闭本视图及上级弹窗）
    let onSelect: (Date) -> Void
    @Environment(\.dismiss) private var dismiss

    /// 每周起始日，与月视图 / 设置页共用同一键（1=周日 / 2=周一）
    @AppStorage("Lunisolar.weekStart") private var weekStart: Int = 1

    private let year: Int
    private let cal = Calendar(identifier: .gregorian)

    // 一次性构建全年标注数据
    @State private var marks: [Int: MonthMarks] = [:]
    @State private var built = false

    struct MonthMarks {
        var todayDay: Int?
        var eventDays: Set<Int> = []
        var termDays: [Int: String] = [:]
        var festivalDays: [Int: String] = [:]
        /// 当月 **1 日** 的星期：1=周日 … 7=周六。
        /// ⚠️ 不是 `Calendar.firstWeekday`（那个是"每周从周几开始"的偏好设置，
        /// 由 `weekStart` 承载）；两者混用正是本视图表头错位的根因。
        var firstWeekday: Int = 1
        var dayCount: Int = 31
    }

    init(targetDate: Binding<Date>, onSelect: @escaping (Date) -> Void) {
        _targetDate = targetDate
        self.onSelect = onSelect
        self.year = Calendar(identifier: .gregorian).component(.year, from: targetDate.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                    ForEach(1...12, id: \.self) { month in
                        miniMonthCard(month)
                            .contentShape(Rectangle())
                            .onTapGesture { selectMonth(month) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(Color.systemGroupedBackground)
            .navigationTitle(String(format: NSLocalizedString("%d 年总览", comment: ""), year))
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("完成", comment: "")) { dismiss() }
                        .font(.body.weight(.semibold))
                }
            }
            .onAppear {
                if !built { buildMarks() }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - 月卡

    private func miniMonthCard(_ month: Int) -> some View {
        let m = marks[month] ?? MonthMarks()
        return VStack(spacing: 5) {
            Text(monthName(month))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 2)

            // 星期头（跟随系统本地化 + 周起始日）
            // 列位必须与下方日期格用同一个起始日才算数：此前这里按月首日的星期旋转整行，
            // 而日期格固定从周日起始，两者错开一整段 → 每个日期都落在写着别的星期的列下。
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(0..<7, id: \.self) { i in
                    Text(shortWeekday(weekday: MiniMonthGrid.weekday(atColumn: i, weekStart: weekStart)))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(Color.secondary)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 3) {
                ForEach(0..<cellsCount(m), id: \.self) { i in
                    miniDayCell(index: i, marks: m, month: month)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondarySystemGroupedBackground)
                .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
        )
    }

    /// 网格格数：前导空格 + 当月天数，向上取整到整行，至少 5 行（12 张月卡等高）
    private func cellsCount(_ m: MonthMarks) -> Int {
        MiniMonthGrid.cellCount(firstDayWeekday: m.firstWeekday,
                                dayCount: m.dayCount,
                                weekStart: weekStart)
    }

    private func miniDayCell(index: Int, marks m: MonthMarks, month: Int) -> some View {
        let lead = MiniMonthGrid.leadingBlanks(firstDayWeekday: m.firstWeekday, weekStart: weekStart)
        let day = index - lead + 1
        guard day >= 1 && day <= m.dayCount else {
            return AnyView(Color.clear.frame(height: 20))
        }
        let isToday = (day == m.todayDay)
        let festival = m.festivalDays[day]
        let term = m.termDays[day]
        let hasEvent = m.eventDays.contains(day)
        let label: String? = festival ?? term
        let labelColor: Color = (festival != nil) ? Color.red : Color.orange

        return AnyView(
            VStack(spacing: 1) {
                ZStack {
                    if isToday {
                        Circle().fill(Color.accentColor)
                    }
                    Text("\(day)")
                        .font(.system(size: isToday ? 9.5 : 8.5, weight: isToday ? .bold : .regular, design: .rounded))
                        .foregroundStyle(isToday ? Color.white : Color.primary)
                }
                .frame(width: 16, height: 16)
                .frame(maxWidth: .infinity)

                if let label {
                    Text(label)
                        .font(.system(size: 6.5, weight: .medium))
                        .foregroundStyle(labelColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(height: 9)
                } else if hasEvent {
                    Circle().fill(Color.accentColor.opacity(0.85)).frame(width: 3, height: 3)
                } else {
                    Color.clear.frame(height: 9)
                }
            }
            .frame(height: 20)
        )
    }

    // MARK: - 数据构建

    private func buildMarks() {
        var result: [Int: MonthMarks] = [:]
        let today = cal.startOfDay(for: Date())
        let todayComps = cal.dateComponents([.year, .month, .day], from: today)

        for month in 1...12 {
            var m = MonthMarks()
            var dc = DateComponents()
            dc.year = year; dc.month = month; dc.day = 1
            guard let first = cal.date(from: dc) else { continue }
            m.dayCount = cal.range(of: .day, in: .month, for: first)?.count ?? 30
            m.firstWeekday = cal.component(.weekday, from: first)
            if todayComps.year == year && todayComps.month == month {
                m.todayDay = todayComps.day
            }
            for day in 1...m.dayCount {
                dc.day = day
                guard let date = cal.date(from: dc) else { continue }
                if let term = SolarTermProvider.termOn(date) {
                    m.termDays[day] = term
                }
                if let fest = FestivalManager.festivals(on: date).first {
                    m.festivalDays[day] = fest.name
                }
            }
            result[month] = m
        }
        // 事件：一次性取全年所有事件，按日分桶
        let events = EventStore.shared.events.filter { cal.component(.year, from: $0.startDate) == year }
        var eventBuckets: [Int: Set<Int>] = [:]
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyyMMdd"
        for e in events {
            let key = fmt.string(from: e.startDate)
            guard key.count == 8, let month = Int(key.dropFirst(4).prefix(2)), let day = Int(key.suffix(2)) else { continue }
            if eventBuckets[month] == nil { eventBuckets[month] = [] }
            eventBuckets[month]?.insert(day)
        }
        for (month, days) in eventBuckets {
            result[month]?.eventDays = days
        }
        marks = result
        built = true
    }

    // MARK: - 交互

    private func selectMonth(_ month: Int) {
        var dc = DateComponents()
        dc.year = year; dc.month = month
        let day = cal.component(.day, from: targetDate)
        dc.day = min(day, marks[month]?.dayCount ?? 31)
        guard let date = cal.date(from: dc), ChineseCalendar.isSupported(date) else {
            // 范围外（不应发生：年视图只展示受支持年份）——回到今天兜底
            onSelect(Date())
            return
        }
        targetDate = date
        onSelect(date)
    }

    // MARK: - 系统本地化星期 / 月份

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.calendar = Calendar(identifier: .gregorian)
        return f
    }()

    private func monthName(_ month: Int) -> String {
        let f = Self.dateFormatter
        f.dateFormat = "MMMM"
        var dc = DateComponents(); dc.year = year; dc.month = month; dc.day = 1
        guard let d = cal.date(from: dc) else { return "\(month)" }
        return f.string(from: d)
    }

    /// 星期缩写
    /// - Parameter weekday: 1=周日 … 7=周六（与 `MiniMonthGrid.weekday(atColumn:weekStart:)` 同口径；
    ///   旧实现收的是"0=周日"的列序号，与表头旋转逻辑耦合，改名换口径以杜绝再次混用）
    private func shortWeekday(weekday: Int) -> String {
        let f = Self.dateFormatter
        f.dateFormat = "EEEEE"
        var dc = DateComponents()
        dc.year = 2026; dc.month = 1; dc.day = 4 + (weekday - 1)  // 2026-01-04 是周日
        guard let d = cal.date(from: dc) else { return "" }
        return f.string(from: d)
    }
}
#endif
