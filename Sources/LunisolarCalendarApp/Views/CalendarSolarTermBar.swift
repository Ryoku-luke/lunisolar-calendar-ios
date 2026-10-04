import SwiftUI

/// 节气倒计时条（P4-1：抽取自 `CalendarMonthView.solarTermBar`）。
///
/// 只依赖入参、**不持有任何状态**——父视图仍是状态所有者，这就是这次抽取的安全边界：
/// 移动的是视图组装，不是状态所有权。
struct CalendarSolarTermBar: View {
    let accent: Color

    var body: some View {
        if let next = SolarTermProvider.nextTerm(from: Date()) {
            HStack(spacing: 6) {
                Image(systemName: "leaf")
                    .font(.caption)
                    .foregroundStyle(Color.secondaryLabel)
                    // 装饰图标：旁边的「下一个节气」文字已是完整语义
                    .accessibilityHidden(true)
                Text("下一个节气")
                    .font(.caption)
                    .foregroundStyle(Color.tertiaryLabel)
                Text(next.name)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, AppTheme.Spacing.xs)
                    .padding(.vertical, 2)
                    // N-8② 折中：节气名用装饰原色保留节日氛围，淡底衬保证浅色模式下可读
                    .background(Capsule().fill(accent.opacity(0.14)))
                if next.daysRemaining > 0 {
                    Text(String(format: NSLocalizedString("还有 %d 天", comment: ""), next.daysRemaining))
                        .font(.caption)
                        .foregroundStyle(Color.secondaryLabel)
                } else if next.daysRemaining == 0 {
                    Text("今天")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.festiveRed)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.xs)
            .background(AdaptiveMaterialFill(material: .ultraThinMaterial, shape: Capsule()))
        }
    }
}
