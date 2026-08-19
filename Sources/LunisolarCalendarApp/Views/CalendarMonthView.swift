#if canImport(SwiftUI)
import SwiftUI

// MARK: - 月视图日历主界面

fileprivate struct DaySlot: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let inCurrentMonth: Bool
}

struct CalendarMonthView: View {
    @State private var currentMonth: Date = Date().firstDayOfMonth
    @State private var selectedDate: Date = Date()

    @Environment(EventStore.self) private var store

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                monthHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 6)

                Divider().padding(.horizontal, 16)

                WeekHeaderView()
                    .padding(.top, 4)

                calendarGrid
                    .padding(.horizontal, 8)
                    .padding(.top, 2)

                dayPreviewPanel
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
            }
            .background(Color.systemGroupedBackground.ignoresSafeArea())
            .overlay(alignment: .bottomTrailing) {
                NavigationLink {
                    EventEditView(
                        editing: nil,
                        defaultDate: selectedDate
                    )
                    .environment(store)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(Color.systemBlue)
                        .background(
                            Circle()
                                .fill(Color.systemBackground)
                                .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2)
                        )
                        .padding()
                        .padding(.trailing, 8)
                        .padding(.bottom, 16)
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    headerTitle
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentMonth = Date().firstDayOfMonth
                            selectedDate = Date()
                        }
                    } label: {
                        Text("今天")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.systemBlue)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentMonth = Date().firstDayOfMonth
                                selectedDate = Date()
                            }
                        } label: {
                            Label("回到今天", systemImage: "calendar.circle")
                        }
                        Divider()
                        NavigationLink {
                            SettingsView()
                                .environment(store)
                        } label: {
                            Label("设置", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    private var headerTitle: some View {
        Text("农历日历")
            .font(.headline)
            .foregroundStyle(Color.label)
    }

    private var monthHeader: some View {
        HStack {
            Text("\(currentMonth.year) 年 \(currentMonth.month) 月")
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.label)
            Spacer()
            HStack(spacing: 4) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentMonth = currentMonth.addingMonths(-1)
                    }
                } label: {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.secondary, Color.secondarySystemBackground)
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentMonth = currentMonth.addingMonths(1)
                    }
                } label: {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.secondary, Color.secondarySystemBackground)
                }
            }
        }
    }

    // MARK: - 日历网格

    private var calendarGrid: some View {
        let columns = [GridItem](repeating: GridItem(.flexible(), spacing: 2), count: 7)

        return LazyVGrid(columns: columns, spacing: 2) {
            ForEach(daysForMonth()) { slot in
                let date = slot.date
                let lunar = date.lunar
                let huangli = HuangliGenerator.generate(for: date)
                let hasEvs = store.hasEvents(on: date)
                let prio = store.highestPriority(on: date)

                DayCellView(
                    date: date,
                    isCurrentMonth: slot.inCurrentMonth,
                    isSelected: date.isSameDay(as: selectedDate),
                    isToday: date.isToday,
                    lunar: lunar,
                    huangli: huangli,
                    hasEvents: hasEvs,
                    eventPriority: prio
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedDate = date
                }
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondarySystemBackground)
        )
        .padding(.horizontal, 8)
    }

    private func daysForMonth() -> [DaySlot] {
        let first = currentMonth.firstDayOfMonth
        // weekday: 1=周日 ... 7=周六 -> 将周日列在首位，前置数量 = (weekday-1)
        let leading = first.weekday - 1
        let totalDays = currentMonth.daysInMonth
        var result: [DaySlot] = []

        for i in 0..<leading {
            let d = first.addingDays(-(leading - i))
            result.append(DaySlot(date: d, inCurrentMonth: false))
        }
        for i in 0..<totalDays {
            result.append(DaySlot(date: first.addingDays(i), inCurrentMonth: true))
        }
        var i = 0
        while result.count < 42 {
            result.append(DaySlot(date: first.addingDays(totalDays + i), inCurrentMonth: false))
            i += 1
        }
        return result
    }

    // MARK: - 底部预览面板

    private var dayPreviewPanel: some View {
        let huangli = HuangliGenerator.generate(for: selectedDate)
        let todaysEvents = store.events(on: selectedDate)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 2) {
                    Text("\(selectedDate.day)")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(selectedDate.isToday ? Color.systemRed : Color.label)
                    Text(selectedDate.weekdaySymbol)
                        .font(.caption)
                        .foregroundStyle(Color.secondaryLabel)
                }
                .frame(width: 64)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.secondarySystemBackground)
                )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(huangli.lunar.displayString)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.label)
                        if huangli.isAuspicious {
                            Label("宜", systemImage: "star.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(Color.auspicious))
                        }
                    }
                    HStack(spacing: 4) {
                        Text("冲煞")
                            .font(.caption)
                            .foregroundStyle(Color.secondaryLabel)
                        Text(huangli.displayChongSha)
                            .font(.caption)
                            .foregroundStyle(Color.label)
                    }
                    HStack(spacing: 4) {
                        Text("五行")
                            .font(.caption)
                            .foregroundStyle(Color.secondaryLabel)
                        Text(huangli.wuXing)
                            .font(.caption)
                            .foregroundStyle(Color.label)
                    }
                }
                Spacer()
            }

            if !todaysEvents.isEmpty {
                VStack(spacing: 4) {
                    ForEach(todaysEvents.prefix(2)) { ev in
                        EventRow(event: ev, compact: true)
                            .environment(store)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "moon.stars")
                        .foregroundStyle(Color.tertiaryLabel)
                    Text("今日暂无日程，保持轻松心情 ☕️")
                        .font(.footnote)
                        .foregroundStyle(Color.tertiaryLabel)
                    Spacer()
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
            }

            HStack(spacing: 8) {
                NavigationLink {
                    DayDetailView(date: selectedDate)
                        .environment(store)
                } label: {
                    HStack {
                        Spacer()
                        Text("查看详情")
                            .font(.footnote.weight(.semibold))
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.systemBlue.opacity(0.12))
                    )
                    .foregroundStyle(Color.systemBlue)
                }

                NavigationLink {
                    EventEditView(editing: nil, defaultDate: selectedDate)
                        .environment(store)
                } label: {
                    HStack {
                        Image(systemName: "plus")
                        Text("新建日程")
                            .font(.footnote.weight(.semibold))
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.systemBlue)
                    )
                    .foregroundStyle(.white)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.secondarySystemBackground)
        )
    }
}

#Preview {
    CalendarMonthView()
        .environment(EventStore.shared)
}

#endif
