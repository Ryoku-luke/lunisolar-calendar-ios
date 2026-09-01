#if canImport(SwiftUI)
import SwiftUI

struct DayDetailView: View {
    let date: Date
    @Environment(EventStore.self) private var store
    @State private var showAdd: Bool = false
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var isWide: Bool { hSizeClass == .regular }
    /// 节日自适应强调色：整页 tint、按钮、强调线都跟随它
    private var accent: Color {
        let fs = FestivalManager.festivals(on: date, lunar: date.lunar)
        return fs.first.map { Color(hex: $0.accentHex) } ?? Color.appTint
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // 节日染色背景（与月视图同款柔和渐变）
                DayDetailBackground(accent: accent).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: AppTheme.Spacing.section) {
                        headerCard.padding(.top, AppTheme.Spacing.lg)
                        almanacCard
                        eventsCard
                        Color.clear.frame(height: AppTheme.Spacing.xxl)
                    }
                    .padding(.horizontal, isWide ? AppTheme.Spacing.xxl : AppTheme.Spacing.lg)
                    .frame(maxWidth: isWide ? 760 : .infinity)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(date.weekdaySymbol)
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.navBar, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3).foregroundStyle(accent)
                            .touchTarget(min: AppTheme.Touch.minTarget)
                    }
                    .pressableFeedback()
                }
            }
            #endif
            .tint(accent)
            .sheet(isPresented: $showAdd) {
                EventEditView(editing: nil, defaultDate: date).environment(store)
            }
        }
    }

    private var headerCard: some View {
        let lunar = date.lunar
        let festivals = FestivalManager.festivals(on: date, lunar: lunar)
        let huangli = HuangliGenerator.generate(for: date)
        let accent = self.accent
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.xl) {
                VStack(spacing: 2) {
                    Text("\(date.day)")
                        .font(AppTheme.Font.numeralXL)
                        .foregroundStyle(date.isToday ? Color.systemRed : Color.label)
                    Text("\(date.gregorianYear) 年 \(date.gregorianMonth) 月")
                        .font(AppTheme.Font.caption).foregroundStyle(Color.secondaryLabel)
                }
                .frame(width: 110).padding(.vertical, AppTheme.Spacing.lg)
                .background {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                        .fill(date.isToday ? Color.todayCapsule : Color.themeQuaternaryFill)
                    RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                        .stroke(accent.opacity(0.18), lineWidth: AppTheme.Stroke.hair)
                }
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Text(lunar.displayString).font(AppTheme.Font.title2).foregroundStyle(Color.label)
                    if !festivals.isEmpty {
                        HStack(spacing: AppTheme.Spacing.xs) {
                            ForEach(Array(festivals.prefix(3)), id: \.name) { f in
                                Text("\(f.emoji) \(f.name)")
                                    .font(AppTheme.Font.caption.weight(.bold))
                                    .capsuleTag(fill: Color(hex: f.accentHex).opacity(0.18),
                                                border: Color(hex: f.accentHex).opacity(0.25), hPad: 10, vPad: 5)
                                    .foregroundStyle(Color(hex: f.accentHex))
                            }
                        }
                    }
                    HStack(spacing: AppTheme.Spacing.xs) {
                        ChipLabel(title: lunar.yearGanZhi, tint: Color.systemIndigo, font: AppTheme.Font.caption)
                        ChipLabel(title: lunar.yearAnimal,
                                  systemImage: "pawprint.circle.fill",
                                  tint: Color.systemOrange, font: AppTheme.Font.caption)
                    }
                }
                Spacer()
            }
            let rows: [(String, String, Color)] = [
                ("冲煞", huangli.chongSha.isEmpty ? "—" : huangli.chongSha, Color.systemRed),
                ("五行", huangli.wuXing.isEmpty ? "—" : huangli.wuXing, Color.systemBrown),
                ("纳音", huangli.naYin.isEmpty ? "—" : huangli.naYin, Color.systemPurple),
                ("喜神", huangli.xiShenDirection.isEmpty ? "—" : huangli.xiShenDirection, Color.systemPink),
                ("财神", huangli.caiShenDirection.isEmpty ? "—" : huangli.caiShenDirection, Color.systemGold)
            ]
            HStack(spacing: AppTheme.Spacing.xs) {
                ForEach(rows, id: \.0) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.0).font(AppTheme.Font.caption2).foregroundStyle(Color.tertiaryLabel)
                        Text(item.1).font(AppTheme.Font.caption.weight(.semibold))
                            .foregroundStyle(item.2).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppTheme.Spacing.sm)
                    .padding(.vertical, AppTheme.Spacing.md)
                    .background(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .fill(.ultraThinMaterial))
                    .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .stroke(Color.separator.opacity(0.18), lineWidth: AppTheme.Stroke.hair))
                    .contentShape(Rectangle())
                }
            }
        }
        .padding(AppTheme.Spacing.xl)
        .liquidCard(radius: AppTheme.Radius.xxl, material: .regularMaterial,
                     tint: accent, shadow: AppTheme.Shadow.card, highlight: 0.12)
    }

    private var almanacCard: some View {
        let huangli = HuangliGenerator.generate(for: date)
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            HStack {
                Label("黄历宜忌", systemImage: "book.and.wrench.fill")
                    .font(AppTheme.Font.title3).foregroundStyle(Color.label)
                Spacer()
            }
            HStack(alignment: .top, spacing: AppTheme.Spacing.lg) {
                yiBlockFull(huangli.yi)
                Divider().frame(maxHeight: .infinity)
                jiBlockFull(huangli.ji)
            }
        }
        .padding(AppTheme.Spacing.xl)
        .liquidCard(radius: AppTheme.Radius.xl, material: .thinMaterial,
                     shadow: AppTheme.Shadow.card, highlight: 0.08)
    }

    private func yiBlockFull(_ yi: [String]) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: 6) {
                Text("宜").font(AppTheme.Font.caption2.weight(.bold))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.systemGreen)).foregroundStyle(.white)
                Text("适宜").font(AppTheme.Font.subheadline.weight(.semibold)).foregroundStyle(Color.secondaryLabel)
            }
            TagCloudView(tags: yi, tint: Color.systemGreen, font: AppTheme.Font.caption)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func jiBlockFull(_ ji: [String]) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: 6) {
                Text("忌").font(AppTheme.Font.caption2.weight(.bold))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.systemRed)).foregroundStyle(.white)
                Text("忌讳").font(AppTheme.Font.subheadline.weight(.semibold)).foregroundStyle(Color.secondaryLabel)
            }
            TagCloudView(tags: ji, tint: Color.systemRed, font: AppTheme.Font.caption)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var eventsCard: some View {
        let todays = store.events(on: date)
        let accent = self.accent
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack {
                Label("当日安排", systemImage: "list.bullet.clipboard.fill")
                    .font(AppTheme.Font.title3).foregroundStyle(Color.label)
                Spacer()
                if !todays.isEmpty {
                    ChipLabel(title: "\(todays.count) 项", systemImage: "calendar.day.timeline.left", tint: accent)
                }
            }
            if todays.isEmpty {
                HStack(spacing: AppTheme.Spacing.md) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [accent.opacity(0.22), accent.opacity(0.06)],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: 52, height: 52)
                        Image(systemName: "sparkles")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(accent)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("今天很空闲").font(AppTheme.Font.bodyBold).foregroundStyle(Color.label)
                        Text("去安排点美好的事吧 ✨").font(AppTheme.Font.caption).foregroundStyle(Color.tertiaryLabel)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(AppTheme.Spacing.xl)
                .background(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                    .fill(.ultraThinMaterial))
                .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                    .stroke(Color.separator.opacity(0.18), lineWidth: AppTheme.Stroke.hair))
            } else {
                VStack(spacing: AppTheme.Spacing.sm) {
                    ForEach(todays) { ev in
                        NavigationLink {
                            EventEditView(editing: ev, defaultDate: date).environment(store)
                        } label: {
                            EventRow(event: ev, compact: false).environment(store)
                        }.buttonStyle(.plain)
                            .pressableFeedback()
                    }
                }
            }
            Button {
                showAdd = true
            } label: {
                Label("新建\(EventType.schedule.uiLabel)", systemImage: "plus.circle.fill")
                    .font(AppTheme.Font.bodyBold).frame(maxWidth: .infinity)
                    .frame(minHeight: AppTheme.Touch.minTarget)
                    .background {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                            .fill(LinearGradient(colors: [accent, accent.opacity(0.82)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                        RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                            .stroke(Color.white.opacity(0.24), lineWidth: AppTheme.Stroke.hair)
                    }
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                            .fill(LinearGradient(colors: [Color.white.opacity(0.22), .clear],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(height: 22).allowsHitTesting(false)
                            .offset(y: 2)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
                    }
                    .foregroundStyle(.white)
                    .shadow(color: accent.opacity(0.30), radius: 12, x: 0, y: 5)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
                .pressableFeedback()
        }
        .padding(AppTheme.Spacing.xl)
        .liquidCard(radius: AppTheme.Radius.xl, material: .thinMaterial,
                     tint: accent.opacity(0.6), shadow: AppTheme.Shadow.card, highlight: 0.08)
    }
}

/// DayDetail 背景：节⽇染色色斑 + 系统分组背景
private struct DayDetailBackground: View {
    let accent: Color
    var body: some View {
        ZStack {
            Color.systemGroupedBackground
            LinearGradient(colors: [accent.opacity(0.08), accent.opacity(0.02), .clear],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(accent.opacity(0.06))
                .frame(width: 360, height: 360).blur(radius: 72)
                .offset(x: -160, y: -200)
            Circle().fill(accent.opacity(0.05))
                .frame(width: 300, height: 300).blur(radius: 64)
                .offset(x: 140, y: 260)
        }
    }
}

extension Color {
    fileprivate static var systemGold: Color { Color.festiveGold }
}
#endif
