#if canImport(SwiftUI)
import SwiftUI
import LunarCore

/// 日期跳转 Sheet：快速跳转到任意日期。
struct DateJumpView: View {
    @Binding var targetDate: Date
    @Environment(\.dismiss) private var dismiss

    @State private var year: Int
    @State private var month: Int
    @State private var day: Int

    // P2 修复：快捷跳转越界或手动拼日期落入 1900/2100 之外时，
    // 不 dismiss 静默 apply 假数据（否则 lunarDate(from:) 返回
    // Gregorian 镜像——用户看得到假『农历几月几日』在界面误导），
    // 应该给出错误提示、留在跳转页让用户重新选。
    // 提示形态由模态 alert 改为行内文案（UI_DESIGN_REVIEW P0-3）：它不是「不可逆二次确认」，
    // 而 alert 里那个「回到今天」本页「快捷跳转」区就有一个（下方 Button），删弹窗不损失任何能力。
    @State private var rangeHint: String?
    /// 年视图入口：全年总览，点击月份直接跳转
    @State private var showYearOverview = false

    private let today = Date()
    private let cal = Calendar(identifier: .gregorian)

    init(targetDate: Binding<Date>) {
        _targetDate = targetDate
        let c = Calendar(identifier: .gregorian)
        let comps = c.dateComponents([.year, .month, .day], from: targetDate.wrappedValue)
        _year = State(initialValue: comps.year ?? 2026)
        _month = State(initialValue: comps.month ?? 1)
        _day = State(initialValue: comps.day ?? 1)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("选择日期") {
                    Picker("年", selection: $year) {
                        ForEach(ChineseCalendar.minYear...ChineseCalendar.maxYear, id: \.self) {
                            Text(String(format: NSLocalizedString("%d 年", comment: ""), $0)).tag($0)
                        }
                    }
                    Picker("月", selection: $month) {
                        ForEach(1...12, id: \.self) {
                            Text(String(format: NSLocalizedString("%d 月", comment: ""), $0)).tag($0)
                        }
                    }
                    Picker("日", selection: $day) {
                        ForEach(1...maxDaysInMonth, id: \.self) {
                            Text(String(format: NSLocalizedString("%d 日", comment: ""), $0)).tag($0)
                        }
                    }
                    .onChange(of: month, initial: false) { _, _ in
                        if day > maxDaysInMonth { day = maxDaysInMonth }
                    }
                    .onChange(of: year, initial: false) { _, _ in
                        if day > maxDaysInMonth { day = maxDaysInMonth }
                    }
                }

                // 越界提示：行内文案，不再用模态 alert（理由见本文件顶部的注释）
                if let rangeHint {
                    Section {
                        Label(rangeHint, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.systemOrange)
                            .accessibilityIdentifier(AccessibilityID.stateError)
                    }
                }

                Section {
                    Label(String(format: NSLocalizedString("支持范围：%d 年 1 月 1 日 — %d 年 12 月 31 日", comment: ""), ChineseCalendar.minYear, ChineseCalendar.maxYear),
                          systemImage: "calendar.badge.clock")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                }

                Section("快捷跳转") {
                    Button { jumpTo(today) } label: { Label("回到今天", systemImage: "sparkles") }
                    Button { jumpTo(today.addingMonths(1)) } label: { Label("下个月", systemImage: "arrow.right") }
                    Button { jumpTo(today.addingMonths(-1)) } label: { Label("上个月", systemImage: "arrow.left") }
                    Button { jumpTo(today.addingMonths(6)) } label: { Label("半年后", systemImage: "arrow.forward") }
                    Button { jumpTo(today.addingYears(1)) } label: { Label("一年后", systemImage: "calendar.badge.plus") }
                    Button { showYearOverview = true } label: { Label("全年视图", systemImage: "square.grid.3x3.fill") }
                }
            }
            .navigationTitle("跳转到日期")
            .inlineTitleBar()
            .toolbar {
                ToolbarItem(placement: .platformTopBarTrailing) {
                    Button("跳转") { jumpToDate() }
                        .font(.body.weight(.semibold))
                }
                ToolbarItem(placement: .platformTopBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        // N-7：全年视图不再用 sheet（会与 DateJumpView 自身的 sheet 叠成
        // 「sheet 叠 sheet」——iPad 上两级模态堆叠观感差、交互绕）。
        // 改用 popover：iPad 上是悬浮窗（不叠模态），iPhone/紧凑宽度下
        // 系统自动退化为全屏 sheet，两种设备行为都自然。
        .popover(isPresented: $showYearOverview, arrowEdge: .top) {
            YearOverviewView(targetDate: $targetDate) { date in
                targetDate = date
                showYearOverview = false
                dismiss()
            }
        }
    }

    // MARK: - 逻辑

    private var maxDaysInMonth: Int {
        var dc = DateComponents()
        dc.year = year; dc.month = month
        guard let date = cal.date(from: dc) else { return 31 }
        return cal.range(of: .day, in: .month, for: date)?.count ?? 31
    }

    /// 越界提示文案（复用既有本地化键，四语言都在）
    private var outOfRangeText: String {
        String(format: NSLocalizedString("清和日历支持的日期范围为 %d 年 1 月至 %d 年 12 月。", comment: ""),
               ChineseCalendar.minYear, ChineseCalendar.maxYear)
    }

    private func jumpToDate() {
        var dc = DateComponents()
        dc.year = year; dc.month = month; dc.day = day
        guard let date = cal.date(from: dc) else {
            rangeHint = outOfRangeText
            return
        }
        // 范围校验：不支持的日期 → 留在本页行内提示，不 apply 假数据
        guard ChineseCalendar.isSupported(date) else {
            rangeHint = outOfRangeText
            return
        }
        targetDate = date
        dismiss()
    }

    private func jumpTo(_ date: Date) {
        // 快捷跳转同样做范围校验（1900-01 点 上个月→1899，2100 点 一年后→2101
        //   都会越过 LunarDate 的数据边界）。
        guard ChineseCalendar.isSupported(date) else {
            rangeHint = outOfRangeText
            return
        }
        targetDate = date
        dismiss()
    }
}

// MARK: - Date 扩展（年加减）

private extension Date {
    func addingYears(_ years: Int) -> Date {
        Calendar(identifier: .gregorian).date(byAdding: .year, value: years, to: self) ?? self
    }
}
#endif
