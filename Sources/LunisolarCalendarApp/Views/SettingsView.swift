#if canImport(SwiftUI)
import SwiftUI
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - 设置页面

struct SettingsView: View {
    @Environment(EventStore.self) private var store
    @Environment(\.horizontalSizeClass) private var hSizeClass
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

    var body: some View {
        baseForm
            .formStyle(.grouped)
            .frame(maxWidth: hSizeClass == .regular ? 720 : .infinity)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
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

                // JSON 全量备份（字段无损：农历生日 / 通知状态 / 创建时间等都保留）
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
                if let co = store.syncCoordinator {
                    Toggle(isOn: Binding(
                        get: { co.isEnabled },
                        set: { newVal in handleSyncToggle(co, enabled: newVal) }
                    )) {
                        Label("启用 iCloud 同步", systemImage: "icloud")
                    }
                    .tint(Color.systemBlue)

                    // 同步状态
                    HStack {
                        Text("同步状态")
                        Spacer()
                        Text(syncStatusText(co.status))
                            .font(.subheadline)
                            .foregroundStyle(syncStatusColor(co.status))
                    }

                    // 最近一次同步结果
                    if let result = co.lastResult {
                        infoRow(label: "最近同步", value: syncResultSummary(result))
                        infoRow(label: "推送 / 拉取", value: "↑\(result.pushed)  ↓\(result.pulled)")
                    }

                    // 手动同步按钮
                    Button {
                        // BUG #35 修复：不再用 try? 静默吞错误；错误进入 coordinator.status（行内显示）
                        // 同时弹一条 toast 给用户即时反馈。
                        Task { @MainActor in
                            do {
                                _ = try await co.syncBidirectional()
                            } catch {
                                print("[SettingsView] 立即同步失败：\(error)")
                                toast = .init(
                                    style: .error,
                                    text: "同步失败：\(syncErrorBrief(error))",
                                    duration: 3.0
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
                    // CloudKit 不可用（Linux / 未配置容器）
                    HStack {
                        Image(systemName: "icloud.slash")
                            .foregroundStyle(Color.tertiaryLabel)
                        Text("iCloud 同步不可用")
                            .foregroundStyle(Color.secondaryLabel)
                    }
                }
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

                // 仅当选择联系人时才显示农历 Toggle（日历事件不需要农历规则）
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
        .formStyle(.grouped)
        // iPad 宽屏下限制表单宽度
        .frame(maxWidth: hSizeClass == .regular ? 720 : .infinity)
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // 用异步版本避免阻塞主线程
            notifStatus = await NotificationManager.shared.authorizationStatusAsync()
        }
        #if canImport(UniformTypeIdentifiers)
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: {
                switch importingFileType {
                case .ics:  return [UTType(filenameExtension: "ics") ?? .data]
                case .json: return [UTType(filenameExtension: "json") ?? .data]
                }
            }()
        ) { result in
            handleImportResult(result, fileType: importingFileType)
        }
        #endif
        .alert("导入结果", isPresented: $showImportResult) {
            Button("好") {}
        } message: {
            if let r = importedResult {
                Text(importSummaryText(r))
            } else {
                Text("导入完成")
            }
        }
        // 冲突策略确认弹框（用户点导入 → 先确认策略 → 再选文件）
        .alert("导入前：冲突处理策略", isPresented: $showConflictPolicy) {
            ForEach(ImportConflictPolicy.allCases, id: \.self) { p in
                Button(p.title + (p == conflictPolicy ? "（当前）" : "")) {
                    conflictPolicy = p
                    showImportPicker = true
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前策略：\(conflictPolicy.title) · \(conflictPolicy.subtitle)\n选完策略后会打开 Files 选择文件。")
        }
        // 清空二次确认
        .alert("确认清空全部事件？", isPresented: $showClearConfirm) {
            Button("清空全部 \(store.events.count) 条", role: .destructive) {
                let n = store.clearAll()
                toast = .init(kind: .success, text: "已清空 \(n) 条事件")
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作不可恢复，强烈建议先点击「全量备份为 .json」导出备份。")
        }
        // Toast：导入/备份完成后短暂出现
        .overlay(alignment: .top) {
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
        #if canImport(UIKit)
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ShareSheet(items: [url])
            }
        }
        #endif
        .animation(.easeInOut(duration: 0.2), value: toast)
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
            print("导入失败: \(error)")
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
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }

    // MARK: - iCloud 同步辅助

    @MainActor
    private func handleSyncToggle(_ co: EventSyncCoordinator, enabled: Bool) {
        co.isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "Lunisolar.sync.enabled")
        if enabled {
            // 开启 → 立即触发一次双向同步
            // BUG #35 修复：不再 try? 静默吞；失败在控制台打印，便于排查（coordinator.status 行内也会变红）
            Task { @MainActor in
                do {
                    _ = try await co.syncBidirectional()
                } catch {
                    print("[SettingsView] 开启同步后首次同步失败：\(error)")
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

// MARK: - 辅助：导入文件类型 / 冲突策略文案 / Toast

enum ImportedFileType {
    case ics
    case json
}

extension ImportConflictPolicy {
    public var title: String {
        switch self {
        case .keepLatest: return "保留最新（推荐）"
        case .keepLocal:  return "保留本地"
        case .overwrite:  return "覆盖本地"
        }
    }

    public var subtitle: String {
        switch self {
        case .keepLatest: return "按 updatedAt 谁更新就用谁"
        case .keepLocal:  return "同 id 的外部数据一律跳过"
        case .overwrite:  return "同 id 一律用导入版本覆盖"
        }
    }
}

struct ToastMessage: Identifiable, Equatable {
    enum Kind: Equatable { case success, warning, error }
    var id = UUID()
    var kind: Kind
    var text: String
}

#if canImport(SwiftUI)
struct ToastBannerView: View {
    let message: ToastMessage

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(.white)
            Text(message.text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(bgColor.shadow(.drop(color: .black.opacity(0.14), radius: 8, x: 0, y: 2)))
        )
        .padding(.horizontal, 20)
    }

    private var iconName: String {
        switch message.kind {
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error:   return "xmark.octagon.fill"
        }
    }

    private var bgColor: Color {
        switch message.kind {
        case .success: return Color(red: 0.21, green: 0.64, blue: 0.37)
        case .warning: return Color(red: 0.90, green: 0.61, blue: 0.15)
        case .error:   return Color(red: 0.87, green: 0.28, blue: 0.28)
        }
    }
}

struct ConflictPolicyPicker: View {
    @Environment(EventStore.self) private var store
    @Binding var policy: ImportConflictPolicy

    var body: some View {
        Form {
            Section {
                ForEach(ImportConflictPolicy.allCases, id: \.self) { p in
                    Button {
                        policy = p
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(p.title).foregroundStyle(Color.primary)
                                Text(p.subtitle)
                                    .font(.footnote)
                                    .foregroundStyle(Color.secondaryLabel)
                            }
                            Spacer()
                            if policy == p {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color(hex: "#C41A1A"))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("冲突处理策略")
            } footer: {
                Text("当导入的事件与本地事件 id 相同时如何处理。若选「保留最新」，会按 updatedAt 时间戳比较。")
            }

            Section {
                info(label: "本地事件总数", value: "\(store.events.count)")
            } header: {
                Text("预览")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("导入冲突策略")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func info(label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(Color.secondaryLabel)
        }
    }
}
#endif

// MARK: - ShareSheet (UIActivityViewController 包装)

#if canImport(UIKit)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

// MARK: - ImportFileModifier（.fileImporter 包装成独立 ViewModifier，降低 body 内联闭包复杂度）

#if canImport(UniformTypeIdentifiers)
private struct ImportFileModifier: ViewModifier {
    @Binding var isPresented: Bool
    let fileType: ImportedFileType
    let onResult: (Result<URL, Error>) -> Void

    func body(content: Content) -> some View {
        content.fileImporter(
            isPresented: $isPresented,
            allowedContentTypes: {
                switch fileType {
                case .ics:  return [UTType(filenameExtension: "ics") ?? .data]
                case .json: return [UTType(filenameExtension: "json") ?? .data]
                }
            }()
        ) { result in
            onResult(result)
        }
    }
}
#else
private struct ImportFileModifier: ViewModifier {
    @Binding var isPresented: Bool
    let fileType: ImportedFileType
    let onResult: (Result<URL, Error>) -> Void
    func body(content: Content) -> some View { content }
}
#endif

#endif
