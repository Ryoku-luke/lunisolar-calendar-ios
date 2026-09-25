#if canImport(SwiftUI)
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 嵌入日期卡片的当日天气文字块：只显示**选中日**当天的天气（城市·天气 + 温度 + 高低温）。
/// 切换选中日期 → 天气自动跟随该日（查快照内的逐日数据，不重新请求）；
/// 数据整体按「今天」刷新，跨天自动重取（见 refreshDayKey）。今天额外显示当前温度。
/// 无独立背景、紧凑文字块（配合 WeatherIconView 大图标上下排布，或独立行使用）。
/// 三态：成功 → 当日天气；定位未授权 → 紧凑提示；失败 → 紧凑重试。
struct WeatherCardView: View {
    /// 要显示天气的日期（通常为选中日期；默认今天）
    var selectedDate: Date = Date()
    /// 文字对齐方向：主界面日期卡片右侧列用 .trailing，详情页独立行用 .leading
    var alignment: HorizontalAlignment = .leading
    /// 每次拿到成功快照时上报给父视图。
    /// 用于「大图标 + 文字块」并排的组合：两者必须看到同一份天气，
    /// 否则文字块重试成功后，并排的图标仍停在占位云。
    var onSnapshot: (WeatherSnapshot) -> Void = { _ in }
    @State private var result: WeatherResult?
    /// 用途只有一个：让「回到前台」成为会触发本视图重算的事件（见 refreshDayKey）
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch result {
            case .some(.success(let snapshot)):
                dayWeatherBlock(snapshot)

            case .some(.denied):
                // 统一错误态（紧凑版）：怎么了 = 定位未开启；怎么办 = 去设置
                QingheErrorView(
                    style: .compact,
                    icon: "location.slash.fill",
                    title: NSLocalizedString("定位未开启，无法显示天气", comment: ""),
                    message: NSLocalizedString("定位未开启，无法显示天气", comment: ""),
                    retryTitle: nil,
                    settingsTitle: NSLocalizedString("去设置", comment: ""),
                    onOpenSettings: { openSystemSettings() }
                )

            case .some(.failed):
                QingheErrorView(
                    style: .compact,
                    icon: "arrow.clockwise",
                    title: NSLocalizedString("天气加载失败", comment: ""),
                    message: NSLocalizedString("天气加载失败", comment: ""),
                    retryTitle: NSLocalizedString("重试", comment: ""),
                    onRetry: { retry() }
                )

            case nil:
                // 骨架屏代替转圈：先给出文字形状（报告 §41 要求 Loading 用骨架屏）
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    QingheSkeletonBlock(height: 12, width: 96)
                    QingheSkeletonBlock(height: 12, width: 64)
                }
                .frame(minHeight: 24)
            }
        }
        .task(id: refreshDayKey) { await load() }
    }

    // MARK: - 刷新时机

    /// `.task(id:)` 的刷新键：今天 00:00。
    ///
    /// 天气数据整体锚在「今天」——「当前温度」和逐日预报都按请求那一刻算，所以：
    /// · 切换选中日期**不需要**重新请求：快照里的 days 已覆盖前 3 天 ~ 后 14 天，
    ///   dayWeatherBlock 直接按日期查表；窗口外的日期重取也拉不到（API 日期参数是固定的）。
    /// · 跨天**必须**重新请求：否则「当前温度」会一直停在昨天。
    /// 读一下 scenePhase 没有别的用途——body 里的 Date() 自身不具反应性，借它让
    /// 「回到前台」也触发本视图重算；同一自然日内键不变，`.task(id:)` 因此不会重复请求
    /// （inactive 抖动同理不触发，因为刷新键没变）。
    private var refreshDayKey: Date {
        _ = scenePhase
        return Calendar(identifier: .gregorian).startOfDay(for: Date())
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
                    Text(NSLocalizedString("暂无该日天气", comment: ""))
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

    // MARK: - 动作

    private func load() async {
        // 不清空当前 result（避免闪 loading）；只有新结果成功时才替换，失败/未授权保留上次快照
        let newResult = await WeatherProvider.currentWeather()
        // 只有新结果成功时才替换；失败/未授权保留上次快照
        switch newResult {
        case .success:
            result = newResult
            publish(newResult)
        case .denied, .failed:
            // 失败时如果之前有成功快照，保留它；否则才显示失败态
            if result == nil { result = newResult }
        }
    }

    private func retry() {
        Task {
            let newResult = await WeatherProvider.currentWeather()
            result = newResult
            publish(newResult)
        }
    }

    /// 把成功快照上报给父视图（供并排的天气大图标同步渲染，避免两份状态）
    private func publish(_ newResult: WeatherResult) {
        if case .success(let snapshot) = newResult { onSnapshot(snapshot) }
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
#endif // canImport(SwiftUI)
