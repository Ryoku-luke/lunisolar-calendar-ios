import SwiftUI

#if canImport(UIKit)
import UIKit

/// 日期格上的 UIKit 长按识别器（自绘长按菜单的入口）。
///
/// **为什么不用系统 `.contextMenu`**：它会对格子做**位图快照**，长按回落时缩放这张位图 →
/// 文字被重采样（实测"回落一瞬间字扭曲变形"）；且抬起预览的圆角由系统决定、
/// 与格子自身的 `RoundedRectangle` 不一致（"圆角依然不一致"）。
/// 只要还用系统菜单，这两件事都消不掉。
///
/// **为什么不用 SwiftUI 手势**：两条路都已实测否掉 —— `Button` 吞横向拖动
/// （`testFlow17` 横滑翻月失效）、`.pressableFeedback()`（内部 DragGesture）吞 tap
/// （`testFlow1` 点击不再选中）。`UILongPressGestureRecognizer` 配
/// `cancelsTouchesInView = false` + 并行识别，是唯一能同时容纳「点按 / 横滑 / 长按」的做法
/// （本仓 `TapOutsideKeyboardDismisser` 同款思路）。
struct DayCellLongPressCatcher: UIViewRepresentable {
    var onLongPress: () -> Void
    var onRelease: () -> Void
    /// 点按回调。**必须由这里提供**：overlay 的 UIKit 视图会抢走命中测试，
    /// 挂在下面的 SwiftUI `.onTapGesture` 收不到点击（实测：不提供 tap 回调时
    /// `testFlow1` 变红——"点击后该日期格应带上选中态"）。
    var onTap: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let press = UILongPressGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handle(_:)))
        press.minimumPressDuration = 0.32
        press.cancelsTouchesInView = false          // 不吞拖动（横滑翻月靠它保住）
        press.delegate = context.coordinator
        view.addGestureRecognizer(press)
        // 点按也在这里处理（UIKit 自己会与长按仲裁：快按走 tap、按住走 long press）
        let tap = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        tap.require(toFail: press)
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private let parent: DayCellLongPressCatcher
        init(_ parent: DayCellLongPressCatcher) { self.parent = parent }

        @objc func handle(_ gesture: UILongPressGestureRecognizer) {
            switch gesture.state {
            case .began: parent.onLongPress()
            case .ended, .cancelled, .failed: parent.onRelease()
            default: break
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            parent.onTap()
        }

        func gestureRecognizer(_ gesture: UIGestureRecognizer,
                              shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
#endif

/// 非 UIKit 平台（macOS 宿主构建）的占位实现：不装识别器，等同原样。
/// 真实实现见上方 UIKit 版本 —— 本包同时为 macOS 宿主构建，缺了它网格视图编译不过。
#if !canImport(UIKit)
struct DayCellLongPressCatcher: View {
    var onLongPress: () -> Void
    var onRelease: () -> Void
    var onTap: () -> Void
    var body: some View { Color.clear }
}
#endif

/// 自绘长按菜单：圆角与格子**同源**（`DayCellView.selectionRadius`）、动画走
/// `AppTheme.Motion.selection`、**不做位图快照** —— 回落时文字不会被重采样，
/// 圆角也与格子一致。这是解决"回落文字变形 + 圆角不一致"的关键。
struct DayCellLongPressMenu: View {
    let radius: CGFloat
    /// 菜单卡在浮层容器里的位置（来自被长按格子的 frame）。
    /// 由调用方传入，而不是让调用方对整体加 .offset —— 这样"背景压暗层"才能铺满容器、
    /// **只让菜单卡偏移**（否则压暗层会被一起挪走，等于没有背景）。
    let offset: CGSize
    let onSelect: () -> Void
    let onNew: () -> Void
    let onCopy: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 背景压暗层：系统菜单"悬浮感"的重要一半 —— 背景被压暗、菜单浮在上面。
            // 它同时承担"点击外部关闭"：此前只把可点区域放在菜单自身 bounds 内，
            // 导致**点菜单外面根本关不掉**（真机反馈"悬浮效果丢失"时一并暴露）。
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }
                .transition(.opacity)

            card
                .offset(x: offset.width, y: offset.height)
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            item("选中此日", "checkmark.circle", onSelect)
            Divider()
            item("新建日程", "plus.circle", onNew)
            Divider()
            item("复制日期", "doc.on.doc", onCopy)
        }
        .frame(minWidth: 168)
        // .thinMaterial（比 regular 更薄更透）→ 更接近系统菜单那种"半透明悬浮"观感。
        .background(.thinMaterial,
                    in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Color.themeSeparator.opacity(0.25), lineWidth: AppTheme.Stroke.hair)
        }
        // 阴影加大 → 抬得更高、更像浮在内容之上
        .shadow(color: .black.opacity(0.24), radius: 18, y: 8)
        // 从格子位置略微放大浮出（起点更小 + 锚在左上角，配合压暗层淡入）
        .transition(.scale(scale: 0.86, anchor: .topLeading).combined(with: .opacity))
    }

    private func item(_ title: LocalizedStringKey, _ symbol: String,
                      _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(AppTheme.Font.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppTheme.Spacing.md)
                .frame(minHeight: AppTheme.Touch.minTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pressableFeedback()
    }
}

/// 系统上下文菜单，**仅在 VoiceOver 运行时**挂载（无障碍降级）。
/// 普通用户走自绘菜单，因此不再触发系统的位图快照。
struct SystemMenuForVoiceOver: ViewModifier {
    let onSelect: () -> Void
    let onNew: () -> Void
    let onCopy: () -> Void

    func body(content: Content) -> some View {
        #if canImport(UIKit)
        if UIAccessibility.isVoiceOverRunning {
            content.contextMenu {
                Button { onSelect() } label: { Label("选中此日", systemImage: "checkmark.circle") }
                Button { onNew() } label: { Label("新建日程", systemImage: "plus.circle") }
                Button { onCopy() } label: { Label("复制日期", systemImage: "doc.on.doc") }
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}
