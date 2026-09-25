#if canImport(SwiftUI)
import SwiftUI
import LunarCore

struct DayDetailView: View {
    let date: Date
    @Environment(EventStore.self) private var store
    @State private var showAdd: Bool = false
    @Environment(\.horizontalSizeClass) private var hSizeClass
    /// 是否由本视图自行包一层 NavigationStack。
    /// iPhone push 进入 / iPad 右栏均复用外层导航上下文时传 false。
    private let embedsInNavigationStack: Bool

    init(date: Date, embedsInNavigationStack: Bool = true) {
        self.date = date
        self.embedsInNavigationStack = embedsInNavigationStack
    }

    private var isWide: Bool { hSizeClass == .regular }
    /// 节日自适应强调色：整页 tint、按钮、强调线都跟随它
    private var accent: Color {
        let fs = FestivalManager.festivals(on: date, lunar: date.lunar)
        return fs.first.map { Color(hex: $0.accentHex) } ?? Color.appTint
    }

    var body: some View {
        if embedsInNavigationStack {
            NavigationStack { detailContent }
        } else {
            detailContent
        }
    }

    private var detailContent: some View {
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
            // 统一节日壁纸（替代内联 DayDetailBackground，全应用同一视觉语言）
            .festiveWallpaper(accent: accent)
            .navigationTitle(date.weekdaySymbol)
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.navBar, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .platformTopBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3).foregroundStyle(accent)
                            .touchTarget(min: AppTheme.Touch.minTarget)
                    }
                    .accessibilityLabel("新建日程")
                    .accessibilityIdentifier(AccessibilityID.dayDetailNewEvent)
                    .pressableFeedback()
                }
            }
            #endif
            .tint(accent)
            .sheet(isPresented: $showAdd) {
                // EventEditView 不自包 NavigationStack（push 继承外层导航），sheet 场景由这里补包
                NavigationStack {
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
                    Text(date.formatted(.dateTime.year().month(.wide)))
                        .font(AppTheme.Font.caption).foregroundStyle(Color.secondaryLabel)
                        .contentTransition(.numericText())
                }
                .frame(width: 110).padding(.vertical, AppTheme.Spacing.lg)
                .background {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                        .fill(date.isToday ? Color.todayCapsule : Color.themeQuaternaryFill)
                    RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                        .stroke(accent.opacity(0.18), lineWidth: AppTheme.Stroke.hair)
                }
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    if lunar.isUnsupported {
                        // 越界（1900 前 / 2100 后）：农历不可用，隐藏农历行与干支/生肖
                        Text("农历数据暂不支持此日期")
                            .font(AppTheme.Font.title2).foregroundStyle(Color.secondaryLabel)
                    } else {
                        Text(lunar.displayString).font(AppTheme.Font.title2).foregroundStyle(Color.label)
                    }
                    if !festivals.isEmpty {
                        HStack(spacing: AppTheme.Spacing.xs) {
                            ForEach(Array(festivals.prefix(3)), id: \.name) { f in  // 数据源 id 保持原 name
                                Text("\(f.emoji) \(f.localizedName)")
                                    .font(AppTheme.Font.caption.weight(.bold))
                                    .capsuleTag(fill: Color(hex: f.accentHex).opacity(0.18),
                                                border: Color(hex: f.accentHex).opacity(0.25), hPad: 10, vPad: 5)
                                    .foregroundStyle(Color(hex: f.accentHex))
                            }
                        }
                    }
                    if !lunar.isUnsupported {
                        HStack(spacing: AppTheme.Spacing.xs) {
                            ChipLabel(title: lunar.yearGanZhi, tint: Color.systemIndigo, font: AppTheme.Font.caption)
                            ChipLabel(title: lunar.yearAnimal,
                                      systemImage: "pawprint.circle.fill",
                                      tint: Color.systemOrange, font: AppTheme.Font.caption)
                        }
                    }
                }
                Spacer()
            }
            // 文档 #16：第一屏只显示宜忌；冲煞/五行/纳音/神位折叠到"更多"
            DisclosureGroup {
                let rows: [(String, String, Color)] = [
                    (NSLocalizedString("冲煞", comment: ""), huangli.chongSha.isEmpty ? "—" : huangli.chongSha, Color.systemRed),
                    (NSLocalizedString("五行", comment: ""), huangli.wuXing.isEmpty ? "—" : huangli.wuXing, Color.systemBrown),
                    (NSLocalizedString("纳音", comment: ""), huangli.naYin.isEmpty ? "—" : huangli.naYin, Color.systemPurple),
                    (NSLocalizedString("喜神", comment: ""), huangli.xiShenDirection.isEmpty ? "—" : huangli.xiShenDirection, Color.systemPink),
                    (NSLocalizedString("财神", comment: ""), huangli.caiShenDirection.isEmpty ? "—" : huangli.caiShenDirection, Color.systemGold)
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
                        .softChipBackground(radius: AppTheme.Radius.md)
                        .contentShape(Rectangle())
                    }
                }
            } label: {
                Label("更多黄历", systemImage: "chevron.down.circle")
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(Color.secondaryLabel)
            }
            .tint(Color.appTint)
            // 节假日 / 调休 / 节气标记
            let holidayInfo = HolidayProvider.info(for: date)
            let termName = SolarTermProvider.termOn(date)
            if holidayInfo.type != .normal || termName != nil {
                HStack(spacing: AppTheme.Spacing.xs) {
                    if holidayInfo.type == .holiday {
                        ChipLabel(title: String(format: NSLocalizedString("休 %@", comment: ""), holidayInfo.name), systemImage: "sun.max.fill",
                                  tint: Color.systemGreen, font: AppTheme.Font.caption)
                    } else if holidayInfo.type == .workday {
                        ChipLabel(title: String(format: NSLocalizedString("班 %@", comment: ""), holidayInfo.name), systemImage: "briefcase.fill",
                                  tint: Color.systemOrange, font: AppTheme.Font.caption)
                    }
                    if let term = termName {
                        ChipLabel(title: term, systemImage: "leaf.fill",
                                  tint: Color.systemTeal, font: AppTheme.Font.caption)
                    }
                }
            }
            // 当日天气：嵌入日期卡内（日期卡片的空白处，仅显示选中日当天天气）
            WeatherCardView(selectedDate: date)
        }
        .padding(AppTheme.Spacing.xl)
        .glassCard(radius: AppTheme.Radius.xxl, material: .regularMaterial,
                   tint: accent, shadow: AppTheme.Shadow.card)
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
        .glassCard(radius: AppTheme.Radius.xl, material: .thinMaterial,
                   shadow: AppTheme.Shadow.card)
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
                    ChipLabel(title: String(format: NSLocalizedString("%d 项", comment: ""), todays.count), systemImage: "calendar.day.timeline.left", tint: accent)
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
                .softChipBackground(material: .ultraThinMaterial)
            } else {
                VStack(spacing: AppTheme.Spacing.sm) {
                    ForEach(todays) { ev in
                        NavigationLink {
                            EventEditView(editing: ev, defaultDate: date).environment(store)
                        } label: {
                            EventRow(event: ev, compact: false).environment(store)
                        }.buttonStyle(.plain)
                            .pressableFeedback()
                            .eventQuickActions(ev)   // 长按：完成 / 删除
                    }
                }
            }
            Button {
                showAdd = true
            } label: {
                Label(String(format: NSLocalizedString("新建%@", comment: ""), EventType.schedule.uiLabel), systemImage: "plus.circle.fill")
            }
            .buttonStyle(PrimaryActionButtonStyle(accent: accent))
        }
        .padding(AppTheme.Spacing.xl)
        .glassCard(radius: AppTheme.Radius.xl, material: .thinMaterial,
                   tint: accent.opacity(0.6), shadow: AppTheme.Shadow.card)
    }
}

extension Color {
    fileprivate static var systemGold: Color { Color.festiveGold }
}
#endif
