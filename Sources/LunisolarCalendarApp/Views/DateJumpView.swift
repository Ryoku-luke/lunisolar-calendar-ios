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
    // 应该弹错误提示、留在跳转页让用户重新选或回到今天。
    @State private var showOutOfRangeAlert = false

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
                        ForEach(LunarDate.minYear...LunarDate.maxYear, id: \.self) {
                            Text("\($0) 年").tag($0)
                        }
                    }
                    Picker("月", selection: $month) {
                        ForEach(1...12, id: \.self) { Text("\($0) 月").tag($0) }
                    }
                    Picker("日", selection: $day) {
                        ForEach(1...maxDaysInMonth, id: \.self) { Text("\($0) 日").tag($0) }
                    }
                    .onChange(of: month) { _, _ in
                        if day > maxDaysInMonth { day = maxDaysInMonth }
                    }
                    .onChange(of: year) { _, _ in
                        if day > maxDaysInMonth { day = maxDaysInMonth }
                    }
                }

                Section {
                    Label("支持范围：\(LunarDate.minYear) 年 1 月 1 日 — \(LunarDate.maxYear) 年 12 月 31 日",
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
                }
            }
            .navigationTitle("跳转到日期")
            .navigationBarTitleDisplayMode(.inline)
            .alert("暂不支持该年份",
                   isPresented: $showOutOfRangeAlert) {
                Button("回到今天", role: .cancel) {
                    targetDate = today
                    dismiss()
                }
                Button("留在当前页", role: .none) {
                    // 用户自行重新调整日期 picker
                }
            } message: {
                Text("清和日历支持的日期范围为 \(LunarDate.minYear) 年 1 月至 \(LunarDate.maxYear) 年 12 月。\n请在此范围内选择，或点击上方「回到今天」直接返回。")
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("跳转") { jumpToDate() }
                        .font(.body.weight(.semibold))
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - 逻辑

    private var maxDaysInMonth: Int {
        var dc = DateComponents()
        dc.year = year; dc.month = month
        guard let date = cal.date(from: dc) else { return 31 }
        return cal.range(of: .day, in: .month, for: date)?.count ?? 31
    }

    private func jumpToDate() {
        var dc = DateComponents()
        dc.year = year; dc.month = month; dc.day = day
        guard let date = cal.date(from: dc) else {
            showOutOfRangeAlert = true
            return
        }
        // 范围校验：不支持的日期 → 留在弹窗提示，不 apply 假数据
        guard LunarDate.isSupported(date) else {
            showOutOfRangeAlert = true
            return
        }
        targetDate = date
        dismiss()
    }

    private func jumpTo(_ date: Date) {
        // 快捷跳转同样做范围校验（1900-01 点 上个月→1899，2100 点 一年后→2101
        //   都会越过 LunarDate 的数据边界）。
        guard LunarDate.isSupported(date) else {
            showOutOfRangeAlert = true
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
