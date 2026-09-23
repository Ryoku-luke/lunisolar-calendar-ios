#if canImport(SwiftUI)
import SwiftUI

// MARK: - 日历显示设置（设计稿 04）
/// 月历标注开关：农历 / 节气 / 节假日。关闭后月历对应小字隐藏，
/// 当日卡片与黄历详情不受影响。
struct CalendarDisplaySettingsView: View {
    @AppStorage("Lunisolar.showLunar") private var showLunar = true
    @AppStorage("Lunisolar.showSolarTerm") private var showSolarTerm = true
    @AppStorage("Lunisolar.showHoliday") private var showHoliday = true

    var body: some View {
        List {
            Section {
                Toggle(isOn: $showLunar) {
                    Label("显示农历", systemImage: "moon")
                }
                Toggle(isOn: $showSolarTerm) {
                    Label("显示节气", systemImage: "leaf")
                }
                Toggle(isOn: $showHoliday) {
                    Label("显示节假日", systemImage: "star")
                }
            } header: {
                Text("日历显示")
            } footer: {
                Text("关闭后月历对应标注将隐藏，不影响当日卡片与黄历详情")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("日历")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

#Preview {
    NavigationStack { CalendarDisplaySettingsView() }
}
#endif
