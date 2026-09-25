#if canImport(SwiftUI)
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
// N6 修复：本文件 5 处 AppLogger 最终走 os.Logger 的 OSLogMessage 插值；
// iOS 18 SDK 下 SwiftUI 不再 transitively 引入 os。
#if canImport(os)
import os
#endif

// MARK: - 设置页面 · iOS 原生形态（List + InsetGrouped）

struct SettingsView: View {
    @Environment(EventStore.self) private var store
    @Environment(\.openURL) private var openURL
    /// 用于回到前台时重新读一次通知授权状态（用户可能刚去系统设置里开过）
    @Environment(\.scenePhase) private var scenePhase

    // —— 通知 / 导入状态
    @State private var notifStatus: NotificationAuthStatus = .unavailable
    @State private var showImportPicker = false
    @State private var importingFileType: ImportedFileType = .ics
    @State private var importedResult: ImportMergeResult?
    @State private var showImportResult = false
    @State private var showClearConfirm = false
    @State private var toast: ToastMessage? = nil
    @State private var conflictPolicy: ImportConflictPolicy = .keepLatest
    @State private var showConflictPolicy = false
    // 系统导入
    @State private var isImportingSystem = false
    @State private var importingSystemSource: SystemImportSource = .systemCalendar
    /// 联系人生日是否按农历每年（跨启动保留）。
    /// 旧实现是 `@State`：每次冷启复位为 false，而用户往往"导入一次就不再想这事"，
    /// 于是这个偏好等于设不上。
    @AppStorage("Lunisolar.contactsImport.lunarAnnually") private var importLunarToggle = false
    // 外观
    @AppStorage("Lunisolar.appearance") private var appearanceSelection: AppAppearance = .system
    /// 每周起始日（Calendar weekday 语义：1=周日，2=周一；默认周日起始，保持既有用户布局）
    @AppStorage("Lunisolar.weekStart") private var weekStart: Int = 1
    @AppStorage("Lunisolar.liveActivity.enabled") private var liveActivityEnabled: Bool = true
    /// 头部卡的「AI 日历助手」入口（此前误接到「帮助与说明」文档，点了等于没反应）
    @State private var showAIAssistant = false

    /// 节日自适应强调色（与月/日视图同规则）
    private var accent: Color {
        let today = Date()
        let fs = FestivalManager.festivals(on: today, lunar: today.lunar)
        return fs.first.map { Color(hex: $0.accentHex) } ?? Color.appTint
    }

    var body: some View {
        // 不再自包 NavigationStack：push 场景继承外层导航（返回箭头天然存在）；
        // sheet 场景由调用方补包。inline 标题消除 large title 的头部大留白，贴近 iOS 原生设置页。
        List {
            Section {
                QingheSettingsHeroCard(
                    eventCount: store.events.count,
                    version: appVersionString,
                    // 打开 AI 助手（此前误接到「帮助与说明」文档——标签写 AI 却弹帮助，
                    // 用户感受为「点了没什么反应」）
                    onAI: { showAIAssistant = true }
                )
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 10, trailing: 16))
                .listRowBackground(Color.clear)
            }

