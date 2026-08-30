#if canImport(SwiftUI)
import SwiftUI
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
#if canImport(UIKit)
import UIKit
#endif
// N6 修复：本文件 5 处 AppLogger（setupCloudSync/warning/handleImportResult/error/enableSync
// 首次失败 + handleSyncToggle 的 warning）最终走 os.Logger 的 OSLogMessage 插值；
// 与 LunisolarCalendarApp 同样地，iOS 18 SDK 下 SwiftUI 不再 transitively 引入 os。
#if canImport(os)
import os
#endif

// MARK: - 设置页面

struct SettingsView: View {
    @Environment(EventStore.self) private var store
    @Environment(\.horizontalSizeClass) private var hSizeClass
    // A1-3: 替换 UIApplication.shared.open（iOS 13+ 在 SwiftUI 里
    // 建议用 @Environment(\.openURL)，Widget Extension / macOS/visionOS
    // 也兼容；UIApplication.shared 在 iOS 18+ 触发 deprecation 警告）
    @Environment(\.openURL) private var openURL
    @State private var notifStatus: NotificationAuthStatus = .unavailable
    @State private var showImportPicker = false
    @State private var importingFileType: ImportedFileType = .ics
    @State private var importedResult: ImportMergeResult?
    @State private var showImportResult = false
    @State private var shareURL: URL?
    @State private var showShareSheet = false
    @State private var showClearConfirm = false
    @State private var toast: ToastMessage? = nil
    // 冲突策略：导入时遇到同 id 事件怎么办
    @State private var conflictPolicy: ImportConflictPolicy = .keepLatest
    @State private var showConflictPolicy = false
    // 系统导入：日历 / 联系人
    @State private var isImportingSystem = false
    @State private var importingSystemSource: SystemImportSource = .systemCalendar
    @State private var importLunarToggle = false  // 联系人生日：true=按农历每年
    // 外观偏好：跟随系统 / 浅色 / 深色（与 App 入口 @AppStorage 同步）
    @AppStorage("Lunisolar.appearance") private var appearanceSelection: AppAppearance = .system

