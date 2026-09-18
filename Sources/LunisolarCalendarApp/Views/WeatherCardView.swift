import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 嵌入日期卡片的当日天气文字块：只显示**选中日**当天的天气（城市·天气 + 温度 + 高低温）。
/// 切换选中日期 → 天气自动跟随该日；今天额外显示当前温度。
/// 无独立背景、紧凑文字块（配合 WeatherIconView 大图标上下排布，或独立行使用）。
/// 三态：成功 → 当日天气；定位未授权 → 紧凑提示；失败 → 紧凑重试。
struct WeatherCardView: View {
    /// 要显示天气的日期（通常为选中日期；默认今天）
    var selectedDate: Date = Date()
    /// 文字对齐方向：主界面日期卡片右侧列用 .trailing，详情页独立行用 .leading
    var alignment: HorizontalAlignment = .leading
    @State private var result: WeatherResult?

    var body: some View {
        Group {
            switch result {
            case .some(.success(let snapshot)):
                dayWeatherBlock(snapshot)

            case .some(.denied):
                compactStatusRow(icon: "location.slash.fill", text: "定位未开启，无法显示天气", actionLabel: "去设置") {
                    openSystemSettings()
                }

            case .some(.failed):
                compactStatusRow(icon: "arrow.clockwise", text: "天气加载失败", actionLabel: "重试") {
                    retry()
                }

            case nil:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("加载天气…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(minHeight: 24)
            }
        }
        .task { await load() }
    }

    // MARK: - 当日天气文字块（图标随天气由 WeatherIconView 承担，这里只放文字）

    private func dayWeatherBlock(_ snapshot: WeatherSnapshot) -> some View {
        let day = Self.daily(for: selectedDate, in: snapshot.days ?? [])
        let isToday = Calendar(identifier: .gregorian).isDate(selectedDate, inSameDayAs: Date())
        return VStack(alignment: alignment, spacing: 3) {
            if let day {
                // 城市 · 天气（辅助信息）
                Text("\(snapshot.locationName) · \(WMOWeather.describe(day.weatherCode).text)")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                // 温度大字独占一行（与高低温分开，避免大小混排突兀）
                if isToday {
                    Text("\(Int(snapshot.temperature.rounded()))°")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }
                // 高低温
                Text("最高\(Int(day.maxTemp.rounded()))° 最低\(Int(day.minTemp.rounded()))°")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            } else {
                // 选中日超出拉取窗口（前 3 天 ~ 后 14 天）时的兜底：
                // 拆成两行短文本（城市 / 暂无天气），避免单行长文案挤压日期卡片
                // 中间的农历列导致农历换行。
                VStack(alignment: alignment, spacing: 2) {
                    Text(snapshot.locationName)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("暂无该日天气")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .frame(minHeight: 24)
    }

    // MARK: - 工具

    /// 取选中日当天的逐日天气（无则 nil）
    private static func daily(for date: Date, in days: [DailyWeather]) -> DailyWeather? {
        let cal = Calendar(identifier: .gregorian)
        return days.first { cal.isDate($0.date, inSameDayAs: date) }
    }

    // MARK: - 状态行（未授权 / 失败共用，紧凑）

    private func compactStatusRow(icon: String, text: String, actionLabel: String,
                                  action: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: action) {
                Text(actionLabel)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
        .frame(minHeight: 24)
    }

    // MARK: - 动作

    private func load() async {
        guard result == nil else { return }
        result = await WeatherProvider.currentWeather()
    }

    private func retry() {
        Task {
            result = nil
            result = await WeatherProvider.currentWeather()
        }
    }

    #if canImport(UIKit)
    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
    #else
    private func openSystemSettings() {}
    #endif
}
