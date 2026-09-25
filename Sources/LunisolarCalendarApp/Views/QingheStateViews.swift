#if canImport(SwiftUI)
import SwiftUI

// MARK: - 统一三态组件（UI 报告 §37 / §41）
//
// 报告要求「每个 Feature 的 Loading / Empty / Error 表现一致」，此前是各页自己拼
// `ProgressView` / `ContentUnavailableView` / 就地重试：同为「加载失败」，
// 天气卡与别的页长得完全不一样。这里给出一套共用件。
//
// 设计口径（照报告 §41）：
// - **Loading**：骨架屏，先给出内容形状，避免白屏一闪。骨架屏此前全仓 0 处。
// - **Empty**：图标 + 标题 + 说明 + 行动按钮（四要素）。现有空态只有前三项。
// - **Error**：怎么了 / 为什么 / 怎么办，且必须给重试入口。
//
// 无障碍（报告 §44）：骨架屏对读屏念一堆空块毫无意义，因此整体作为一个元素、
// 只朗读「正在加载」；呼吸动画在「减弱动态效果」开启时关闭。

// MARK: 骨架屏基础块

/// 一块示意内容形状的占位。可单独使用，也可由 `QingheLoadingView` 组合。
public struct QingheSkeletonBlock: View {
    public var height: CGFloat
    /// nil = 撑满可用宽度
    public var width: CGFloat?
    public var cornerRadius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    public init(height: CGFloat = 14,
                width: CGFloat? = nil,
                cornerRadius: CGFloat = AppTheme.Radius.sm) {
        self.height = height
        self.width = width
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.themeQuaternaryFill)
            .frame(width: width, height: height)
            .opacity(pulsing ? 0.55 : 1)
            // 「减弱动态效果」开启时不做呼吸动画（传入 nil 即不动画）
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                       value: pulsing)
            .onAppear { if !reduceMotion { pulsing = true } }
            .accessibilityHidden(true)
    }
}

// MARK: 加载态

// 这里**刻意不提供**「页面级骨架屏」组合件（`QingheLoadingView` 那种）。
// 原因：本 App 的数据是同步的（EventStore 在 init 里读 JSON），
// 全仓三处 `ProgressView` 都是「按钮旁边正在执行」的行内指示，套骨架屏是错的；
// 真正异步的只有天气与 iCloud 同步，它们各自用 `QingheSkeletonBlock`
// 或行内指示即可。没有消费者的组合件只会变成死代码——等真有异步页面时再加。
// 骨架屏此前全仓 0 处，`QingheSkeletonBlock` 是它的基础块。

// MARK: 空态

/// 统一空态：图标 + 标题 +（可选）说明 +（可选）行动按钮。
public struct QingheEmptyView: View {
    public var icon: String
    public var title: String
    public var message: String?
    public var actionTitle: String?
    public var action: (() -> Void)?

    public init(icon: String,
                title: String,
                message: String? = nil,
                actionTitle: String? = nil,
                action: (() -> Void)? = nil) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 38, weight: .regular))
                .foregroundStyle(Color.tertiaryLabel)

            Text(title)
                .font(AppTheme.Font.bodyBold)
                .foregroundStyle(Color.label)
                .multilineTextAlignment(.center)

            if let message, !message.isEmpty {
                Text(message)
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(Color.secondaryLabel)
                    .multilineTextAlignment(.center)
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(AppTheme.Font.subheadline.weight(.semibold))
                        .foregroundStyle(Color.appTint)
                        .padding(.horizontal, AppTheme.Spacing.lg)
                        .padding(.vertical, AppTheme.Spacing.sm)
                        .background(Capsule().fill(Color.appTint.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .touchTarget()
                .padding(.top, AppTheme.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(AppTheme.Spacing.xxl)
        .accessibilityIdentifier(AccessibilityID.stateEmpty)
    }
}

// MARK: 错误态

/// 统一错误态。两种排版：
/// - `.card`：整块的三问（怎么了 / 为什么 / 怎么办），用于页面级失败；
/// - `.compact`：单行「图标 + 说明 + 按钮」，用于天气卡这种紧凑插槽。
public struct QingheErrorView: View {
    public enum Style { case card, compact }

    public var style: Style
    public var icon: String
    public var title: String
    public var message: String?
    /// 主行动（通常是「重试」）
    public var retryTitle: String?
    public var onRetry: (() -> Void)?
    /// 次行动（通常是「去设置」）
    public var settingsTitle: String?
    public var onOpenSettings: (() -> Void)?

    public init(style: Style = .card,
                icon: String = "exclamationmark.triangle",
                title: String,
                message: String? = nil,
                retryTitle: String? = NSLocalizedString("重试", comment: ""),
                onRetry: (() -> Void)? = nil,
                settingsTitle: String? = nil,
                onOpenSettings: (() -> Void)? = nil) {
        self.style = style
        self.icon = icon
        self.title = title
        self.message = message
        self.retryTitle = retryTitle
        self.onRetry = onRetry
        self.settingsTitle = settingsTitle
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        switch style {
        case .card:    cardBody
        case .compact: compactBody
        }
    }

    // 怎么了（图标 + 标题）/ 为什么（说明）/ 怎么办（按钮）
    private var cardBody: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(Color.systemOrange)

            Text(title)
                .font(AppTheme.Font.bodyBold)
                .foregroundStyle(Color.label)
                .multilineTextAlignment(.center)

            if let message, !message.isEmpty {
                Text(message)
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(Color.secondaryLabel)
                    .multilineTextAlignment(.center)
            }

            actionRow
        }
        .frame(maxWidth: .infinity)
        .padding(AppTheme.Spacing.xxl)
        .accessibilityIdentifier(AccessibilityID.stateError)
    }

    private var compactBody: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: icon)
                .font(.footnote)
                .foregroundStyle(Color.secondaryLabel)
            Text(message ?? title)
                .font(.footnote)
                .foregroundStyle(Color.secondaryLabel)
                .lineLimit(2)
            Spacer(minLength: AppTheme.Spacing.sm)
            actionRow
        }
        .accessibilityIdentifier(AccessibilityID.stateError)
    }

    @ViewBuilder
    private var actionRow: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            if let retryTitle, let onRetry {
                pillButton(retryTitle, tint: .appTint, action: onRetry)
            }
            if let settingsTitle, let onOpenSettings {
                pillButton(settingsTitle, tint: .appTint, action: onOpenSettings)
            }
        }
    }

    private func pillButton(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(tint.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .touchTarget()
    }
}

// MARK: 行内提示

/// 统一行内提示：替代模态 alert 的轻反馈（报告 §42「同一件事不要既 Toast 又 Alert」）。
public struct QingheToast: View {
    public var icon: String
    public var message: String

    public init(icon: String = "checkmark.circle.fill", message: String) {
        self.icon = icon
        self.message = message
    }

    public var body: some View {
        Label(message, systemImage: icon)
            .font(AppTheme.Font.subheadline.weight(.semibold))
            .foregroundStyle(Color.appTint)
            .accessibilityIdentifier(AccessibilityID.stateToast)
    }
}
#endif
