#if canImport(SwiftUI)
import SwiftUI

/// 日期卡片右侧空白处的大天气效果图标：按**选中日**当天天气码渲染大图标（不显示温度数字），
/// 让天气预览更直观（如 ☀️ 38pt 大图标，纯图标无文字）。
/// 加载失败/定位未授权时显示中性占位图标，绝不塌陷。
struct WeatherIconView: View {
    /// 要显示天气的日期（通常为选中日期；默认今天）
    var selectedDate: Date = Date()
    /// 父视图提供的共享快照（「大图标 + 文字块」并排时由父视图驱动）。
    /// 非 nil 时优先用它 —— 否则同一天气存在两份独立状态：
    /// 文字块重试成功、这边还停在占位云。
    var sharedSnapshot: WeatherSnapshot? = nil
    @State private var result: WeatherResult?

    /// 父视图给了快照就用它，否则用本视图自己拉到的结果
    private var effectiveResult: WeatherResult? {
        sharedSnapshot.map { WeatherResult.success($0) } ?? result
    }

    var body: some View {
        Group {
            switch effectiveResult {
            case .some(.success(let snapshot)):
                if let day = Self.daily(for: selectedDate, in: snapshot.days ?? []) {
                    Image(systemName: WMOWeather.describe(day.weatherCode).symbol)
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(Self.symbolColor(day.weatherCode))
                        .frame(width: 52, height: 52)
                        .background {
                            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                                .fill(Self.symbolColor(day.weatherCode).opacity(0.10))
                        }
                } else {
                    placeholder
                }

            default:
                placeholder
            }
        }
        .task {
            // 父视图已提供共享快照时不再自行请求：同一天气不必拉两份，
            // 也让「文字块重试成功」能立刻反映到这边
            guard sharedSnapshot == nil else { return }
            await load()
        }
    }

    /// 加载中/失败/越界：中性占位
    private var placeholder: some View {
        Image(systemName: "cloud.fill")
            .font(.system(size: 32, weight: .medium))
            .foregroundStyle(Color.quaternaryLabel)
            .frame(width: 52, height: 52)
            .background {
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .fill(Color.themeQuaternaryFill)
            }
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
