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
    @State private var importLunarToggle = false
    // 外观
    @AppStorage("Lunisolar.appearance") private var appearanceSelection: AppAppearance = .system
    /// 每周起始日（Calendar weekday 语义：1=周日，2=周一；默认周日起始，保持既有用户布局）
    @AppStorage("Lunisolar.weekStart") private var weekStart: Int = 1

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
            appearanceSection
            notificationSection
            dataSection
            syncSection
            conflictSection
            statisticsSection
            dangerSection
            aboutSection
        }
        .listStyle(.insetGrouped)
        .festiveWallpaper(accent: accent)
        .navigationTitle("设置")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.navBar, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        #endif
        .tint(accent)
        .task {
            notifStatus = await NotificationManager.shared.authorizationStatusAsync()
        }
        .modifier(ImportFileModifier(
            isPresented: $showImportPicker,
            fileType: importingFileType,
            onResult: { handleImportResult($0, fileType: importingFileType) }
        ))
        .alert("导入结果", isPresented: $showImportResult) {
            Button("好") {}
        } message: { importResultAlertMessage }
        .alert("导入前：冲突处理策略", isPresented: $showConflictPolicy) {
            conflictPolicyAlertButtons
        } message: { conflictPolicyAlertMessage }
        .alert("确认清空全部事件？", isPresented: $showClearConfirm) {
            Button(String(format: NSLocalizedString("清空全部 %d 条", comment: ""), store.events.count), role: .destructive) {
                let n = store.clearAll()
                toast = .init(kind: .success, text: String(format: NSLocalizedString("已清空 %d 条事件", comment: ""), n))
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作不可恢复。")
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
            Picker("外观模式", selection: $appearanceSelection) {
                ForEach(AppAppearance.allCases) { mode in
                    Label(mode.title, systemImage: mode.iconName).tag(mode)
                }
            }
            .pickerStyle(.menu)
            // 每周起始日（主流日历标配，切换即时生效于月视图网格与星期头）
            Picker("每周起始日", selection: $weekStart) {
                Text("周日").tag(1)
                Text("周一").tag(2)
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier(AccessibilityID.settingsWeekStart)
        } header: {
            Text("外观")
        }
    }

    // MARK: - 2. 通知

    private var notificationSection: some View {
        Section {
            HStack {
                Label("通知权限", systemImage: "bell.badge")
                Spacer()
                Text(notifStatusText)
                    .font(AppTheme.Font.subheadline.weight(.semibold))
                    .foregroundStyle(notifStatus == .granted ? Color.systemGreen : Color.secondaryLabel)
            }

            if notifStatus == .denied {
                Button { openSystemSettings() } label: {
                    Label("前往系统设置开启", systemImage: "arrow.up.right.square")
                }
            }

            if notifStatus == .notDetermined {
                // P3 UX：首次启动用户没申请过通知权限时，denied 分支（前往系统设置）
                // 不生效，下方"重排所有提醒"也因为 != granted 灰掉。用户卡在『啥也点不了』。
                // 新增显式按钮：直接调 NM.requestAuthorization 弹出系统权限弹窗。
                Button {
                    Task { @MainActor in
                        let ok = await NotificationManager.shared.requestAuthorization()
                        notifStatus = await NotificationManager.shared.authorizationStatusAsync()
                        toast = ToastMessage(
                            kind: ok ? .success : .warning,
                            text: ok ? "通知权限已开启，可重新调度提醒"
                                 : "未开启通知权限，提醒将不会送达"
                        )
                    }
                } label: {
                    Label("申请通知权限", systemImage: "bell.badge")
                }
            }

            Button {
                Task { await NotificationManager.shared.rescheduleAllReminders(in: store) }
            } label: {
                Label("重新调度所有提醒", systemImage: "arrow.clockwise.circle.fill")
            }
            // 允许在 .notDetermined 时按下（按钮文案本来就是"重新调度"，没权限时
            // 点下去啥也不会做，UX 不好；因此保留 granted-only 禁用，让用户先点上方
            // 新增的"申请通知权限"完成授权）。
            .disabled(notifStatus != .granted)
            .opacity(notifStatus == .granted ? 1 : 0.45)
        } header: {
            Text("提醒通知")
        } footer: {
            Text("本地通知，权限未开启时提醒不会送达")
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
                    Label("从 .ics 日历文件导入", systemImage: "calendar.badge.plus")
                }
                Button {
                    importingFileType = .json
                    showConflictPolicy = true
                } label: {
                    Label("从 .json 备份恢复", systemImage: "externaldrive.badge.plus")
                }
            } label: {
                Label("导入 / 恢复数据", systemImage: "square.and.arrow.down")
            }

            Button {
                importingSystemSource = .systemCalendar
                Task { await performSystemImport(source: .systemCalendar) }
            } label: {
                HStack {
                    Label("从系统日历导入", systemImage: "calendar.badge.plus")
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
                    Label("从联系人导入生日/纪念日", systemImage: "person.crop.circle.badge.plus")
                    Spacer()
                    if isImportingSystem && importingSystemSource == .contacts {
                        ProgressView().scaleEffect(0.8)
                    }
                }
            }
            .disabled(isImportingSystem)

            if importingSystemSource == .contacts || !store.events.isEmpty {
                Toggle(isOn: $importLunarToggle) {
                    Label("联系人生日按农历每年", systemImage: "moon.stars.fill")
                }
                .tint(Color.systemIndigo)
            }
        } header: {
            Text("数据")
        } footer: {
            Text("从系统日历 / 联系人导入，重复导入不会产生副本；闰月生日会匹配平月同日")
        }
    }

    // MARK: - 4. iCloud 同步

    private var syncSection: some View {
        Section {
            #if canImport(CloudKit)
            if let co = store.syncCoordinator {
                Toggle(isOn: Binding(
                    get: { co.isEnabled },
                    set: { newVal in handleSyncToggle(co, enabled: newVal) }
                )) {
                    Label("启用 iCloud 同步", systemImage: "icloud")
                }
                .tint(Color.systemBlue)

                HStack {
                    Text("同步状态")
                    Spacer()
                    Text(syncStatusText(co.status))
                        .font(AppTheme.Font.subheadline.weight(.semibold))
                        .foregroundStyle(syncStatusColor(co.status))
                }

                if let result = co.lastResult {
                    HStack {
                        Text("最近同步")
                        Spacer()
                        Text(syncResultSummary(result))
                            .font(AppTheme.Font.subheadline)
                            .foregroundStyle(Color.secondaryLabel)
                    }
                    HStack {
                        Text("推送 / 拉取")
                        Spacer()
                        Text("↑ \(result.pushed)   ↓ \(result.pulled)")
                            .font(AppTheme.Font.subheadline.weight(.semibold))
                            .foregroundStyle(Color.label)
                    }
                }

                Button {
                    Task { @MainActor in
                        do {
                            _ = try await co.syncBidirectional()
                            // 双向同步可能从 iCloud 拉回了新的 reminder 事件，需要重新排本地通知
                            await NotificationManager.shared.rescheduleAllReminders(in: store)
                            toast = .init(kind: .success, text: "同步完成")
                        } catch {
                            AppLogger.sync.error("立即同步失败：\(error)")
                            toast = .init(kind: .error, text: "同步失败：\(syncErrorBrief(error))")
                        }
                    }
                } label: {
                    HStack {
                        Label("立即同步", systemImage: "arrow.triangle.2.circlepath")
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
                            Task { @MainActor in await enableSyncForFirstTime() }
                        }
                    }
                )) {
                    Label("启用 iCloud 同步", systemImage: "icloud.slash")
                }
                .tint(Color.systemBlue)

                HStack {
                    Text("同步状态")
                    Spacer()
                    Text("未启用")
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
        } header: {
            Text("iCloud 同步")
        } footer: {
            Text("通过 iCloud 私有数据库在多台设备间同步")
        }
    }

    // MARK: - 5. 导入冲突策略

    private var conflictSection: some View {
        Section {
            Picker("冲突处理", selection: $conflictPolicy) {
                ForEach(ImportConflictPolicy.allCases, id: \.self) { p in
                    Text(p.title).tag(p)
                }
            }
            .pickerStyle(.menu)
        } header: {
            Text("导入冲突策略")
        } footer: {
            Text("同 ID 事件合并时的处理方式：\(conflictPolicy.subtitle)")
        }
    }

    // MARK: - 6. 数据统计

    private var statisticsSection: some View {
        Section {
            statRow(label: "总事件数", value: "\(store.events.count)")
            statRow(label: "日程", value: "\(storeCount(of: .schedule))")
            statRow(label: "提醒", value: "\(storeCount(of: .reminder))")
            statRow(label: "记事", value: "\(storeCount(of: .note))")
        } header: {
            Text("数据统计")
        }
    }

    // MARK: - 7. 危险操作

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                showClearConfirm = true
            } label: {
                HStack {
                    Label("清空全部事件", systemImage: "trash")
                    Spacer()
                    Text("\(store.events.count) 条")
                        .font(AppTheme.Font.caption.weight(.semibold))
                        .foregroundStyle(Color.tertiaryLabel)
                }
            }
            .disabled(store.events.isEmpty)
            .opacity(store.events.isEmpty ? 0.45 : 1)
        } footer: {
            Text("清空后无法恢复，请谨慎操作")
        }
    }

    // MARK: - 8. 关于

    private var aboutSection: some View {
        Section {
            statRow(label: "应用名称", value: "清和日历")
            statRow(label: "版本", value: appVersionString)
            statRow(label: "农历范围", value: "1900 – 2100")
        } header: {
            Text("关于")
        } footer: {
            Text("清和日历 © 2026 清和日历工作室。\n保留所有权利。")
        }
    }

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
        p == conflictPolicy ? p.title + "（当前）" : p.title
    }

    private var conflictPolicyAlertMessage: some View {
        Text("当前策略：\(conflictPolicy.title) · \(conflictPolicy.subtitle)\n选完策略后会打开 Files 选择文件。")
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
        case .granted:       return "已开启"
        case .denied:         return "未开启"
        case .notDetermined: return "未请求"
        case .unavailable:    return "不可用"
        }
    }

    private func importSummaryText(_ r: ImportMergeResult) -> String {
        var parts: [String] = []
        if r.added > 0   { parts.append("新增 \(r.added)") }
        if r.updated > 0 { parts.append("更新 \(r.updated)") }
        if r.skipped > 0 { parts.append("保留本地 \(r.skipped)") }
        if r.invalid > 0 { parts.append("无效 \(r.invalid)") }
        let main = parts.isEmpty ? "没有可导入的事件" : parts.joined(separator: " · ")
        if r.hasConflicts {
            return main + "\n（检测到 \(r.updated + r.skipped) 条冲突，已按「\(conflictPolicy.title)」处理）"
        }
        return main
    }

    // MARK: - 导入操作

    private func handleImportResult(_ result: Result<URL, Error>, fileType: ImportedFileType) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else {
                toast = .init(kind: .error, text: "导入失败：无权限读取该文件，请重新选择")
                importedResult = .init(invalid: 1)
                showImportResult = true
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                importedResult = .init(invalid: 1)
                showImportResult = true
                toast = .init(kind: .error, text: "导入失败：文件无法读取或编码不支持（请使用 UTF-8 文本）")
                return
            }
            let incoming: [CalendarEvent]
            switch fileType {
            case .ics:  incoming = DataPortability.importICS(content)
            case .json: incoming = DataPortability.importJSON(content)
            }
            let r = store.merge(incoming, policy: conflictPolicy, skipSync: true)
            importedResult = r
            showImportResult = true
            // 新增/更新的事件如果是 reminder，需要被挂到 UNUserNotificationCenter。
            // 由于本 merge 是 O(N) 数据导入，用 rescheduleAllReminders（内部 cancelAll+重排）一次性刷新全局
            if r.added + r.updated > 0 {
                Task { @MainActor in
                    await NotificationManager.shared.rescheduleAllReminders(in: store)
                }
                toast = .init(kind: .success,
                              text: "导入完成：新增 \(r.added) · 更新 \(r.updated)")
            } else {
                toast = .init(kind: .warning, text: "未导入任何新事件（已有或数据无效）")
            }
        case .failure(let error):
            AppLogger.app.error("导入失败: \(error)")
            importedResult = .init(invalid: 1)
            showImportResult = true
            toast = .init(kind: .error, text: "导入失败：\(error.localizedDescription)")
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

        let (events, failures) = await SystemImportAggregator.gather(
            providers: [provider],
            conflictPolicy: conflictPolicy
        )

        if events.isEmpty {
            if failures.contains(where: { if case .unauthorized = $0 { return true } else { return false } }) {
                toast = .init(kind: .error,
                              text: "\(source.displayName) 权限未授权，请前往系统设置开启")
            } else if let f = failures.first {
                toast = .init(kind: .warning, text: "导入失败：\(f)")
            } else {
                toast = .init(kind: .warning, text: "\(source.displayName) 中没有可导入的事件")
            }
            return
        }

        let r = store.merge(events, policy: conflictPolicy, skipSync: true)
        importedResult = r
        showImportResult = false
        // 系统导入成功后重排所有 pending 通知，把新增 reminder 挂到 UNUserNotificationCenter
        if r.added + r.updated > 0 {
            Task { @MainActor in
                await NotificationManager.shared.rescheduleAllReminders(in: store)
            }
            toast = .init(kind: .success,
                          text: "\(source.displayName) 导入：新增 \(r.added) · 更新 \(r.updated)")
        } else {
            toast = .init(kind: .warning,
                          text: "\(source.displayName) 无新增（已存在或被策略跳过）")
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

    @MainActor
    private func enableSyncForFirstTime() async {
        #if canImport(CloudKit)
        do {
            let provider = RealCloudKitProvider()
            let available = await provider.isAvailable
            guard available else {
                toast = .init(kind: .error, text: "iCloud 不可用：请登录 iCloud 并检查 entitlement 配置")
                return
            }
            let coordinator = EventSyncCoordinator(eventStore: store, provider: provider)
            coordinator.isEnabled = true
            store.syncCoordinator = coordinator
            UserDefaults.standard.set(true, forKey: "Lunisolar.sync.enabled")
            _ = try await coordinator.syncBidirectional()
            // 首次双向同步后：远端可能有新 reminder，需要排本地通知
            await NotificationManager.shared.rescheduleAllReminders(in: store)
            toast = .init(kind: .success, text: "iCloud 同步已开启")
        } catch {
            AppLogger.sync.error("首次开启 iCloud 同步失败：\(error)")
            toast = .init(kind: .error, text: "iCloud 同步开启失败")
        }
        #endif
    }

    @MainActor
    private func handleSyncToggle(_ co: EventSyncCoordinator, enabled: Bool) {
        co.isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "Lunisolar.sync.enabled")
        if enabled {
            Task { @MainActor in
                do {
                    _ = try await co.syncBidirectional()
                    // 开启同步后首次双向同步：远端新 reminder 需要排本地通知
                    await NotificationManager.shared.rescheduleAllReminders(in: store)
                } catch {
                    AppLogger.sync.warning("开启同步后首次同步失败：\(error)")
                }
            }
        }
    }

    private func syncStatusText(_ status: SyncStatus) -> String {
        switch status {
        case .idle: return "空闲"
        case .inProgress(let dir): return "同步中（\(dir == .push ? "↑推送" : dir == .pull ? "↓拉取" : "↑↓双向")）"
        case .succeeded: return "已同步"
        case .failed(let e): return "失败：\(syncErrorBrief(e))"
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
        case .notAvailable: return "iCloud 不可用"
        case .networkUnavailable: return "无网络"
        case .permissionDenied: return "权限被拒"
        case .quotaExceeded: return "容量超限"
        case .conflict: return "冲突"
        case .recordNotFound: return "记录不存在"
        case .invalidPayload: return "数据损坏"
        case .rateLimited: return "请求过频"
        case .unknown: return "未知错误"
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
        let status = r.isSuccess ? "成功" : "部分失败"
        return "\(time) · \(status)"
    }

    private func isSyncing(_ status: SyncStatus) -> Bool {
        if case .inProgress = status { return true }
        return false
    }
}
#endif
