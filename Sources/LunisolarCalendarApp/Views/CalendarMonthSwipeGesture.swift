#if canImport(UIKit)
import SwiftUI

extension CalendarMonthView {
    #if canImport(UIKit)
    /// 完全跟手滑动：拖动中卡片 1:1 跟随手指；松手后按位移/甩动速度判定翻页或回弹。
    func swipeMonthGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: swipeThreshold, coordinateSpace: .local)
            .onChanged { value in
                let dx = value.translation.width
                if !isDragging {
                    let dy = value.translation.height
                    // 首次水平判定：水平占主导才进入跟手态；
                    // 纵向滚动（页面滚动）与轻微点按（日期选中）一律放行
                    guard abs(dx) > 1.5 * abs(dy) else { return }
                }
                isDragging = true
                dragOffsetX = dx
                // 左滑预渲染下月（右侧）、右滑预渲染上月（左侧）；缓存预填充后零卡顿
                previewMonth = dx < 0 ? currentMonth.addingMonths(1) : currentMonth.addingMonths(-1)
            }
            .onEnded { value in
                isDragging = false
                let dx = value.translation.width
                let predicted = value.predictedEndTranslation.width
                // 容器宽度兜底：background GeometryReader 未注入前（首帧）用保守值，防止误翻页
                let w = width > 0 ? width : 360
                // 翻页判定：位移超过容器宽度 22% 或甩动速度足够（P2：阈值从 0.28 降到 0.22，更跟手）
                if abs(dx) > w * 0.22 || abs(predicted - dx) > w * 0.45 {
                    let target = dx < 0 ? currentMonth.addingMonths(1) : currentMonth.addingMonths(-1)
                    monthSlideEdge = dx < 0 ? .trailing : .leading
                    // P2：翻页到位轻触感反馈（UISelectionFeedbackGenerator）
                    #if canImport(UIKit)
                    UISelectionFeedbackGenerator().selectionChanged()
                    #endif
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82, blendDuration: 0.08)) {
                        currentMonth = target
                        selectedDate = Self.clampedToMonth(selectedDate, in: target)
                        dragOffsetX = 0
                    }
                } else {
                    // 未过阈值：回弹原位（preview 网格在屏幕外，直接清空）
                    previewMonth = nil
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82, blendDuration: 0.08)) {
                        dragOffsetX = 0
                    }
                }
            }
    }
    #endif
}
#endif
