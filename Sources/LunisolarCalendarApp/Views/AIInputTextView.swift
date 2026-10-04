import SwiftUI
import Foundation

#if canImport(UIKit)
import UIKit
#endif

// MARK: - UITextView 桥接（绕开 iOS 27 模拟器 FocusState 不弹键盘的 bug）
#if canImport(UIKit)
struct AutoFocusTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    /// 回车（Return）提交：与键盘工具栏的「解析」等价，省去"先收键盘再点按钮"
    let onSubmit: () -> Void

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.font = .preferredFont(forTextStyle: .body)
        tv.backgroundColor = .secondarySystemBackground
        tv.layer.cornerRadius = 12
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        tv.delegate = context.coordinator
        // UI 测试锚点：SwiftUI 的 .accessibilityIdentifier 不会传递到 UIViewRepresentable
        // 包着的 UIKit 视图，必须在 UITextView 上直接设。
        tv.accessibilityIdentifier = AccessibilityID.aiInput
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        // 组字中（拼音 / 听写的 marked text）绝不插手文本 —— 程序化改写会中断听写与联想。
        // 其余情况按"文本是否一致"同步：正常输入时两者恒等（delegate 已回写），
        // 只有程序化清空/恢复才会走到回写分支（若额外用 isFirstResponder 门挡掉，
        // 一键清空后字段会停留在旧文本）。
        if uiView.markedTextRange == nil, uiView.text != text {
            uiView.text = text
        }
        if focused && !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !focused && uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
        // 安装/刷新「点输入框之外收键盘」的 UIKit 手势（幂等）。
        // 放在这里而不是 makeUIView：此时视图已在层级中，才能向上找到外层滚动视图。
        TapOutsideKeyboardDismisser.shared.bind(textView: uiView) {
            focused = false
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// 只做「文本 / 焦点」双向同步。
    ///
    /// 占位文案已移出本类，改由 SwiftUI 侧 overlay 渲染。历史实现把 placeholder
    /// 直接写进 UITextView 并在清空时重新填回，导致：
    /// - 编辑中清空后，占位串被当作输入内容（下一次按键会拼在占位串后面）；
    /// - 文本颜色在 .placeholderText / .label 之间来回切换，状态难以自洽。
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: AutoFocusTextView
        init(_ p: AutoFocusTextView) { parent = p }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.focused = true
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            // 回车 = 解析。多行文本里回车默认是换行；本页只收"一句话"，
            // 用回车提交可省掉「先收键盘 → 再点按钮」这一步（真机反馈交互拖沓的主因）
            if text == "\n" {
                parent.focused = false
                parent.onSubmit()
                return false
            }
            return true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.focused = false
        }
    }
}

/// 「点输入框之外收键盘」的 **UIKit 实现**。
///
/// 为什么绕开 SwiftUI 手势：三种 SwiftUI 写法都会破坏别的东西（详见本文件下方的注释）——
/// `simultaneousGesture` 会抢输入框焦点、`onTapGesture` 会吞掉行内按钮的点击、
/// `SpatialTapGesture` + PreferenceKey 拿不到输入框 frame。
///
/// UIKit 这条路能做对，靠的是两件 SwiftUI 手势做不到的事：
/// 1. `cancelsTouchesInView = false`：手势**不吞**触摸，行内按钮、列表行照常收到点击；
/// 2. `gestureRecognizer(_:shouldReceive:)` 里按**命中区域**判断：触摸点落在输入框内部时
///    直接不受理该触摸 —— 于是「点输入框本身」不会被误判成「点外面」。
///
/// 手势挂在**外层滚动视图**（List 底层的 UICollectionView）上，覆盖整页可点区域。
@MainActor
final class TapOutsideKeyboardDismisser: NSObject, UIGestureRecognizerDelegate {
    static let shared = TapOutsideKeyboardDismisser()

    private weak var host: UIScrollView?
    private weak var textView: UITextView?
    private var onDismiss: (() -> Void)?

    /// 由输入框在每次布局更新时调用：绑定当前输入框，必要时安装手势。
    /// 幂等：宿主滚动视图仍有效时不重复安装（否则会叠加多个手势）。
    func bind(textView: UITextView, onDismiss: @escaping () -> Void) {
        self.textView = textView
        self.onDismiss = onDismiss

        if let host, host.window != nil { return }
        guard let scrollView = Self.enclosingScrollView(of: textView) else { return }
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        scrollView.addGestureRecognizer(tap)
        host = scrollView
    }

    @objc private func handleTap() {
        // 只在键盘真的弹着时才动作，避免无谓地改状态
        guard textView?.isFirstResponder == true else { return }
        onDismiss?()
    }

    /// 命中输入框内部的触摸不受理 —— 否则刚点起来的键盘会被立刻收掉
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        guard let textView else { return false }
        return !textView.bounds.contains(touch.location(in: textView))
    }

    private static func enclosingScrollView(of view: UIView) -> UIScrollView? {
        var candidate = view.superview
        while let current = candidate {
            if let scrollView = current as? UIScrollView { return scrollView }
            candidate = current.superview
        }
        return nil
    }
}
#endif
