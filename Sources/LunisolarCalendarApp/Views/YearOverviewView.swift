#if canImport(SwiftUI)
import SwiftUI
import LunarCore

// MARK: - 年视图
/// 全年总览：12 个月迷你网格，标注 今日 / 事件 / 节气 / 节日。
/// 点击任意月份 → 回调选中该月（保持原日分量，超出该月天数则取月末），关闭视图回到月视图。
struct YearOverviewView: View {
    @Binding var targetDate: Date
    /// 选中月份后的回调（调用方负责关闭本视图及上级弹窗）
    let onSelect: (Date) -> Void
    @Environment(\.dismiss) private var dismiss

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
        var firstWeekday: Int = 1   // Calendar.firstWeekday 语义：1=周日…7=周六
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
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(String(format: NSLocalizedString("%d 年总览", comment: ""), year))
            .navigationBarTitleDisplayMode(.inline)
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
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(0..<7, id: \.self) { i in
                    let idx = (i + m.firstWeekday - 1) % 7
                    Text(shortWeekday(idx))
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
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
        )
    }

    /// 网格格数：前导空格 + 当月天数，向上取整到整行（≥5 行）
    private func cellsCount(_ m: MonthMarks) -> Int {
        let lead = (m.firstWeekday - 1) % 7
        let total = lead + m.dayCount
        return ((total + 6) / 7) * 7
    }

    private func miniDayCell(index: Int, marks m: MonthMarks, month: Int) -> some View {
        let lead = (m.firstWeekday - 1) % 7
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

    private func shortWeekday(_ index: Int) -> String {
        // index: 0=firstWeekday … 6
        let f = Self.dateFormatter
        f.dateFormat = "EEEEE"
        var dc = DateComponents()
        dc.year = 2026; dc.month = 1; dc.day = 4 + index  // 2026-01-04 是周日
        guard let d = cal.date(from: dc) else { return "" }
        return f.string(from: d)
    }
}
#endif
