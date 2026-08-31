#if canImport(SwiftUI)
import SwiftUI
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
#if canImport(UIKit)
import UIKit
#endif
// N6 修复：本文件 5 处 AppLogger 最终走 os.Logger 的 OSLogMessage 插值；
// iOS 18 SDK 下 SwiftUI 不再 transitively 引入 os。
#if canImport(os)
import os
#endif

// MARK: - 设置页面 · 现代分组卡 + 液态玻璃头

struct SettingsView: View {
    @Environment(EventStore.self) private var store
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.openURL) private var openURL

    // —— 通知 / 导入 / 导出状态
    @State private var notifStatus: NotificationAuthStatus = .unavailable
    @State private var showImportPicker = false
    @State private var importingFileType: ImportedFileType = .ics
    @State private var importedResult: ImportMergeResult?
    @State private var showImportResult = false
    @State private var shareURL: URL?
    @State private var showShareSheet = false
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

    // iPad regular 模式下居中限宽
    private var isWide: Bool { hSizeClass == .regular }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.systemGroupedBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AppTheme.Spacing.section) {
                        heroHeader
                            .padding(.top, AppTheme.Spacing.lg)

                        appearanceCard
                        notificationCard
                        dataManagementCard
                        cloudSyncCard
                        systemImportCard
                        conflictPolicyCard
                        dangerZoneCard
                        statisticsCard
                        aboutCard

                        Color.clear.frame(height: AppTheme.Spacing.xxl)
                    }
                    .padding(.horizontal, isWide ? AppTheme.Spacing.xxl : AppTheme.Spacing.lg)
                    .frame(maxWidth: isWide ? 760 : .infinity)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
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
            } message: { importResultAlertMessage }
            .alert("导入前：冲突处理策略", isPresented: $showConflictPolicy) {
                conflictPolicyAlertButtons
            } message: { conflictPolicyAlertMessage }
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
            .animation(.easeInOut(duration: 0.22), value: toast)
        }
    }

    // MARK: - Hero · 液态玻璃头

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(spacing: AppTheme.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.appTint, Color.systemIndigo.opacity(0.85)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "calendar")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolRenderingMode(.hierarchical)
                }
                .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("农历日历")
                        .font(AppTheme.Font.title2)
                        .foregroundStyle(Color.label)
                    Text("v1.0.0 · 1900 – 2100")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(Color.secondaryLabel)
                }
                Spacer(minLength: 0)
                ChipLabel(title: "\(store.events.count) 事件", systemImage: "list.bullet.rectangle", tint: Color.appTint)
            }

            HStack(spacing: AppTheme.Spacing.sm) {
                HeroStat(label: "日程", value: storeCount(of: .schedule), tint: .appTint)
                HeroStat(label: "提醒", value: storeCount(of: .reminder), tint: .systemOrange)
                HeroStat(label: "记事", value: storeCount(of: .note), tint: .systemIndigo)
            }
        }
        .padding(AppTheme.Spacing.xl)
        .liquidGlassCard(
            cornerRadius: AppTheme.Radius.xl,
            borderColor: Color.appTint.opacity(0.22),
            borderWidth: 0.8,
            shadowOpacity: 0.10,
            interactive: false
        )
    }

    private func storeCount(of type: EventType) -> Int {
        store.events.filter { $0.type == type }.count
    }

    // MARK: - 1. 外观

    private var appearanceCard: some View {
        SettingsCard(title: "外观", icon: "circle.lefthalf.filled", tint: Color.systemIndigo, subtitle: "浅色 / 深色 / 跟随系统自动切换") {
            AppearanceSegmented(selection: $appearanceSelection)
        }
    }

    // MARK: - 2. 通知

    private var notificationCard: some View {
        SettingsCard(title: "提醒通知", icon: "bell.badge", tint: Color.systemOrange, subtitle: "本地通知，权限未开启时提醒不会送达") {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack {
                    Text("通知权限")
                        .font(AppTheme.Font.body)
                    Spacer()
                    Text(notifStatusText)
                        .font(AppTheme.Font.subheadline.weight(.semibold))
                        .foregroundStyle(notifStatus == .granted ? Color.systemGreen : Color.secondaryLabel)
                        .capsuleTag(fill: notifStatus == .granted ? Color.systemGreen.opacity(0.12) : Color.quaternarySystemFill)
                }

                if notifStatus == .denied {
                    Button { openSystemSettings() } label: {
                        Label("前往系统设置开启", systemImage: "arrow.up.right.square")
                            .font(AppTheme.Font.subheadline.weight(.semibold))
                            .foregroundStyle(Color.appTint)
                    }
                }

                Divider().opacity(0.0)

                Button {
                    Task { await NotificationManager.shared.rescheduleAllReminders(in: store) }
                } label: {
                    HStack {
                        Label("重新调度所有提醒", systemImage: "arrow.clockwise.circle.fill")
                            .font(AppTheme.Font.bodyBold)
                            .foregroundStyle(Color.systemOrange)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.tertiaryLabel)
                    }
                }
                .buttonStyle(.plain)
                .disabled(notifStatus != .granted)
                .opacity(notifStatus == .granted ? 1 : 0.45)
            }
            .padding(AppTheme.Spacing.lg)
        }
    }

    // MARK: - 3. 数据管理

    private var dataManagementCard: some View {
        SettingsCard(title: "数据管理", icon: "externaldrive.badge.checkmark", tint: Color(hex: "#C41A1A"), subtitle: "备份 · 导出 · 导入 / 恢复，.json 保留全部字段") {
            VStack(spacing: 2) {
                DataActionRow(
                    icon: "square.and.arrow.up",
                    title: "导出为 .ics 日历文件",
                    subtitle: "适合与其他日历 App 互通",
                    tint: Color.systemBlue
                ) { exportAsICS() }
                divider
                DataActionRow(
                    icon: "tablecells",
                    title: "导出为 .csv 表格文件",
                    subtitle: "可用 Excel / Numbers 打开",
                    tint: Color.systemGreen
                ) { exportAsCSV() }
                divider
                DataActionRow(
                    icon: "externaldrive.badge.checkmark",
                    title: "全量备份为 .json",
                    subtitle: "含农历重复 / 通知状态 / 创建时间",
                    tint: Color(hex: "#C41A1A")
                ) { exportAsJSONBackup() }
                divider
                DataActionRow(
                    icon: "square.and.arrow.down",
                    title: "导入 / 恢复数据",
                    subtitle: ".ics 日历 / .json 全量备份",
                    tint: Color(red: 0.25, green: 0.55, blue: 0.95),
                    accessory: .menu
                ) { showConflictPolicy = true } secondary: {
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
                        Image(systemName: "ellipsis.circle")
                            .font(AppTheme.Font.title3)
                            .foregroundStyle(Color.appTint)
                    }
                }
            }
            .padding(4)
        }
    }

    // MARK: - 4. iCloud 同步

    private var cloudSyncCard: some View {
        SettingsCard(title: "iCloud 同步", icon: "icloud", tint: Color.systemBlue, subtitle: "通过 iCloud 私有数据库在多台设备间同步") {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                #if canImport(CloudKit)
                if let co = store.syncCoordinator {
                    Toggle(isOn: Binding(
                        get: { co.isEnabled },
                        set: { newVal in handleSyncToggle(co, enabled: newVal) }
                    )) {
                        Label("启用 iCloud 同步", systemImage: "icloud")
                            .font(AppTheme.Font.bodyBold)
                    }
                    .tint(Color.systemBlue)

                    HStack {
                        Text("同步状态")
                            .font(AppTheme.Font.body)
                        Spacer()
                        Text(syncStatusText(co.status))
                            .font(AppTheme.Font.subheadline.weight(.semibold))
                            .foregroundStyle(syncStatusColor(co.status))
                            .capsuleTag(fill: syncStatusColor(co.status).opacity(0.12))
                    }

                    if let result = co.lastResult {
                        VStack(spacing: AppTheme.Spacing.sm) {
                            infoMiniRow(label: "最近同步", value: syncResultSummary(result))
                            infoMiniRow(label: "推送 / 拉取", value: "↑ \(result.pushed)   ↓ \(result.pulled)")
                        }
                        .padding(AppTheme.Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                                .fill(Color.quaternarySystemFill)
                        )
                    }

                    Button {
                        Task { @MainActor in
                            do {
                                _ = try await co.syncBidirectional()
                            } catch {
                                AppLogger.sync.error("立即同步失败：\(error)")
                                toast = .init(kind: .error, text: "同步失败：\(syncErrorBrief(error))")
                            }
                        }
                    } label: {
                        HStack {
                            Label("立即同步", systemImage: "arrow.triangle.2.circlepath")
                                .font(AppTheme.Font.bodyBold)
                                .foregroundStyle(Color.systemBlue)
                            Spacer()
                            if case .inProgress = co.status {
                                ProgressView().scaleEffect(0.7)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.tertiaryLabel)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
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
                            .font(AppTheme.Font.bodyBold)
                    }
                    .tint(Color.systemBlue)

                    HStack {
                        Text("同步状态")
                            .font(AppTheme.Font.body)
                        Spacer()
                        Text("未启用")
                            .font(AppTheme.Font.subheadline)
                            .foregroundStyle(Color.secondaryLabel)
                            .capsuleTag(fill: Color.quaternarySystemFill)
                    }

                    Text("首次开启时才会创建 CloudKit 容器，避免未配置 entitlement 时启动崩溃。")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(Color.tertiaryLabel)
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
            }
            .padding(AppTheme.Spacing.lg)
        }
    }

    // MARK: - 5. 系统数据导入

    private var systemImportCard: some View {
        SettingsCard(title: "系统数据导入", icon: "tray.and.arrow.down.fill", tint: Color.systemMint, subtitle: "从系统日历 / 联系人导入，重复导入不会产生副本") {
            VStack(spacing: 2) {
                DataActionRow(
                    icon: "calendar.badge.plus",
                    title: "从系统日历导入",
                    subtitle: "按 RRULE 映射为重复规则",
                    tint: Color.systemRed,
                    busy: isImportingSystem && importingSystemSource == .systemCalendar
                ) {
                    importingSystemSource = .systemCalendar
                    Task { await performSystemImport(source: .systemCalendar) }
                }
                divider
                DataActionRow(
                    icon: "person.crop.circle.badge.plus",
                    title: "从联系人导入生日/纪念日",
                    subtitle: importLunarToggle ? "按农历每年重复" : "按公历每年重复",
                    tint: Color.systemBlue,
                    busy: isImportingSystem && importingSystemSource == .contacts
                ) {
                    importingSystemSource = .contacts
                    Task { await performSystemImport(source: .contacts) }
                }
                if importingSystemSource == .contacts || !store.events.isEmpty {
                    divider
                    HStack(spacing: AppTheme.Spacing.md) {
                        Image(systemName: "moon.stars.fill")
                            .font(AppTheme.Font.bodyBold)
                            .foregroundStyle(Color.systemIndigo)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("联系人生日按农历每年")
                                .font(AppTheme.Font.body)
                            Text("闰月生日会匹配平月同日")
                                .font(AppTheme.Font.caption)
                                .foregroundStyle(Color.tertiaryLabel)
                        }
                        Spacer()
                        Toggle("", isOn: $importLunarToggle)
                            .labelsHidden()
                            .tint(Color.systemIndigo)
                    }
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.vertical, AppTheme.Spacing.md)
                }

                if isImportingSystem {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("正在拉取并合并…")
                            .font(AppTheme.Font.subheadline)
                            .foregroundStyle(Color.secondaryLabel)
                    }
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.vertical, AppTheme.Spacing.md)
                }
            }
            .padding(4)
        }
    }

    // MARK: - 6. 冲突策略

    private var conflictPolicyCard: some View {
        SettingsCard(title: "导入冲突策略", icon: "arrow.triangle.2.circlepath.circle.fill", tint: Color.systemOrange, subtitle: "同 ID 事件合并时的处理方式") {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                PolicyChipPicker(policy: $conflictPolicy)
                Text(conflictPolicy.subtitle)
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(Color.secondaryLabel)
                    .padding(.horizontal, 4)
            }
            .padding(AppTheme.Spacing.lg)
        }
    }

    // MARK: - 7. 危险操作

    private var dangerZoneCard: some View {
        SettingsCard(title: "危险操作", icon: "exclamationmark.triangle.fill", tint: Color.systemRed, subtitle: "清空后无法恢复，请先在上方导出 .json 备份") {
            VStack(spacing: AppTheme.Spacing.md) {
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    HStack {
                        Label("清空全部事件", systemImage: "trash.fill")
                            .font(AppTheme.Font.bodyBold)
                        Spacer()
                        Text("\(store.events.count) 条")
                            .font(AppTheme.Font.caption.weight(.semibold))
                            .foregroundStyle(Color.tertiaryLabel)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.tertiaryLabel)
                    }
                    .padding(.vertical, AppTheme.Spacing.sm)
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                            .fill(Color.systemRed.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                            .stroke(Color.systemRed.opacity(0.25), lineWidth: AppTheme.Stroke.hair)
                    )
                }
                .buttonStyle(.plain)
                .disabled(store.events.isEmpty)
                .opacity(store.events.isEmpty ? 0.45 : 1)
            }
            .padding(AppTheme.Spacing.lg)
        }
    }

    // MARK: - 8. 统计

    private var statisticsCard: some View {
        SettingsCard(title: "数据统计", icon: "chart.bar.doc.horizontal.fill", tint: Color.systemPurple) {
            VStack(spacing: AppTheme.Spacing.xs) {
                StatRow(label: "总事件数", value: "\(store.events.count)")
                divider
                StatRow(label: "日程", value: "\(storeCount(of: .schedule))")
                divider
                StatRow(label: "提醒", value: "\(storeCount(of: .reminder))")
                divider
                StatRow(label: "记事", value: "\(storeCount(of: .note))")
            }
            .padding(AppTheme.Spacing.sm)
        }
    }

    // MARK: - 9. 关于

    private var aboutCard: some View {
        SettingsCard(title: "关于", icon: "info.circle.fill", tint: Color.secondaryLabel) {
            VStack(spacing: AppTheme.Spacing.xs) {
                StatRow(label: "应用名称", value: "农历日历")
                divider
                StatRow(label: "版本", value: "1.0.0")
                divider
                StatRow(label: "农历范围", value: "1900 – 2100")
            }
            .padding(AppTheme.Spacing.sm)
        }
    }

    // MARK: - 分割线 / 通用控件

    private var divider: some View {
        Color.separator.opacity(0.28)
            .frame(height: AppTheme.Stroke.hair)
            .padding(.leading, 52)
    }

    private func infoMiniRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(AppTheme.Font.caption)
                .foregroundStyle(Color.secondaryLabel)
            Spacer()
            Text(value)
                .font(AppTheme.Font.subheadline.weight(.semibold))
                .foregroundStyle(Color.label)
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

    // MARK: - 导入导出操作

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
            openURL(url)
        }
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

