#if canImport(SwiftUI)
import SwiftUI

/// 日期卡片右侧空白处的大天气效果图标：按**选中日**当天天气码渲染大图标（不显示温度数字），
/// 让天气预览更直观（如 ☀️ 38pt 大图标，纯图标无文字）。
/// 加载失败/定位未授权时显示中性占位图标，绝不塌陷。
struct WeatherIconView: View {
    /// 要显示天气的日期（通常为选中日期；默认今天）
    var selectedDate: Date = Date()
    @State private var result: WeatherResult?

    var body: some View {
        Group {
            switch result {
            case .some(.success(let snapshot)):
                if let day = Self.daily(for: selectedDate, in: snapshot.days ?? []) {
                    Image(systemName: WMOWeather.describe(day.weatherCode).symbol)
                        .font(.system(size: 38, weight: .medium))
                        .foregroundStyle(Self.symbolColor(day.weatherCode))
                        .frame(width: 48, height: 44)
                } else {
                    // 选中日超出拉取窗口：中性占位
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 38, weight: .medium))
                        .foregroundStyle(Color.quaternaryLabel)
                        .frame(width: 48, height: 44)
                }

            default:
                // 加载中 / 失败：浅色占位图标（可见但不干扰）
                Image(systemName: "cloud.fill")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(Color.quaternaryLabel)
                    .frame(width: 48, height: 44)
            }
        }
        .task { await load() }
    }

    // MARK: - 工具

    /// 取选中日当天的逐日天气（无则 nil）
    private static func daily(for date: Date, in days: [DailyWeather]) -> DailyWeather? {
        let cal = Calendar(identifier: .gregorian)
        return days.first { cal.isDate($0.date, inSameDayAs: date) }
    }

    private static func symbolColor(_ code: Int) -> Color {
        switch code {
        case 0, 1, 2: return .orange
        case 95, 96, 99: return .systemPurple
        default: return .accentColor
        }
    }

    private func load() async {
        guard result == nil else { return }
        result = await WeatherProvider.currentWeather()
    }
}
#endif // canImport(SwiftUI)