    var body: some View {
        baseForm
            .formStyle(.grouped)
            .frame(maxWidth: hSizeClass == .regular ? 720 : .infinity)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            // iOS 26：导航栏材质 + 全局 tint
            .toolbarBackground(.navBar, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .tint(Color.appTint)
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
            } message: {
                importResultAlertMessage
            }
            .alert("导入前：冲突处理策略", isPresented: $showConflictPolicy) {
                conflictPolicyAlertButtons
            } message: {
                conflictPolicyAlertMessage
            }
            .alert("确认清空全部事件？", isPresented: $showClearConfirm) {
                Button("清空全部 \(store.events.count) 条", role: .destructive) {
                    let n = store.clearAll()
                    toast = .init(kind: .success, text: "已清空 \(n) 条事件")
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("此操作不可恢复，强烈建议先点击「全量备份为 .json」导出备份。")
            }
            .overlay(alignment: .top) { toastOverlayContent }
            #if canImport(UIKit)
            .sheet(isPresented: $showShareSheet) {
                if let url = shareURL { ShareSheet(items: [url]) }
            }
            #endif
            .animation(.easeInOut(duration: 0.2), value: toast)
    }

    // MARK: - Alert / Overlay 闭包内容（独立 computed property，单独类型检查）

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

    @ViewBuilder
    private var conflictPolicyAlertMessage: some View {
        Text("当前策略：\(conflictPolicy.title) · \(conflictPolicy.subtitle)\n选完策略后会打开 Files 选择文件。")
    }

    @ViewBuilder
    private var toastOverlayContent: some View {
        if let t = toast {
            ToastBannerView(message: t)
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, 12)
                .onAppear {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 2_200_000_000)
                        if toast?.id == t.id { toast = nil }
                    }
                }
        }
    }

    /// 把主 Form 内容抽到独立 computed property，降低 body 的 modifier 链长度，
    /// 避免 SwiftUI 编译器"无法在合理时间内类型检查"超时。
    private var baseForm: some View {
        Form {
            // MARK: - 外观设置
            Section {
                Picker(selection: $appearanceSelection) {
                    ForEach(AppAppearance.allCases) { mode in
                        Label(mode.title, systemImage: mode.iconName)
                            .tag(mode)
                    }
                } label: {
                    Label("外观", systemImage: "circle.lefthalf.filled")
                        .foregroundStyle(Color.systemIndigo)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("外观")
            } footer: {
                Text("选择浅色、深色或跟随系统自动切换。")
            }

            // MARK: - 通知设置
            Section {
                HStack {
                    Image(systemName: "bell.badge")
                        .foregroundStyle(Color.systemOrange)
                    Text("通知权限")
                    Spacer()
                    Text(notifStatusText)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondaryLabel)
                }

                if notifStatus == .denied {
                    Button("前往系统设置开启") {
                        openSystemSettings()
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.systemBlue)
                }

                Button("重新调度所有提醒") {
                    Task {
                        await NotificationManager.shared.rescheduleAllReminders(in: store)
                    }
                }
                .disabled(notifStatus != .granted)
                .font(.subheadline)
            } header: {
                Text("提醒通知")
            }

            // MARK: - 数据管理
            Section {
                Button {
                    exportAsICS()
                } label: {
                    row(icon: "square.and.arrow.up", text: "导出为 .ics 日历文件")
                }

                Button {
                    exportAsCSV()
                } label: {
                    row(icon: "tablecells", text: "导出为 .csv 表格文件")
                }

                Button {
                    exportAsJSONBackup()
                } label: {
                    row(icon: "externaldrive.badge.checkmark", text: "全量备份为 .json",
                        tint: Color(hex: "#C41A1A"))
                }

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
                    row(icon: "square.and.arrow.down", text: "导入/恢复数据",
                        tint: Color(red: 0.25, green: 0.55, blue: 0.95))
                }
            } header: {
                Text("数据管理")
            } footer: {
                Text(".json 备份保留全部字段（含农历生日重复规则、通知状态、创建时间）；.ics/.csv 适合与其他日历互通。")
            }

            // MARK: - iCloud 同步
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
                            .font(.subheadline)
                            .foregroundStyle(syncStatusColor(co.status))
                    }

                    if let result = co.lastResult {
                        infoRow(label: "最近同步", value: syncResultSummary(result))
                        infoRow(label: "推送 / 拉取", value: "↑\(result.pushed)  ↓\(result.pulled)")
                    }

                    Button {
                        Task { @MainActor in
                            do {
                                _ = try await co.syncBidirectional()
                            } catch {
                                AppLogger.sync.error("立即同步失败：\(error)")
                                toast = .init(
                                    kind: .error,
                                    text: "同步失败：\(syncErrorBrief(error))"
                                )
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundStyle(Color.systemBlue)
                            Text("立即同步")
                            Spacer()
                            if case .inProgress = co.status {
                                ProgressView().scaleEffect(0.7)
                            }
                        }
                    }
                    .disabled(!co.isEnabled || isSyncing(co.status))
                } else {
                    // 首次开启：App 启动路径不触碰 CloudKit API（防 entitlement 缺失崩溃）
                    // 等用户主动点 Toggle 时才创建 RealCloudKitProvider
                    Toggle(isOn: Binding(
                        get: { false },
                        set: { newVal in
                            if newVal {
                                Task { @MainActor in
                                    await enableSyncForFirstTime()
                                }
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
                            .font(.subheadline)
                            .foregroundStyle(Color.secondaryLabel)
                    }
                }
                #else
                HStack {
                    Image(systemName: "icloud.slash")
                        .foregroundStyle(Color.tertiaryLabel)
                    Text("iCloud 同步不可用（当前平台未编译 CloudKit）")
                        .foregroundStyle(Color.secondaryLabel)
                }
                #endif
            } header: {
                Text("iCloud 同步")
            } footer: {
                Text("通过 iCloud 私有数据库在多台设备间同步日历事件。需登录 iCloud 账号并启用 iCloud Drive。关闭后仅本地存储。")
            }

            // MARK: - 系统数据导入
            Section {
                Button {
                    importingSystemSource = .systemCalendar
                    Task { await performSystemImport(source: .systemCalendar) }
                } label: {
                    row(icon: "calendar.badge.plus",
                        text: "从系统日历导入",
                        tint: Color.systemRed)
                }
                .disabled(isImportingSystem)

                Button {
                    importingSystemSource = .contacts
                    Task { await performSystemImport(source: .contacts) }
                } label: {
                    row(icon: "person.crop.circle.badge.plus",
                        text: "从联系人导入生日/纪念日",
                        tint: Color.systemBlue)
                }
                .disabled(isImportingSystem)

                if importingSystemSource == .contacts {
                    Toggle(isOn: $importLunarToggle) {
                        Label("联系人生日按农历每年", systemImage: "moon.stars.fill")
                    }
                    .font(.subheadline)
                    .tint(Color.systemIndigo)
                    .disabled(isImportingSystem)
                }

                if isImportingSystem {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("正在拉取并合并…")
                            .font(.subheadline)
                            .foregroundStyle(Color.secondaryLabel)
                    }
                }
            } header: {
                Text("系统数据导入")
            } footer: {
                Text("系统日历事件按 RRULE 映射为重复规则；联系人生日默认按公历每年，可勾选按农历每年。重复导入同一条不会产生副本。")
            }

            // MARK: - 冲突策略
            Section {
                NavigationLink {
                    ConflictPolicyPicker(policy: $conflictPolicy)
                        .environment(store)
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(Color.systemOrange)
                        Text("导入冲突策略")
                        Spacer()
                        Text(conflictPolicy.title)
                            .font(.subheadline)
                            .foregroundStyle(Color.secondaryLabel)
                    }
                }
            } footer: {
                Text("再次导入同一份文件或从多台设备合并时，遇到同一事件的处理方式。")
            }

            // MARK: - 清空数据
            Section {
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("清空全部事件")
                        Spacer()
                        if store.events.isEmpty {
                            Text("0条")
                                .font(.footnote)
                                .foregroundStyle(Color.tertiaryLabel)
                        }
                    }
                }
                .disabled(store.events.isEmpty)
            } header: {
                Text("危险操作")
            } footer: {
                Text("清空后无法恢复，请先在上方「全量备份为 .json」导出备份再清空。")
            }

            // MARK: - 统计信息
            Section {
                infoRow(label: "总事件数", value: "\(store.events.count)")
                let schedules = store.events.filter { $0.type == .schedule }.count
                let reminders = store.events.filter { $0.type == .reminder }.count
                let notes = store.events.filter { $0.type == .note }.count
                infoRow(label: "日程", value: "\(schedules)")
                infoRow(label: "提醒", value: "\(reminders)")
                infoRow(label: "记事", value: "\(notes)")
            } header: {
                Text("数据统计")
            }

            // MARK: - 关于
            Section {
                HStack {
                    Text("应用名称")
                    Spacer()
                    Text("农历日历").foregroundStyle(Color.secondaryLabel)
                }
                HStack {
                    Text("版本")
                    Spacer()
                    Text("1.0.0").foregroundStyle(Color.secondaryLabel)
                }
                HStack {
                    Text("农历范围")
                    Spacer()
                    Text("1900-2100").foregroundStyle(Color.secondaryLabel)
                }
            } header: {
                Text("关于")
            }
        }
    }

    // MARK: - 辅助视图

    private func row(icon: String, text: String, tint: Color = Color.primary) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(text)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Color.tertiaryLabel)
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(Color.secondaryLabel)
        }
    }

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

    // MARK: - 操作

    private func exportAsICS() {
        let content = DataPortability.exportICS(from: store.events)
        let dateStr = isoDateStamp()
        if let url = DataPortability.writeToTempFile(
            content: content,
            filename: "lunisolar_calendar_\(dateStr).ics"
        ) {
            shareURL = url
            showShareSheet = true
            toast = .init(kind: .success, text: "已生成 .ics 日历备份（\(store.events.count) 条）")
        }
    }

    private func exportAsCSV() {
        let content = DataPortability.exportCSV(from: store.events)
        let dateStr = isoDateStamp()
        if let url = DataPortability.writeToTempFile(
            content: content,
            filename: "lunisolar_calendar_\(dateStr).csv"
        ) {
            shareURL = url
            showShareSheet = true
            toast = .init(kind: .success, text: "已生成 .csv 表格（\(store.events.count) 条）")
        }
    }

    private func exportAsJSONBackup() {
        let content = DataPortability.exportJSON(from: store.events)
        let dateStr = isoDateStamp()
        if let url = DataPortability.writeToTempFile(
            content: content,
            filename: "lunisolar_backup_\(dateStr).json"
        ) {
            shareURL = url
            showShareSheet = true
            toast = .init(kind: .success, text: "已生成全量 JSON 备份（\(store.events.count) 条）")
        }
    }

    private func handleImportResult(_ result: Result<URL, Error>, fileType: ImportedFileType) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                importedResult = .init(invalid: 1)
                showImportResult = true
                return
            }
            let incoming: [CalendarEvent]
            switch fileType {
            case .ics:  incoming = DataPortability.importICS(content)
            case .json: incoming = DataPortability.importJSON(content)
            }
            // merge 走统一策略；此处 skipSync 避免首次导入的纯本地数据推到云端
            let r = store.merge(incoming, policy: conflictPolicy, skipSync: true)
            importedResult = r
            showImportResult = true
            if r.added + r.updated > 0 {
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

    private func isoDateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmm"
        return f.string(from: Date())
    }

    // MARK: - 系统数据导入（日历 / 联系人）

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
        // Linux：用占位 Provider（不可能成功，只走错误流程让 UI 显示不可用）
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
        if r.added + r.updated > 0 {
            toast = .init(kind: .success,
                          text: "\(source.displayName) 导入：新增 \(r.added) · 更新 \(r.updated)")
        } else {
            toast = .init(kind: .warning,
                          text: "\(source.displayName) 无新增（已存在或被策略跳过）")
        }
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            // A1-3: 通过 SwiftUI environment 的 openURL 打开系统设置
            // （替换 UIApplication.shared.open，后者在 iOS 18+ / multi-scene 下 deprecated）
            openURL(url)
        }
    }

    // MARK: - iCloud 同步辅助

    /// 首次开启 iCloud 同步 —— 延迟创建 RealCloudKitProvider，避免 App 启动时
    /// 在没有 CloudKit entitlement 的模拟器/设备上触发 fatalError（EXC_BREAKPOINT）。
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
            store.syncCoordinator = coordinator  // EventStore 是 @Observable，赋值自动触发 UI 刷新
            UserDefaults.standard.set(true, forKey: "Lunisolar.sync.enabled")
            // 首次同步
            _ = try await coordinator.syncBidirectional()
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

    /// 通用 Error 过载：优先转 SyncError 给精确文案；否则回退 localizedDescription
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
