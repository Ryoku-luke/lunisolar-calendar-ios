import SwiftUI
import LunarCore

/// 选中日期详情卡片：公历大数字 + 农历干支 + 节日 + 天气 + 宜忌 + 今日安排 + CTA
struct SelectedDayCardView: View {
    let selectedDate: Date
    @Binding var isPanelExpanded: Bool
    let accent: Color
    @Environment(EventStore.self) private var store
    /// 天气结果（由天气文字块上报）：与并排的大图标共享，避免两者各拉一份、状态不一致
    @State private var weatherSnapshot: WeatherSnapshot?

    var body: some View {
        let huangli = HuangliGenerator.generate(for: selectedDate)
        let selLunar = selectedDate.lunar
        let todayFestivals = FestivalManager.festivals(on: selectedDate, lunar: selLunar)
        let todaysEvents = store.events(on: selectedDate)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.lg) {
                VStack(spacing: 2) {
                    Text("\(selectedDate.day)")
                        .font(AppTheme.Font.numeralXL)
                        .foregroundStyle(Self.foregroundForDayNumber(selectedDate))
                        .id(selectedDate.day)
                        .transition(.opacity.combined(with: .move(edge: .top).combined(with: .scale(scale: 0.92))))
                    Text(selectedDate.weekdaySymbol)
                        .font(AppTheme.Font.caption).foregroundStyle(Color.secondaryLabel)
                }
                .frame(width: 92).padding(.vertical, AppTheme.Spacing.md)
                .animation(AppTheme.Motion.screen, value: selectedDate.day)
                .background {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                        .fill(selectedDate.isToday ? Color.todayCapsule : Color.themeQuaternaryFill)
                    RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                        .stroke(accent.opacity(0.16), lineWidth: AppTheme.Stroke.hair)
                }

                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    if selLunar.isUnsupported {
                        Text("农历数据暂不支持此日期")
                            .font(AppTheme.Font.title3).foregroundStyle(Color.secondaryLabel)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(selLunar.yearGanZhi)年")
                                .font(AppTheme.Font.caption2.weight(.medium))
                                .foregroundStyle(Color.secondaryLabel)
                                .lineLimit(1)
                            Text("\(selLunar.monthName)\(selLunar.dayName)")
                                .font(AppTheme.Font.title3)
                                .foregroundStyle(Color.label)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        HStack(spacing: AppTheme.Spacing.xs) {
                            ChipLabel(title: "\(selLunar.yearGanZhi)", tint: Color.systemIndigo)
                            ChipLabel(title: selLunar.yearAnimal, systemImage: "pawprint.circle.fill", tint: Color.systemOrange)
                        }
                    }
                    if !todayFestivals.isEmpty {
                        HStack(spacing: AppTheme.Spacing.xs) {
                            ForEach(Array(todayFestivals.prefix(2)), id: \.name) { f in
                                // 用 localizedName（= L10n.str(name)）而不是 f.name ——
                                // 节日名的 key 早已存在，直接取原始中文会在英文界面显示中文
                                Text("\(f.emoji) \(f.localizedName)")
                                    .font(AppTheme.Font.caption).fontWeight(.bold)
                                    .capsuleTag(fill: Color(hex: f.accentHex).opacity(0.16),
                                                border: Color(hex: f.accentHex).opacity(0.25))
                                    .foregroundStyle(Color(hex: f.accentHex))
                                    // P2-7：节日标签 spring 入场（缩放+淡入）
                                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
                            }
                        }
                        .animation(AppTheme.Motion.screen, value: todayFestivals.map(\.name))
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 6) {
                    // 两者共享同一份天气结果：否则文字块重试成功、并排的图标仍停在占位云
                    WeatherIconView(selectedDate: selectedDate, sharedSnapshot: weatherSnapshot)
                    WeatherCardView(selectedDate: selectedDate, alignment: .trailing,
                                    onSnapshot: { weatherSnapshot = $0 })
                    Spacer(minLength: 0)
                }
            }

            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                yiBlock(huangli.yi, maxShown: 6)
                Divider().frame(maxHeight: .infinity)
                jiBlock(huangli.ji, maxShown: 6)
            }
            // minHeight + 不裁剪，替代原来的 `frame(height: 78) + clipped()`：
            // 超大辅助字号下 caption2 会被放大 2~3 倍，FlowLayout 换行后必然超过 78pt，
            // 硬裁会把后面的标签整段切掉且无法滚动查看。宁可卡片变高，也不丢内容。
            .frame(minHeight: 78, alignment: .top)
            .padding(.top, AppTheme.Spacing.sm)
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.bottom, AppTheme.Spacing.sm)
            .softChipBackground(material: .thinMaterial)
            .padding(.top, AppTheme.Spacing.md)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack {
                    Text("今日安排").font(AppTheme.Font.bodyBold).foregroundStyle(Color.label)
                    Spacer()
                    if !todaysEvents.isEmpty {
                        Text(String(format: NSLocalizedString("%d 项", comment: ""), todaysEvents.count)).font(AppTheme.Font.caption).foregroundStyle(Color.tertiaryLabel)
                    }
                }
                if todaysEvents.isEmpty {
                    HStack(spacing: AppTheme.Spacing.md) {
                        ZStack {
                            Circle()
                                .fill(accent.opacity(0.10))
                                .frame(width: 48, height: 48)
                            Image(systemName: "sparkles")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(accent)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "这一天很空闲")).font(AppTheme.Font.bodyBold).foregroundStyle(Color.label)
                            Text("去安排点美好的事吧 ✨").font(AppTheme.Font.caption).foregroundStyle(Color.tertiaryLabel)
                        }
                        Spacer()
                    }
                    .padding(AppTheme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .softChipBackground(material: .ultraThinMaterial)
                } else {
                    let slice = isPanelExpanded ? todaysEvents : Array(todaysEvents.prefix(3))
                    VStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(slice) { ev in
                            NavigationLink {
                                EventEditView(editing: ev, defaultDate: selectedDate).environment(store)
                            } label: {
                                EventRow(event: ev, compact: !isPanelExpanded).environment(store)
                            }.buttonStyle(.plain)
                                .pressableFeedback()
                                .eventQuickActions(ev)   // 长按：完成 / 删除
                        }
                    }
                    if todaysEvents.count > 3 {
                        Button {
                            withAnimation(AppTheme.Motion.screen) {
                                isPanelExpanded.toggle()
                            }
                        } label: {
                            HStack {
                                Spacer()
                                Text(isPanelExpanded ? String(localized: "收起") : String(format: NSLocalizedString("查看全部 %d 项 →", comment: ""), todaysEvents.count))
                                    .font(AppTheme.Font.caption.weight(.bold)).foregroundStyle(accent)
                                Spacer()
                            }
                            .frame(minHeight: AppTheme.Touch.chipHeight)
                            .background(Capsule().fill(accent.opacity(0.10)))
                            .contentShape(Capsule())
                        }.buttonStyle(.plain)
                            .pressableFeedback()
                    }
                }
            }
            .padding(.top, AppTheme.Spacing.md)

            VStack(spacing: AppTheme.Spacing.sm) {
                NavigationLink {
                    EventEditView(editing: nil, defaultDate: selectedDate).environment(store)
                } label: {
                    Label("新建日程", systemImage: "plus")
                }
                .buttonStyle(PrimaryActionButtonStyle(accent: accent))

                NavigationLink {
                    DayDetailView(date: selectedDate, embedsInNavigationStack: false).environment(store)
                } label: {
                    Label("查看黄历详情", systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(SecondaryActionButtonStyle(accent: accent))
            }
            .padding(.top, AppTheme.Spacing.md)
        }
        .padding(AppTheme.Spacing.lg)
        .glassCard(radius: 24, material: .regularMaterial,
                   tint: accent, shadow: AppTheme.Shadow.raised)
        // 选中日摘要卡的稳定锚点（UI 测试用；卡片全屏只渲染一次）
        .accessibilityIdentifier(AccessibilityID.selectedSummary)
    }

    private static func foregroundForDayNumber(_ date: Date) -> Color {
        if date.isToday { return Color.systemRed }
        if !Calendar(identifier: .gregorian).isDate(date, equalTo: Date(), toGranularity: .month) {
            return Color.tertiaryLabel
        }
        return Color.label
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
