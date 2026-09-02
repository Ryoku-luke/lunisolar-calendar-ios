#if canImport(SwiftUI)
import SwiftUI

/// 日期跳转 Sheet：快速跳转到任意日期。
struct DateJumpView: View {
    @Binding var targetDate: Date
    @Environment(\.dismiss) private var dismiss

    @State private var year: Int
    @State private var month: Int
    @State private var day: Int

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
                        ForEach(1900...2100, id: \.self) { Text("\($0) 年").tag($0) }
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
        if let date = cal.date(from: dc) {
            targetDate = date
        }
        dismiss()
    }

    private func jumpTo(_ date: Date) {
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
