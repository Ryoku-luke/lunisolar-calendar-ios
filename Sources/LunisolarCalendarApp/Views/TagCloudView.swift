import SwiftUI

/// 宜/忌标签云：流式布局，空数组显示 "—"
struct TagCloudView: View {
    let tags: [String]
    var tint: Color = .appTint
    var font: Font = AppTheme.Font.caption2
    var body: some View {
        FlowLayout(spacing: 4, lineSpacing: 4) {
            ForEach(tags, id: \.self) { tag in
                Text(tag).font(font).fontWeight(.medium)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(tint.opacity(0.12)))
                    .foregroundStyle(tint)
            }
            if tags.isEmpty {
                Text("—").font(font).foregroundStyle(Color.quaternaryLabel)
            }
        }
        // 宜/忌标签是整体展示信息：VoiceOver 一次性读出全部，避免逐个标签打断
        .accessibilityElement(children: .combine)
    }
}
