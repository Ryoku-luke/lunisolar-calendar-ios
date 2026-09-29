import Foundation
#if canImport(SwiftUI)
import SwiftUI
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
#endif

// MARK: - 设置页辅助类型与子视图（从 SettingsView.swift 拆分，降低单文件体积与编译器负担）

enum ImportedFileType {
    case ics
    case json
}

extension ImportConflictPolicy {
    public var title: String {
        switch self {
        case .keepLatest: return NSLocalizedString("保留最新（推荐）", comment: "")
        case .keepLocal:  return NSLocalizedString("保留本地", comment: "")
        case .overwrite:  return NSLocalizedString("覆盖本地", comment: "")
        }
    }

    public var subtitle: String {
        switch self {
        case .keepLatest: return NSLocalizedString("按 updatedAt 谁更新就用谁", comment: "")
        case .keepLocal:  return NSLocalizedString("同 id 的外部数据一律跳过", comment: "")
        case .overwrite:  return NSLocalizedString("同 id 一律用导入版本覆盖", comment: "")
        }
    }
}

#if canImport(SwiftUI)

// MARK: - Toast 模型 & 视图

struct ToastMessage: Identifiable, Equatable {
    enum Kind: Equatable { case success, warning, error }
    var id = UUID()
    var kind: Kind
    var text: String
    /// 可选行动按钮（例如倒数日的「去设置」）。带行动的 toast 停留更久，点行动即收起。
    /// **需要行动的场景不能退回纯文案 toast**——那等于把用户该走的下一步藏起来
    /// （`docs/DEVICE_TEST_CHECKLIST.md` §1.2 明确要求「不是静默失败」）。
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    // 手写 Equatable：成员里有闭包，合成实现要求闭包可比较（不可能）。
    // 只比呈现相关字段，闭包身份不参与——`.animation(value:)` 与自动消失判据用的都是这些。
    static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool {
        lhs.id == rhs.id && lhs.kind == rhs.kind && lhs.text == rhs.text && lhs.actionTitle == rhs.actionTitle
    }
}

struct ToastBannerView: View {
    let message: ToastMessage

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(bgAccent.opacity(0.18))
                Image(systemName: iconName)
                    .font(AppTheme.Font.bodyBold)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(bgAccent)
            }
            .frame(width: 32, height: 32)
            Text(message.text)
                .font(AppTheme.Font.subheadline.weight(.semibold))
                .foregroundStyle(Color.label)
                .lineLimit(3)
            Spacer(minLength: 8)
            if let title = message.actionTitle, let action = message.action {
                Button(title) { action() }
                    .font(AppTheme.Font.subheadline.weight(.semibold))
                    .foregroundStyle(bgAccent)
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(AccessibilityID.toastAction)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.md)
        .glassCard(radius: AppTheme.Radius.lg,
                   material: .thickMaterial,
                   tint: bgAccent,
                   shadow: AppTheme.Shadow.floating)
        // 统一锚点：UI 测试断言「出现了反馈」只认这一个标识，不必分辨是哪个页面的 toast
        .accessibilityIdentifier(AccessibilityID.stateToast)
    }

    private var iconName: String {
        switch message.kind {
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error:   return "xmark.circle.fill"
        }
    }

    private var bgAccent: Color {
        switch message.kind {
        case .success: return .systemGreen
        case .warning: return .systemOrange
        case .error:   return .systemRed
        }
    }
}

/// 统一 toast 宿主：顶部浮层 + 进出场动画 + 自动消失。
/// 抽成 modifier 是因为要被多个页面共用（设置 / 倒数日 / 跳转到日期）——
/// 复制多份的结果必然是几份不同的计时与动画。
struct QingheToastHost: ViewModifier {
    @Binding var toast: ToastMessage?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let t = toast {
                    ToastBannerView(message: t)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 12)
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .onAppear {
                            Task { @MainActor in
                                // 带行动按钮的多给几秒：用户要先读完才知道点不点
                                let ns: UInt64 = t.actionTitle == nil ? 2_200_000_000 : 6_000_000_000
                                try? await Task.sleep(nanoseconds: ns)
                                if toast?.id == t.id { toast = nil }
                            }
                        }
                }
            }
            .animation(AppTheme.Motion.toast, value: toast)
    }
}

extension View {
    /// 挂上统一 toast 浮层（传 nil 即不显示）
    func qingheToast(_ toast: Binding<ToastMessage?>) -> some View {
        modifier(QingheToastHost(toast: toast))
    }
}

// MARK: - ImportFileModifier（.fileImporter 包装成独立 ViewModifier，降低 body 内联闭包复杂度）

#if canImport(UniformTypeIdentifiers)
struct ImportFileModifier: ViewModifier {
    @Binding var isPresented: Bool
    let fileType: ImportedFileType
    let onResult: (Result<URL, Error>) -> Void

    func body(content: Content) -> some View {
        content.fileImporter(
            isPresented: $isPresented,
            allowedContentTypes: {
                switch fileType {
                case .ics:  return [UTType(filenameExtension: "ics") ?? .data]
                case .json: return [UTType(filenameExtension: "json") ?? .data]
                }
            }()
        ) { result in
            onResult(result)
        }
    }
}
#else
struct ImportFileModifier: ViewModifier {
    @Binding var isPresented: Bool
    let fileType: ImportedFileType
    let onResult: (Result<URL, Error>) -> Void
    func body(content: Content) -> some View { content }
}
#endif


#endif
