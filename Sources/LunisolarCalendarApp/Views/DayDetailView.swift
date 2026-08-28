#if canImport(SwiftUI)
import SwiftUI

// MARK: - 日详情视图：黄历 + 当日日程列表

struct DayDetailView: View {
    @Environment(EventStore.self) private var store
    @Environment(\.horizontalSizeClass) private var hSizeClass
    let date: Date

    /// iPad regular 宽屏下约束内容最大宽度，避免文字行宽过大影响可读性
    private var isRegular: Bool { hSizeClass == .regular }

    var body: some View {
        let huangli = HuangliGenerator.generate(for: date)
        let events = store.events(on: date)

        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                // 顶部：日期 + 农历 + 黄道
                headerCard(huangli: huangli)

                // 黄历宜忌
                huangliCard(huangli: huangli)

                // 其他信息：冲煞、五行、神位
                extraHuangliCard(huangli: huangli)

                // 当日日程
                eventsCard(events: events)

                // 底部留白
                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .frame(maxWidth: isRegular ? 720 : .infinity) // iPad 限宽
            .frame(maxWidth: .infinity) // 居中
        }
        .background(Color.systemGroupedBackground.ignoresSafeArea())
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        // iOS 26：详情页使用常规材质导航栏（与月视图保持一致）
        .toolbarBackground(.navBar, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    EventEditView(editing: nil, defaultDate: date)
                        .environment(store)
                } label: {
                    // iOS 26：SF Symbols 5 palette 渲染
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.appTint, Color.quaternarySystemFill)
                }
            }
        }
        .tint(Color.appTint)
    }

    private var navTitle: String {
        "\(date.year)/\(date.month)/\(date.day)"
    }

    // MARK: - 顶部卡片

    private func headerCard(huangli: HuangliDay) -> some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(spacing: 4) {
                Text("\(date.day)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(date.isToday ? Color.systemRed : Color.label)
                Text(date.weekdaySymbol)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.secondaryLabel)
                Text(date.isToday ? "今天" : "")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.systemRed)
            }
            .frame(width: 78)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.secondarySystemGroupedBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.separator.opacity(0.35), lineWidth: 0.5)
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("\(date.year)年\(date.month)月\(date.day)日")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.secondaryLabel)

                Text(huangli.lunar.displayString)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.label)

                HStack(spacing: 8) {
                    Text("\(huangli.lunar.yearGanZhi)年")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(
                            Capsule().fill(Color.systemIndigo.opacity(0.14))
                        )
                        .foregroundStyle(Color.systemIndigo)

                    Label(huangli.lunar.yearAnimal, systemImage: "pawprint.circle.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(
                            Capsule().fill(Color.systemOrange.opacity(0.14))
                        )
                        .foregroundStyle(Color.systemOrange)
                }

                if huangli.isAuspicious {
                    Label("黄道吉日 · 诸事顺遂", systemImage: "sparkles")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(
                            Capsule().fill(Color.auspicious.opacity(0.14))
                        )
                        .foregroundStyle(Color.auspicious)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        // iOS 26 液态玻璃：头部卡片
        .liquidGlassCard(
            cornerRadius: 24,
            borderColor: Color.separator.opacity(0.4),
            borderWidth: 0.5,
            shadowOpacity: 0.06
        )
    }

    // MARK: - 黄历宜忌卡片

    private func huangliCard(huangli: HuangliDay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "book.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.systemOrange)
                Text("黄历宜忌")
                    .font(.headline)
                    .foregroundStyle(Color.label)
                Spacer()
            }

            HStack(alignment: .top, spacing: 12) {
                // 宜
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Text("宜")
                            .font(.caption2.weight(.bold))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.systemGreen.opacity(0.88)))
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    tagGrid(tags: huangli.yi, tint: Color.systemGreen)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // 忌
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Text("忌")
                            .font(.caption2.weight(.bold))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.systemRed.opacity(0.88)))
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    tagGrid(tags: huangli.ji, tint: Color.systemRed)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        // iOS 26 液态玻璃：黄历宜忌卡片
        .liquidGlassCard(
            cornerRadius: 20,
            borderColor: Color.separator.opacity(0.4),
            borderWidth: 0.5,
            shadowOpacity: 0.05
        )
    }

    /// 使用FlowLayout排列标签（每行按宽度自动换行，不依赖屏幕宽度硬编码）
    private func tagGrid(tags: [String], tint: Color) -> some View {
        FlowLayout(spacing: 4, lineSpacing: 4) {
            ForEach(tags.indices, id: \.self) { idx in
                Text(tags[idx])
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(tint.opacity(0.12))
                    )
                    .foregroundStyle(tint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 其他黄历信息

    private func extraHuangliCard(huangli: HuangliDay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.systemTeal)
                Text("其他信息")
                    .font(.headline)
                Spacer()
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                infoRow(title: "冲煞", value: huangli.displayChongSha, icon: "xmark.shield")
                infoRow(title: "五行纳音", value: huangli.wuXing, icon: "flame.circle")
                infoRow(title: "神位", value: huangli.shenWei, icon: "sparkles", span: 2)
            }
        }
        .padding(16)
        // iOS 26 液态玻璃：其他信息卡片
        .liquidGlassCard(
            cornerRadius: 20,
            borderColor: Color.separator.opacity(0.4),
            borderWidth: 0.5,
            shadowOpacity: 0.05
        )
    }

    private func infoRow(title: String, value: String, icon: String, span: Int = 1) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.systemTeal)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(Color.secondaryLabel)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.label)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondarySystemGroupedBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.separator.opacity(0.3), lineWidth: 0.5)
        )
        .gridCellColumns(span)
    }

    // MARK: - 当日日程卡片

    private func eventsCard(events: [CalendarEvent]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.systemBlue)
                Text("当日日程 (\(events.count))")
                    .font(.headline)
                Spacer()
                NavigationLink {
                    EventEditView(editing: nil, defaultDate: date)
                        .environment(store)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .symbolRenderingMode(.palette)
                        Text("添加")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(Color.appTint)
                }
            }

            if events.isEmpty {
                emptyEventsState
            } else {
                VStack(spacing: 10) {
                    ForEach(events) { event in
                        NavigationLink {
                            EventEditView(editing: event, defaultDate: date)
                                .environment(store)
                        } label: {
                            EventRow(event: event)
                                .environment(store)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        // iOS 26 液态玻璃：当日日程卡片
        .liquidGlassCard(
            cornerRadius: 20,
            borderColor: Color.separator.opacity(0.4),
            borderWidth: 0.5,
            shadowOpacity: 0.05
        )
    }

    private var emptyEventsState: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.stars")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color.tertiaryLabel)
            Text("这天还没有安排")
                .font(.subheadline)
                .foregroundStyle(Color.secondaryLabel)
            Text("添加日程、提醒或记事，让生活更有条理")
                .font(.caption)
                .foregroundStyle(Color.tertiaryLabel)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

#Preview {
    NavigationStack {
        DayDetailView(date: Date())
            .environment(EventStore.shared)
    }
}

#endif