// MARK: - 子组件：设置卡 / Hero 统计 / 外观分段 / 冲突策略胶囊

/// 通用「设置卡片」：带图标 + 标题 + 副标题 + 内容块
private struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    let tint: Color
    var subtitle: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: icon)
                    .font(AppTheme.Font.title3)
                    .foregroundStyle(tint)
                    .symbolRenderingMode(.hierarchical)
                Text(title)
                    .font(AppTheme.Font.title3)
                    .foregroundStyle(Color.label)
                Spacer(minLength: 0)
            }
            if let subtitle {
                Text(subtitle)
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(Color.secondaryLabel)
                    .padding(.leading, AppTheme.Spacing.md + 4)
                    .padding(.top, -4)
            }
            content()
        }
        .padding(AppTheme.Spacing.lg)
        .modernCard(radius: AppTheme.Radius.xl, material: .thinMaterial)
    }
}

/// Hero 区：小型统计块
private struct HeroStat: View {
    let label: String
    let value: Int
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(AppTheme.Font.numeralL)
                .foregroundStyle(tint)
            Text(label)
                .font(AppTheme.Font.caption2)
                .foregroundStyle(Color.secondaryLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .fill(tint.opacity(0.08))
        )
    }
}

/// 外观分段选择器（系统 / 浅色 / 深色）
private struct AppearanceSegmented: View {
    @Binding var selection: AppAppearance

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            ForEach(AppAppearance.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: mode.iconName)
                            .font(AppTheme.Font.title3)
                        Text(mode.title)
                            .font(AppTheme.Font.caption.weight(.semibold))
                    }
                    .foregroundStyle(selection == mode ? Color.white : Color.secondaryLabel)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                            .fill(
                                selection == mode
                                    ? LinearGradient(colors: [Color.systemIndigo, Color.appTint], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    : LinearGradient(colors: [Color.quaternarySystemFill, Color.quaternarySystemFill], startPoint: .top, endPoint: .bottom)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                            .stroke(selection == mode ? Color.appTint.opacity(0.45) : .clear,
                                    lineWidth: AppTheme.Stroke.hair)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// 冲突策略 胶囊 chip 三列选择器
private struct PolicyChipPicker: View {
    @Binding var policy: ImportConflictPolicy

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            ForEach(ImportConflictPolicy.allCases, id: \.self) { p in
                Button { policy = p } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.title)
                            .font(AppTheme.Font.subheadline.weight(.semibold))
                            .multilineTextAlignment(.leading)
                    }
                    .foregroundStyle(policy == p ? Color.white : Color.label)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                            .fill(
                                policy == p
                                    ? Color.appTint
                                    : Color.quaternarySystemFill
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                            .stroke(policy == p ? Color.appTint.opacity(0.5) : .clear,
                                    lineWidth: AppTheme.Stroke.hair)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// 数据管理 / 系统导入 的单行操作
private struct DataActionRow: View {
    let icon: String
    let title: String
    var subtitle: String = ""
    let tint: Color
    var busy: Bool = false
    var accessory: Accessory = .chevron
    var action: () -> Void = {}
    @ViewBuilder var secondary: (() -> some View) = { EmptyView() }

    enum Accessory { case chevron, menu, none }

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .fill(tint.opacity(0.14))
                    Image(systemName: icon)
                        .font(AppTheme.Font.bodyBold)
                        .foregroundStyle(tint)
                        .symbolRenderingMode(.hierarchical)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTheme.Font.bodyBold)
                        .foregroundStyle(Color.label)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(AppTheme.Font.caption)
                            .foregroundStyle(Color.secondaryLabel)
                    }
                }
                Spacer(minLength: 8)
                if busy {
                    ProgressView().scaleEffect(0.7)
                } else {
                    secondary()
                    switch accessory {
                    case .chevron:
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.tertiaryLabel)
                    case .menu, .none:
                        EmptyView()
                    }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 统计行：左 label 右 value
private struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(AppTheme.Font.body)
                .foregroundStyle(Color.secondaryLabel)
            Spacer()
            Text(value)
                .font(AppTheme.Font.subheadline.weight(.semibold))
                .foregroundStyle(Color.label)
                .lineLimit(1)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.md)
    }
}

#endif
