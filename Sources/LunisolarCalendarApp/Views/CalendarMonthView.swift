#if canImport(SwiftUI)
import SwiftUI

fileprivate final class _Box<T>: @unchecked Sendable { var value: T; init(_ v: T) { self.value = v } }
fileprivate struct DaySlot: Identifiable, Hashable {
    let id = UUID(); let date: Date; let inCurrentMonth: Bool
}

struct CalendarMonthView: View {
    @State private var currentMonth: Date = Date().gregorianFirstDayOfMonth
    @Binding private var selectedDate: Date
    @State private var isPanelExpanded: Bool = false
    @Environment(EventStore.self) private var store
    @Environment(\.horizontalSizeClass) private var hSizeClass

    init(selectedDate: Binding<Date>? = nil) {
        if let binding = selectedDate {
            self._selectedDate = binding
        } else {
            let localBox = _Box(Date())
            self._selectedDate = Binding(get: { localBox.value }, set: { localBox.value = $0 })
        }
    }

    private var isIPadSplit: Bool { hSizeClass == .regular }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.systemGroupedBackground.ignoresSafeArea()
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        monthHeader(containerWidth: geo.size.width)
                            .padding(.horizontal, AppTheme.Spacing.xl)
                            .padding(.top, 12).padding(.bottom, AppTheme.Spacing.sm)
                        calendarShell(containerWidth: geo.size.width)
                            .padding(.horizontal, AppTheme.Spacing.md)
                        if !isIPadSplit {
                            selectedDayCard
                                .padding(.horizontal, AppTheme.Spacing.md)
                                .padding(.top, AppTheme.Spacing.md)
                                .padding(.bottom, AppTheme.Spacing.xxl)
                        }
                    }.frame(maxWidth: .infinity)
                }
                if !isIPadSplit {
                    VStack { Spacer(); HStack {
                        Spacer()
                        NavigationLink {
                            EventEditView(editing: nil, defaultDate: selectedDate).environment(store)
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.white)
                                .frame(width: 56, height: 56)
                                .background(Circle().fill(
                                    LinearGradient(colors: [Color.appTint, Color.appTint.opacity(0.8)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing)))
                                .shadow(color: Color.appTint.opacity(0.35), radius: 14, x: 0, y: 6)
                                .overlay(Circle().stroke(Color.white.opacity(0.28), lineWidth: AppTheme.Stroke.hair))
                        }
                        .padding(.trailing, AppTheme.Spacing.xl)
                        .padding(.bottom, AppTheme.Spacing.xl)
                    }}
                }
            }
            .navigationTitle("日历")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.navBar, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            currentMonth = Date().gregorianFirstDayOfMonth; selectedDate = Date()
                        }
                    } label: { Label("今天", systemImage: "sparkles").font(.subheadline.weight(.semibold)) }
                        .tint(Color.appTint)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            currentMonth = Date().gregorianFirstDayOfMonth; selectedDate = Date()
                        } } label: { Label("回到今天", systemImage: "location.circle") }
                        Divider()
                        NavigationLink { SettingsView().environment(store) }
                            label: { Label("设置", systemImage: "gearshape") }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.title3).foregroundStyle(Color.secondaryLabel)
                    }
                }
            }
            .tint(Color.appTint)
        }
    }

    private func monthHeader(containerWidth: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.md) {
            Text("\(currentMonth.gregorianMonth)月")
                .font(AppTheme.Font.hero).foregroundStyle(Color.label)
            Text("\(currentMonth.gregorianYear)")
                .font(AppTheme.Font.title3).foregroundStyle(Color.tertiaryLabel)
            Spacer()
            HStack(spacing: AppTheme.Spacing.sm) {
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        currentMonth = currentMonth.gregorianAddingMonths(-1)
                    }
                } label: { chevronButton("chevron.left") }
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        currentMonth = currentMonth.gregorianAddingMonths(1)
                    }
                } label: { chevronButton("chevron.right") }
            }
        }
    }

    private func chevronButton(_ name: String) -> some View {
        Image(systemName: name).font(.title2.weight(.semibold)).foregroundStyle(Color.secondaryLabel)
            .frame(width: 40, height: 40)
            .background(Circle().fill(Color.secondarySystemGroupedBackground))
            .overlay(Circle().stroke(Color.separator.opacity(0.25), lineWidth: AppTheme.Stroke.hair))
    }

    private func calendarShell(containerWidth: CGFloat) -> some View {
        let slots = daysForMonth()
        var statsMap: [Date: (count: Int, prio: Priority?)] = [:]
        var huangliMap: [Date: HuangliDay] = [:]
        var lunarMap: [Date: LunarDate] = [:]
        for slot in slots {
            let d = slot.date
            let stats = store.eventStats(on: d)
            statsMap[d] = (stats.count, stats.priority)
            huangliMap[d] = HuangliGenerator.generate(for: d)
            lunarMap[d] = d.lunar
        }
        let columns = [GridItem](repeating: GridItem(.flexible(), spacing: 0), count: 7)
        return VStack(alignment: .leading, spacing: 0) {
            WeekHeaderView()
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(slots) { slot in
                    let d = slot.date
                    let st = statsMap[d] ?? (0, nil)
                    DayCellView(date: d, isCurrentMonth: slot.inCurrentMonth,
                                isSelected: d.isSameDay(as: selectedDate),
                                isToday: d.isToday,
                                lunar: lunarMap[d] ?? d.lunar,
                                huangli: huangliMap[d] ?? HuangliGenerator.generate(for: d),
                                hasEvents: st.count > 0, eventPriority: st.prio, eventCount: st.count)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) { selectedDate = d }
                    }
                }
            }
            .padding(.horizontal, isIPadSplit ? AppTheme.Spacing.lg : AppTheme.Spacing.md)
            .padding(.bottom, AppTheme.Spacing.lg)
        }
        .padding(.top, AppTheme.Spacing.xs)
        .modernCard(radius: AppTheme.Radius.xl, material: .thinMaterial,
                    border: Color.separator.opacity(0.22), shadow: AppTheme.Shadow.card)
    }

    private func daysForMonth() -> [DaySlot] {
        let first = currentMonth.gregorianFirstDayOfMonth
        let leading = first.gregorianWeekday - 1
        let totalDays = currentMonth.gregorianDaysInMonth
        var result: [DaySlot] = []
        for i in 0..<leading {
            result.append(DaySlot(date: first.gregorianAddingDays(-(leading - i)), inCurrentMonth: false))
        }
        for i in 0..<totalDays {
            result.append(DaySlot(date: first.gregorianAddingDays(i), inCurrentMonth: true))
        }
        var i = 0
        while result.count < 42 {
            result.append(DaySlot(date: first.gregorianAddingDays(totalDays + i), inCurrentMonth: false))
            i += 1
        }
        return result
    }

    private var selectedDayCard: some View {
        let huangli = HuangliGenerator.generate(for: selectedDate)
        let selLunar = selectedDate.lunar
        let todayFestivals = FestivalManager.festivals(on: selectedDate, lunar: selLunar)
        let accent: Color = todayFestivals.first.map { Color(hex: $0.accentHex) } ?? Color.appTint
        let todaysEvents = store.events(on: selectedDate)

        return VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.lg) {
                VStack(spacing: 2) {
                    Text("\(selectedDate.day)")
                        .font(AppTheme.Font.numeralXL)
                        .foregroundStyle(selectedDate.isToday ? Color.systemRed : Color.label)
                    Text(selectedDate.weekdaySymbol)
                        .font(AppTheme.Font.caption).foregroundStyle(Color.secondaryLabel)
                }
                .frame(width: 92).padding(.vertical, AppTheme.Spacing.md)
                .background(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                    .fill(selectedDate.isToday ? Color.todayCapsule : Color.secondarySystemGroupedBackground))
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Text(selLunar.displayString).font(AppTheme.Font.title3).foregroundStyle(Color.label)
                    if !todayFestivals.isEmpty {
                        HStack(spacing: AppTheme.Spacing.xs) {
                            ForEach(Array(todayFestivals.prefix(2)), id: \.name) { f in
                                Text("\(f.emoji) \(f.name)")
                                    .font(AppTheme.Font.caption).fontWeight(.bold)
                                    .capsuleTag(fill: Color(hex: f.accentHex).opacity(0.16),
                                                border: Color(hex: f.accentHex).opacity(0.25))
                                    .foregroundStyle(Color(hex: f.accentHex))
                            }
                        }
                    }
                    HStack(spacing: AppTheme.Spacing.xs) {
                        ChipLabel(title: "\(selLunar.yearGanZhi)", tint: Color.systemIndigo)
                        ChipLabel(title: selLunar.yearAnimal, systemImage: "pawprint.circle.fill", tint: Color.systemOrange)
                        if huangli.isAuspicious {
                            ChipLabel(title: "黄道吉日", systemImage: "sparkles", tint: Color.auspicious)
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            if huangli.isAuspicious || !huangli.yi.isEmpty || !huangli.ji.isEmpty {
                HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                    yiBlock(huangli.yi, maxShown: 6)
                    Divider().frame(maxHeight: .infinity)
                    jiBlock(huangli.ji, maxShown: 6)
                }
                .padding(AppTheme.Spacing.md)
                .background(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                    .fill(Color.secondarySystemGroupedBackground))
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack {
                    Text("今日安排").font(AppTheme.Font.bodyBold).foregroundStyle(Color.label)
                    Spacer()
                    if !todaysEvents.isEmpty {
                        Text("\(todaysEvents.count) 项").font(AppTheme.Font.caption).foregroundStyle(Color.tertiaryLabel)
                    }
                }
                if todaysEvents.isEmpty {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        Image(systemName: "cup.and.saucer").foregroundStyle(Color.tertiaryLabel)
                        Text("这一天很空闲，去安排点美好的事吧")
                            .font(AppTheme.Font.caption).foregroundStyle(Color.tertiaryLabel)
                        Spacer()
                    }.padding(.vertical, AppTheme.Spacing.md)
                } else {
                    let slice = isPanelExpanded ? todaysEvents : Array(todaysEvents.prefix(3))
                    VStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(slice) { ev in
                            NavigationLink {
                                EventEditView(editing: ev, defaultDate: selectedDate).environment(store)
                            } label: {
                                EventRow(event: ev, compact: !isPanelExpanded).environment(store)
                            }.buttonStyle(.plain)
                        }
                    }
                    if todaysEvents.count > 3 {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                isPanelExpanded.toggle()
                            }
                        } label: {
                            HStack {
                                Spacer()
                                Text(isPanelExpanded ? "收起" : "查看全部 \(todaysEvents.count) 项 →")
                                    .font(AppTheme.Font.caption.weight(.bold)).foregroundStyle(accent)
                                Spacer()
                            }
                            .padding(.vertical, AppTheme.Spacing.sm)
                            .background(Capsule().fill(accent.opacity(0.10)))
                        }.buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: AppTheme.Spacing.sm) {
                NavigationLink {
                    DayDetailView(date: selectedDate).environment(store)
                } label: {
                    Label("查看黄历详情", systemImage: "doc.text.magnifyingglass")
                        .font(AppTheme.Font.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.Spacing.md)
                        .background(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                            .fill(Color.secondarySystemGroupedBackground))
                        .foregroundStyle(Color.label)
                }
                NavigationLink {
                    EventEditView(editing: nil, defaultDate: selectedDate).environment(store)
                } label: {
                    Label("新建日程", systemImage: "plus.circle.fill")
                        .font(AppTheme.Font.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.Spacing.md)
                        .background(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                            .fill(LinearGradient(colors: [accent, accent.opacity(0.82)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing)))
                        .foregroundStyle(.white)
                        .shadow(color: accent.opacity(0.28), radius: 10, x: 0, y: 4)
                }
            }
        }
        .padding(AppTheme.Spacing.xl)
        .modernCard(radius: 26, material: .thinMaterial,
                    border: Color.separator.opacity(0.22), shadow: AppTheme.Shadow.raised)
    }

    private func yiBlock(_ yi: [String], maxShown: Int) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: 4) {
                Text("宜").font(AppTheme.Font.caption2.weight(.bold))
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.systemGreen)).foregroundStyle(.white)
                Text("宜做").font(AppTheme.Font.caption.weight(.semibold)).foregroundStyle(Color.secondaryLabel)
            }
            TagCloudView(tags: Array(yi.prefix(maxShown)), tint: Color.systemGreen)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func jiBlock(_ ji: [String], maxShown: Int) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: 4) {
                Text("忌").font(AppTheme.Font.caption2.weight(.bold))
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.systemRed)).foregroundStyle(.white)
                Text("勿做").font(AppTheme.Font.caption.weight(.semibold)).foregroundStyle(Color.secondaryLabel)
            }
            TagCloudView(tags: Array(ji.prefix(maxShown)), tint: Color.systemRed)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

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
    }
}

#Preview { CalendarMonthView().environment(EventStore.shared) }
#Preview("iPad Split") { iPadRootView().environment(EventStore.shared) }

#endif
