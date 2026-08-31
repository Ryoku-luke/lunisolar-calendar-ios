#if canImport(SwiftUI)
import SwiftUI

struct DayDetailView: View {
    let date: Date
    @Environment(EventStore.self) private var store
    @State private var showAdd: Bool = false
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var isWide: Bool { hSizeClass == .regular }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.systemGroupedBackground.ignoresSafeArea()
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.navBar, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .tint(Color.appTint)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3).foregroundStyle(Color.appTint)
                            .touchTarget(min: AppTheme.Touch.minTarget)
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                EventEditView(editing: nil, defaultDate: date).environment(store)
            }
        }
    }

    private var headerCard: some View {
        let lunar = date.lunar
        let festivals = FestivalManager.festivals(on: date, lunar: lunar)
        let accent: Color = festivals.first.map { Color(hex: $0.accentHex) } ?? Color.appTint
        let huangli = HuangliGenerator.generate(for: date)
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
                .background(RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                    .fill(date.isToday ? Color.todayCapsule : Color.secondarySystemGroupedBackground))
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
                        .fill(Color.quaternarySystemFill))
                    .contentShape(Rectangle())
                }
            }
        }
        .padding(AppTheme.Spacing.xl)
        .modernCard(radius: AppTheme.Radius.xl, material: .thinMaterial,
                    border: accent.opacity(0.12), shadow: AppTheme.Shadow.card)
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
        .padding(AppTheme.Spacing.xl).modernCard()
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
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack {
                Label("当日安排", systemImage: "list.bullet.clipboard.fill")
                    .font(AppTheme.Font.title3).foregroundStyle(Color.label)
                Spacer()
                if !todays.isEmpty {
                    ChipLabel(title: "\(todays.count) 项", systemImage: "calendar.day.timeline.left", tint: Color.appTint)
                }
            }
            if todays.isEmpty {
                HStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: "sun.max")
                        .font(AppTheme.Font.numeralL).foregroundStyle(Color.systemYellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("今天很空闲").font(AppTheme.Font.bodyBold).foregroundStyle(Color.label)
                        Text("去安排点美好的事吧").font(AppTheme.Font.caption).foregroundStyle(Color.tertiaryLabel)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(AppTheme.Spacing.xl)
                .background(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                    .fill(Color.secondarySystemGroupedBackground))
            } else {
                VStack(spacing: AppTheme.Spacing.sm) {
                    ForEach(todays) { ev in
                        NavigationLink {
                            EventEditView(editing: ev, defaultDate: date).environment(store)
                        } label: {
                            EventRow(event: ev, compact: false).environment(store)
                        }.buttonStyle(.plain)
                    }
                }
            }
            Button {
                showAdd = true
            } label: {
                Label("新建\(EventType.schedule.displayTitle)", systemImage: "plus.circle.fill")
                    .font(AppTheme.Font.bodyBold).frame(maxWidth: .infinity)
                    .frame(minHeight: AppTheme.Touch.minTarget)
                    .background(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                        .fill(LinearGradient(colors: [Color.appTint, Color.appTint.opacity(0.82)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)))
                    .foregroundStyle(.white)
                    .shadow(color: Color.appTint.opacity(0.30), radius: 12, x: 0, y: 5)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        .padding(AppTheme.Spacing.xl).modernCard()
    }
}

extension Color {
    fileprivate static var systemGold: Color { Color.festiveGold }
}
#endif