            appearanceSection
            #if canImport(UIKit)
            iconSection
            #endif
            notificationSection
            calendarLinkSection
            dataSection
            syncSection
            dangerSection
            AboutSectionView(docToShow: $docToShow)
        }
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #else
        // macOS 无 insetGrouped；产品目标为 iOS，macOS 仅作 SPM 单测宿主
        .listStyle(.automatic)
        #endif
        .festiveWallpaper(accent: accent)
        .navigationTitle(NSLocalizedString("设置", comment: ""))
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.navBar, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        #endif
        .tint(accent)
        .task {
            notifStatus = await EventService.shared.notificationAuthorizationStatus()
        }
        // 用户点「前往系统设置」开完通知回来时，本页不会重建、.task 也不会重跑 →
        // 状态栏一直显示「未开启」、「重新调度所有提醒」继续灰着，用户以为没生效。
        // 回到前台时重新读一次授权状态。
        .onChange(of: scenePhase, initial: false) { _, phase in
            guard phase == .active else { return }
            Task { notifStatus = await EventService.shared.notificationAuthorizationStatus() }
        }
        .modifier(ImportFileModifier(
            isPresented: $showImportPicker,
            fileType: importingFileType,
            onResult: { handleImportResult($0, fileType: importingFileType) }
        ))
        .alert(NSLocalizedString("导入结果", comment: ""), isPresented: $showImportResult) {
            Button(NSLocalizedString("好", comment: "")) {}
        } message: { importResultAlertMessage }
        .alert(NSLocalizedString("导入前：冲突处理策略", comment: ""), isPresented: $showConflictPolicy) {
            conflictPolicyAlertButtons
        } message: { conflictPolicyAlertMessage }
        .sheet(item: $docToShow) { kind in
            DocSheetView(kind: kind)
        }
        // AI 助手入口（设置头部卡）：AIAssistantView 自身已含 NavigationStack，勿再包一层
        .sheet(isPresented: $showAIAssistant) {
            AIAssistantView().environment(store)
        }
        .alert(NSLocalizedString("确认清空全部事件？", comment: ""), isPresented: $showClearConfirm) {
            Button(String(format: NSLocalizedString("清空全部 %d 条", comment: ""), store.events.count), role: .destructive) {
                // P0 收口：清空走 EventService（内部转 EventStore.clearAll，含通知取消 / 墓碑逻辑）
                let n = EventService.shared.clearAllEvents()
                toast = .init(kind: .success, text: String(format: NSLocalizedString("已清空 %d 条事件", comment: ""), n))
            }
            Button(NSLocalizedString("取消", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("此操作不可恢复。", comment: ""))
        }
        .overlay(alignment: .top) { toastOverlayContent }
        .animation(AppTheme.Motion.toast, value: toast)
    }

    private func storeCount(of type: EventType) -> Int {
        store.events.filter { $0.type == type }.count
    }

    // MARK: - 1. 外观

    private var appearanceSection: some View {
        Section {
            // 外观模式：原生菜单 Picker（跟随系统 / 浅色 / 深色）
            Picker(NSLocalizedString("外观模式", comment: ""), selection: $appearanceSelection) {
                ForEach(AppAppearance.allCases) { mode in
                    Label(mode.title, systemImage: mode.iconName).tag(mode)
                }
            }
            .pickerStyle(.menu)
            // 每周起始日（主流日历标配，切换即时生效于月视图网格与星期头）
            Picker(NSLocalizedString("每周起始日", comment: ""), selection: $weekStart) {
                Text(NSLocalizedString("周日", comment: "")).tag(1)
                Text(NSLocalizedString("周一", comment: "")).tag(2)
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier(AccessibilityID.settingsWeekStart)
        } header: {
            QingheSectionHeader(NSLocalizedString("外观", comment: ""), subtitle: "主题与日历显示方式")
        }
    }

    // MARK: - 1.5 App 图标（P2-9：手动切换主图标/春节限定）
    // UIKit only：UIApplication.setAlternateIconName 为 iOS API，macOS 无替代图标能力

    #if canImport(UIKit)
    private var iconSection: some View {
        Section {
            Picker(NSLocalizedString("App 图标", comment: ""), selection: .init(
                get: { AlternateIconManager.shared.current },
                set: { icon in
                    Task { await AlternateIconManager.shared.setIcon(icon) }
                }
            )) {
                ForEach(AlternateIconManager.Icon.allCases, id: \.self) { icon in
                    Label(icon.uiLabel, systemImage: icon == .springFestival ? "gift" : "app")
                        .tag(icon)
                }
            }
            .pickerStyle(.navigationLink)
        } header: {
            QingheSectionHeader(NSLocalizedString("图标", comment: ""),
                                subtitle: NSLocalizedString("主图标 / 春节限定自动切换", comment: ""))
        }
    }
    #endif

    // MARK: - 2. 通知

    private var notificationSection: some View {
        Section {
            HStack {
                Label(NSLocalizedString("通知权限", comment: ""), systemImage: "bell.badge")
                Spacer()
                Text(notifStatusText)
                    .font(AppTheme.Font.subheadline.weight(.semibold))
                    .foregroundStyle(notifStatus == .granted ? Color.systemGreen : Color.secondaryLabel)
            }

            if notifStatus == .denied {
                Button { openSystemSettings() } label: {
                    Label(NSLocalizedString("前往系统设置开启", comment: ""), systemImage: "arrow.up.right.square")
                }
            }

            if notifStatus == .notDetermined {
                Button {
                    Task { @MainActor in
                        let ok = await EventService.shared.requestNotificationAuthorization()
                        notifStatus = await EventService.shared.notificationAuthorizationStatus()
                        toast = ToastMessage(
                            kind: ok ? .success : .warning,
                            text: ok ? NSLocalizedString("通知权限已开启，可重新调度提醒", comment: "")
                                 : NSLocalizedString("未开启通知权限，提醒将不会送达", comment: "")
                        )
                    }
                } label: {
                    Label(NSLocalizedString("申请通知权限", comment: ""), systemImage: "bell.badge")
                }
            }

            Toggle(isOn: $liveActivityEnabled) {
                Label(NSLocalizedString("时间胶囊", comment: "Live Activities"), systemImage: "rectangle.topthird.inset.filled")
            }
            .tint(Color.appTint)
            // P1：设置变化即时反馈——关闭时立即结束所有活动，开启时给出提示
            .onChange(of: liveActivityEnabled) { _, newValue in
                if !newValue {
                    // P0 遗留收口：结束全部倒数日活动走 CountdownActivityController
                    CountdownActivityController.shared.endAllActivities()
                    toast = ToastMessage(kind: .warning,
                        text: NSLocalizedString("时间胶囊已关闭", comment: ""))
                } else {
                    toast = ToastMessage(kind: .success,
                        text: NSLocalizedString("时间胶囊已开启，添加倒数日后自动上岛", comment: ""))
                }
            }
        } header: {
            QingheSectionHeader(NSLocalizedString("提醒与时间胶囊", comment: ""), subtitle: "通知、日程与 Live Activity")
        } footer: {
            Text(NSLocalizedString("本地通知，权限未开启时提醒不会送达", comment: ""))
        }
    }

    // MARK: - 2.5 日历显示（二级入口，设计稿 04）

    private var calendarLinkSection: some View {
        Section {
            NavigationLink {
                CalendarDisplaySettingsView()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("日历", comment: ""))
                            .font(AppTheme.Font.bodyBold)
                            .foregroundStyle(Color.label)
                        Text(NSLocalizedString("农历、节气、节假日显示", comment: ""))
                            .font(AppTheme.Font.caption)
                            .foregroundStyle(Color.tertiaryLabel)
                    }
                } icon: {
                    Image(systemName: "calendar")
                        .foregroundStyle(Color.appTint)
                }
            }
        }
    }

    // MARK: - 3. 数据（导入 / 恢复 + 系统数据导入）

    private var dataSection: some View {
        Section {
            // 误触优化：整行点击 = 弹出格式选择菜单（不再"点行主体直接走 .ics"，
            // 避免想恢复 .json 却误触行主体进入错误导入流程）。
            Menu {
                Button {
                    importingFileType = .ics
                    showConflictPolicy = true
                } label: {
                    Label(NSLocalizedString("从 .ics 日历文件导入", comment: ""), systemImage: "calendar.badge.plus")
                }
                Button {
                    importingFileType = .json
                    showConflictPolicy = true
                } label: {
                    Label(NSLocalizedString("从 .json 备份恢复", comment: ""), systemImage: "externaldrive.badge.plus")
                }
            } label: {
                Label(NSLocalizedString("导入 / 恢复数据", comment: ""), systemImage: "square.and.arrow.down")
            }

            Button {
                importingSystemSource = .systemCalendar
                Task { await performSystemImport(source: .systemCalendar) }
            } label: {
                HStack {
                    Label(NSLocalizedString("从系统日历导入", comment: ""), systemImage: "calendar.badge.plus")
                    Spacer()
                    if isImportingSystem && importingSystemSource == .systemCalendar {
                        ProgressView().scaleEffect(0.8)
                    }
                }
            }
            .disabled(isImportingSystem)

            Button {
                importingSystemSource = .contacts
                Task { await performSystemImport(source: .contacts) }
            } label: {
                HStack {
                    Label(NSLocalizedString("从联系人导入生日/纪念日", comment: ""), systemImage: "person.crop.circle.badge.plus")
                    Spacer()
                    if isImportingSystem && importingSystemSource == .contacts {
                        ProgressView().scaleEffect(0.8)
                    }
                }
            }
            .disabled(isImportingSystem)

            // 始终可见（去掉了 `importingSystemSource == .contacts || !store.events.isEmpty` 的门槛）：
            // `importingSystemSource` 只有**点过**联系人导入按钮才会变成 .contacts，因此全新用户
            // （0 事件）根本看不到这个开关 —— 而它必须在点按钮**之前**就能设，否则第一次导入
            // 必然按公历入库，恰恰是最需要它的那一次用错口径。
            Toggle(isOn: $importLunarToggle) {
                Label(NSLocalizedString("联系人生日按农历每年", comment: ""), systemImage: "moon.stars.fill")
            }
            .tint(Color.systemIndigo)
        } header: {
            QingheSectionHeader(NSLocalizedString("数据与同步", comment: ""), subtitle: "导入、恢复与系统数据")
        } footer: {
            Text(NSLocalizedString("从系统日历 / 联系人导入，重复导入不会产生副本；闰月生日会匹配平月同日", comment: ""))
        }
    }

    // MARK: - 4. iCloud 同步

    private var syncSection: some View {
        Section {
            #if canImport(CloudKit)
            if let co = store.syncCoordinator {
                Toggle(isOn: Binding(
                    get: { co.isEnabled },
                    // P0 遗留收口：开关切换走 AppLifecycleCoordinator（View 不直接驱动同步）
                    set: { newVal in AppLifecycleCoordinator.shared.setCloudSyncEnabled(newVal) }
                )) {
                    Label(NSLocalizedString("启用 iCloud 同步", comment: ""), systemImage: "icloud")
                }
                .tint(Color.systemBlue)

                HStack {
                    Text(NSLocalizedString("同步状态", comment: ""))
                    Spacer()
                    Text(syncStatusText(co.status))
                        .font(AppTheme.Font.subheadline.weight(.semibold))
                        .foregroundStyle(syncStatusColor(co.status))
                }

                if let result = co.lastResult {
                    HStack {
                        Text(NSLocalizedString("最近同步", comment: ""))
                        Spacer()
                        Text(syncResultSummary(result))
                            .font(AppTheme.Font.subheadline)
                            .foregroundStyle(Color.secondaryLabel)
                    }
                    HStack {
                        Text(NSLocalizedString("推送 / 拉取", comment: ""))
                        Spacer()
                        Text("↑ \(result.pushed)   ↓ \(result.pulled)")
                            .font(AppTheme.Font.subheadline.weight(.semibold))
                            .foregroundStyle(Color.label)
                    }
                }

                Button {
                    // P0 遗留收口：立即同步走 AppLifecycleCoordinator（含日志与通知重排）
                    Task { @MainActor in
                        if let error = await AppLifecycleCoordinator.shared.syncNow() {
                            toast = .init(kind: .error, text: String(format: NSLocalizedString("同步失败：%@", comment: ""), syncErrorBrief(error)))
                        } else {
                            toast = .init(kind: .success, text: NSLocalizedString("同步完成", comment: ""))
                        }
                    }
                } label: {
                    HStack {
                        Label(NSLocalizedString("立即同步", comment: ""), systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        if case .inProgress = co.status {
                            ProgressView().scaleEffect(0.7)
                        }
                    }
                }
                .disabled(!co.isEnabled || isSyncing(co.status))
                .opacity((!co.isEnabled || isSyncing(co.status)) ? 0.45 : 1)
            } else {
                Toggle(isOn: Binding(
                    get: { false },
                    set: { newVal in
                        if newVal {
                            Task { @MainActor in await enableSyncFirstTime() }
                        }
                    }
                )) {
                    Label(NSLocalizedString("启用 iCloud 同步", comment: ""), systemImage: "icloud.slash")
                }
                .tint(Color.systemBlue)

                HStack {
                    Text(NSLocalizedString("同步状态", comment: ""))
                    Spacer()
                    Text(NSLocalizedString("未启用", comment: ""))
                        .font(AppTheme.Font.subheadline)
                        .foregroundStyle(Color.secondaryLabel)
                }
            }
            #else
            HStack {
                Image(systemName: "icloud.slash")
                    .foregroundStyle(Color.tertiaryLabel)
                Text("iCloud 同步不可用（当前平台未编译 CloudKit）")
                    .font(AppTheme.Font.subheadline)
                    .foregroundStyle(Color.secondaryLabel)
            }
            #endif

            // 高级数据设置（文档 #13：技术性设置从顶层下放，不与其他普通设置平级）
            Section {
                // docs #13：技术性操作下放高级数据设置，不与普通通知设置平级
                Button {
                    EventService.shared.rescheduleAllReminders()
                } label: {
                    Label(NSLocalizedString("重新调度所有提醒", comment: ""), systemImage: "arrow.clockwise.circle.fill")
                }
                .disabled(notifStatus != .granted)
                .opacity(notifStatus == .granted ? 1 : 0.45)

                Picker(NSLocalizedString("冲突处理", comment: ""), selection: $conflictPolicy) {
                    ForEach(ImportConflictPolicy.allCases, id: \.self) { p in
                        Text(p.title).tag(p)
                    }
                }
                .pickerStyle(.menu)
                statRow(label: NSLocalizedString("总事件数", comment: ""), value: "\(store.events.count)")
                statRow(label: NSLocalizedString("日程", comment: ""), value: "\(storeCount(of: .schedule))")
                statRow(label: NSLocalizedString("提醒", comment: ""), value: "\(storeCount(of: .reminder))")
                statRow(label: NSLocalizedString("记事", comment: ""), value: "\(storeCount(of: .note))")
                // P1-2 数据诚实化：明确黄历数据的来源与推导方式（非人工核验的权威库）
                Text(HuangliDBProvider.coverageDescription)
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(Color.secondaryLabel)
            } header: {
                Text(NSLocalizedString("高级数据设置", comment: ""))
            } footer: {
                Text(String(format: NSLocalizedString("同 ID 事件合并时的处理方式：%@", comment: ""), conflictPolicy.subtitle))
            }
        } header: {
            QingheSectionHeader(NSLocalizedString("iCloud 同步", comment: ""), subtitle: "多设备保持一致")
        } footer: {
            Text(NSLocalizedString("通过 iCloud 私有数据库在多台设备间同步", comment: ""))
        }
    }

    // MARK: - 7. 危险操作

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                showClearConfirm = true
            } label: {
                HStack {
                    Label(NSLocalizedString("删除所有数据", comment: ""), systemImage: "trash")
                    Spacer()
                    Text(String(format: NSLocalizedString("%d 项", comment: ""), store.events.count))
                        .font(AppTheme.Font.caption.weight(.semibold))
                        .foregroundStyle(Color.tertiaryLabel)
                }
            }
            .disabled(store.events.isEmpty)
            .opacity(store.events.isEmpty ? 0.45 : 1)
        } footer: {
            Text(NSLocalizedString("将永久删除所有日程、提醒和设置，此操作无法撤销", comment: ""))
        }
    }

    // MARK: - 8. 关于（iOS 系统标准"图标 + 名称 + 版本"三行居中样式）

    /// 文档 Sheet（帮助/反馈/隐私/协议）
    @State private var docToShow: DocKind?

    /// 从 Bundle 动态读取版本号（只显示 CFBundleShortVersionString，不带构建号；
    /// 版本递增规则：末位 +1，如 1.0.0 → 1.0.1 → 1.0.2）
    private var appVersionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    // MARK: - 通用行

    /// 设置页原生行：左 label 右 value（insetGrouped 列表内不自带内边距，直接使用）
    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(AppTheme.Font.body)
                .foregroundStyle(Color.label)
            Spacer()
            Text(value)
                .font(AppTheme.Font.subheadline.weight(.semibold))
                .foregroundStyle(Color.secondaryLabel)
                .lineLimit(1)
        }
    }

    // MARK: - Alert / Overlay

    @ViewBuilder
    private var importResultAlertMessage: some View {
        if let r = importedResult {
            Text(importSummaryText(r))
        } else {
            Text("导入完成")
        }
    }

    @ViewBuilder
    private var conflictPolicyAlertButtons: some View {
        ForEach(ImportConflictPolicy.allCases, id: \.self) { p in
            Button(conflictPolicyButtonTitle(p)) {
                conflictPolicy = p
                showImportPicker = true
            }
        }
        Button("取消", role: .cancel) {}
    }

    private func conflictPolicyButtonTitle(_ p: ImportConflictPolicy) -> String {
        p == conflictPolicy ? p.title + NSLocalizedString("（当前）", comment: "") : p.title
    }

    private var conflictPolicyAlertMessage: some View {
        // 拆成两行而不是在一个 key 里塞 `\n`：字符串目录里的换行键既难翻译也易出错
        VStack(alignment: .leading, spacing: 4) {
            Text(String(format: NSLocalizedString("当前策略：%@ · %@", comment: ""),
                        conflictPolicy.title, conflictPolicy.subtitle))
            Text(NSLocalizedString("选完策略后会打开 Files 选择文件。", comment: ""))
        }
    }

    @ViewBuilder
    private var toastOverlayContent: some View {
        if let t = toast {
            ToastBannerView(message: t)
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, 12)
                .padding(.horizontal, AppTheme.Spacing.md)
                .onAppear {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 2_200_000_000)
                        if toast?.id == t.id { toast = nil }
                    }
                }
        }
    }

    // MARK: - 文字辅助

    private var notifStatusText: String {
        switch notifStatus {
        case .granted:        return NSLocalizedString("已开启", comment: "")
        case .denied:         return NSLocalizedString("未开启", comment: "")
        case .notDetermined:  return NSLocalizedString("未请求", comment: "")
        case .unavailable:    return NSLocalizedString("不可用", comment: "")
        }
    }

    private func importSummaryText(_ r: ImportMergeResult) -> String {
        // 这些是 String 上下文的文案：必须显式 NSLocalizedString，
        // 否则无论 .strings 里有没有条目都不会被查表（英文界面永远显示中文）
        var parts: [String] = []
        if r.added > 0   { parts.append(String(format: NSLocalizedString("新增 %d", comment: ""), r.added)) }
        if r.updated > 0 { parts.append(String(format: NSLocalizedString("更新 %d", comment: ""), r.updated)) }
        if r.skipped > 0 { parts.append(String(format: NSLocalizedString("保留本地 %d", comment: ""), r.skipped)) }
        if r.invalid > 0 { parts.append(String(format: NSLocalizedString("无效 %d", comment: ""), r.invalid)) }
        let main = parts.isEmpty
            ? NSLocalizedString("没有可导入的事件", comment: "")
            : parts.joined(separator: " · ")
        if r.hasConflicts {
            let note = String(format: NSLocalizedString("（检测到 %d 条冲突，已按「%@」处理）", comment: ""),
                              r.updated + r.skipped, conflictPolicy.title)
            return main + "\n" + note
        }
        return main
    }

    // MARK: - 导入操作

    private func handleImportResult(_ result: Result<URL, Error>, fileType: ImportedFileType) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else {
                toast = .init(kind: .error, text: NSLocalizedString("导入失败：无权限读取该文件，请重新选择", comment: ""))
                importedResult = .init(invalid: 1)
                showImportResult = true
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                importedResult = .init(invalid: 1)
                showImportResult = true
                toast = .init(kind: .error, text: NSLocalizedString("导入失败：文件无法读取或编码不支持（请使用 UTF-8 文本）", comment: ""))
                return
            }
            let incoming: [CalendarEvent]
            switch fileType {
            case .ics:  incoming = DataPortability.importICS(content)
            case .json: incoming = DataPortability.importJSON(content)
            }
            // P0 收口：批量合并导入走 EventService（内部转 EventStore.merge）
            let r = EventService.shared.mergeImportedEvents(incoming, policy: conflictPolicy, skipSync: true)
            importedResult = r
            showImportResult = true
            // 新增/更新的事件如果是 reminder，需要被挂到 UNUserNotificationCenter。
            // 由于本 merge 是 O(N) 数据导入，用 rescheduleAllReminders（内部 cancelAll+重排）一次性刷新全局
            if r.added + r.updated > 0 {
                Task { @MainActor in
                    EventService.shared.rescheduleAllReminders()
                }
                toast = .init(kind: .success,
                              text: String(format: NSLocalizedString("导入完成：新增 %d · 更新 %d", comment: ""),
                                           r.added, r.updated))
            } else {
                toast = .init(kind: .warning, text: NSLocalizedString("未导入任何新事件（已有或数据无效）", comment: ""))
            }
        case .failure(let error):
            AppLogger.app.error("导入失败: \(error)")
            importedResult = .init(invalid: 1)
            showImportResult = true
            toast = .init(kind: .error,
                          text: String(format: NSLocalizedString("导入失败：%@", comment: ""),
                                       error.localizedDescription))
        }
    }

    // MARK: - 系统数据导入

    @MainActor
    private func performSystemImport(source: SystemImportSource) async {
        importingSystemSource = source
        isImportingSystem = true
        defer { isImportingSystem = false }

        #if canImport(EventKit) && canImport(Contacts)
        let provider: SystemImportProviding
        switch source {
        case .systemCalendar:
            provider = CalendarImportProvider()
        case .contacts:
            provider = ContactsImportProvider(asLunarAnnually: importLunarToggle)
        }
        #else
        let provider = StubSystemImportProvider(
            source: source, events: [], authorized: false
        )
        #endif

        let (events, failures) = await SystemImportAggregator.gather(providers: [provider])

        if events.isEmpty {
            if failures.contains(where: { if case .unauthorized = $0 { return true } else { return false } }) {
                toast = .init(kind: .error,
                              text: String(format: NSLocalizedString("%@ 权限未授权，请前往系统设置开启", comment: ""),
                                           source.displayName))
            } else if let f = failures.first {
                toast = .init(kind: .warning,
                              text: String(format: NSLocalizedString("导入失败：%@", comment: ""), "\(f)"))
            } else {
                toast = .init(kind: .warning,
                              text: String(format: NSLocalizedString("%@ 中没有可导入的事件", comment: ""),
                                           source.displayName))
            }
            return
        }

        // P0 收口：批量合并导入走 EventService（内部转 EventStore.merge）
        let r = EventService.shared.mergeImportedEvents(events, policy: conflictPolicy, skipSync: true)
        // 系统导入的结果用**行内 toast** 呈现（见下），不走「导入结果」alert：
        // 原先这里还给 importedResult 赋值、紧接着 showImportResult = false，
        // 那个状态永远不会被展示（死赋值），已移除；这行只做防御性收起。
        showImportResult = false
        // 系统导入成功后重排所有 pending 通知，把新增 reminder 挂到 UNUserNotificationCenter
        if r.added + r.updated > 0 {
            Task { @MainActor in
                EventService.shared.rescheduleAllReminders()
            }
            toast = .init(kind: .success,
                          text: String(format: NSLocalizedString("%@ 导入：新增 %d · 更新 %d", comment: ""),
                                       source.displayName, r.added, r.updated))
        } else {
            toast = .init(kind: .warning,
                          text: String(format: NSLocalizedString("%@ 无新增（已存在或被策略跳过）", comment: ""),
                                       source.displayName))
        }
    }

    private func openSystemSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
        #endif
    }

    // MARK: - iCloud 同步辅助
    //
    // P0 遗留收口：CloudKit 装配 / 开关切换 / 立即同步全部在 AppLifecycleCoordinator，
    // 这里只把首次开启的结果映射成 toast（文案与旧行为一致）。

    @MainActor
    private func enableSyncFirstTime() async {
        switch await AppLifecycleCoordinator.shared.enableCloudSync() {
        case .success:
            toast = .init(kind: .success, text: NSLocalizedString("iCloud 同步已开启", comment: ""))
        case .unsupportedBuild:
            toast = .init(kind: .error, text: NSLocalizedString("当前构建未启用 iCloud 权限，同步暂不可用", comment: ""))
        case .accountUnavailable:
            toast = .init(kind: .error, text: NSLocalizedString("iCloud 不可用：请在系统设置登录 iCloud 后重试", comment: ""))
        case .syncFailed:
            toast = .init(kind: .error, text: NSLocalizedString("iCloud 同步开启失败", comment: ""))
        }
    }

    private func syncStatusText(_ status: SyncStatus) -> String {
        switch status {
        case .idle: return NSLocalizedString("空闲", comment: "")
        case .inProgress(let dir):
            let arrow = dir == .push ? NSLocalizedString("↑推送", comment: "")
                       : dir == .pull ? NSLocalizedString("↓拉取", comment: "")
                                      : NSLocalizedString("↑↓双向", comment: "")
            return String(format: NSLocalizedString("同步中（%@）", comment: ""), arrow)
        case .succeeded: return NSLocalizedString("已同步", comment: "")
        case .failed(let e):
            return String(format: NSLocalizedString("失败：%@", comment: ""), syncErrorBrief(e))
        }
    }

    private func syncStatusColor(_ status: SyncStatus) -> Color {
        switch status {
        case .idle: return Color.secondaryLabel
        case .inProgress: return Color.systemBlue
        case .succeeded: return Color.systemGreen
        case .failed: return Color.systemRed
        }
    }

    private func syncErrorBrief(_ e: SyncError) -> String {
        switch e {
        case .notAvailable: return NSLocalizedString("iCloud 不可用", comment: "")
        case .networkUnavailable: return NSLocalizedString("无网络", comment: "")
        case .permissionDenied: return NSLocalizedString("权限被拒", comment: "")
        case .quotaExceeded: return NSLocalizedString("容量超限", comment: "")
        case .conflict: return NSLocalizedString("冲突", comment: "")
        case .recordNotFound: return NSLocalizedString("记录不存在", comment: "")
        case .invalidPayload: return NSLocalizedString("数据损坏", comment: "")
        case .rateLimited: return NSLocalizedString("请求过频", comment: "")
        case .unknown: return NSLocalizedString("未知错误", comment: "")
        }
    }

    private func syncErrorBrief(_ e: Error) -> String {
        if let se = e as? SyncError { return syncErrorBrief(se) }
        return e.localizedDescription
    }

    private func syncResultSummary(_ r: SyncResult) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        let time = f.string(from: r.finishedAt)
        let status = r.isSuccess
            ? NSLocalizedString("成功", comment: "")
            : NSLocalizedString("部分失败", comment: "")
        return "\(time) · \(status)"
    }

    private func isSyncing(_ status: SyncStatus) -> Bool {
        if case .inProgress = status { return true }
        return false
    }
}
#endif
