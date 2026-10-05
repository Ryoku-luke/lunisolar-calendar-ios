#if canImport(SwiftUI)
import SwiftUI

extension SettingsView {
    // MARK: - 3. 数据（导入 / 恢复 + 系统数据导入）

    /// 「存储当前为只读」提示（D7）。
    ///
    /// 为什么需要：只读时改动**静默不保存**，用户会以为「保存坏了」或「App 有 bug」。
    /// 这里把状态直接说出来，并给出可操作的方向（清空间 + 重启）。只在只读时出现。
    @ViewBuilder
    var storageReadOnlySection: some View {
        if store.storageIsReadOnly {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("存储当前为只读", comment: "设置页：存储只读提示标题"))
                            .font(AppTheme.Font.bodyBold)
                            .foregroundStyle(Color.systemOrange)
                        Text(NSLocalizedString("改动暂时无法保存。可能是设备可用空间不足，或数据迁移未完成；请清理空间后重启 App。",
                                               comment: "设置页：存储只读提示说明"))
                            .font(AppTheme.Font.caption)
                            .foregroundStyle(Color.secondaryLabel)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.systemOrange)
                }
            }
        }
    }

    var dataSection: some View {
        Section {
            // 误触优化：整行点击 = 先选格式（不再"点行主体直接走 .ics"，
            // 避免想恢复 .json 却误触行主体进入错误导入流程）。
            //
            // P3-6：这里原先是嵌套 `Menu`。审计实测它在无障碍树里**按钮元素没有标签**
            // （文字留在子 StaticText 上），AX 外框也只有 154.7×20.3pt（HIG 要 44pt 高）；
            // 而给那个 Menu 挂任何 accessibility 修饰符都会让 SwiftUI 崩溃
            // （EXC_BAD_ACCESS in `initializeWithCopy for Menu`，`SettingsView.body`，
            //   对照实验确认由该修饰符引入）。改用「Button + confirmationDialog」：
            // 标准控件自带标签与整行命中区，防误触语义不变（仍是两选一后才导入）。
            Button {
                showImportSourceDialog = true
            } label: {
                Label(NSLocalizedString("导入 / 恢复数据", comment: ""), systemImage: "square.and.arrow.down")
            }
            .confirmationDialog(NSLocalizedString("导入 / 恢复数据", comment: "导入/恢复：格式选择对话框标题"),
                                isPresented: $showImportSourceDialog, titleVisibility: .visible) {
                Button(NSLocalizedString("从 .ics 日历文件导入", comment: "")) {
                    importingFileType = .ics
                    showConflictPolicy = true
                }
                Button(NSLocalizedString("从 .json 备份恢复", comment: "")) {
                    importingFileType = .json
                    showConflictPolicy = true
                }
                Button(NSLocalizedString("取消", comment: ""), role: .cancel) {}
            }

            // D6：导出 / 备份入口。与导入对称——先选格式，再由系统的文件面板决定存到哪。
            Button {
                showExportDialog = true
            } label: {
                Label(NSLocalizedString("导出 / 备份数据", comment: "设置页：导出入口"), systemImage: "square.and.arrow.up")
            }
            .confirmationDialog(NSLocalizedString("导出 / 备份数据", comment: ""),
                                isPresented: $showExportDialog, titleVisibility: .visible) {
                ForEach(ExportFormat.allCases) { format in
                    Button(format.localizedTitle) {
                        let text = format.makeText(from: store.events)
                        exportDocument = DataExportDocument(data: Data(text.utf8))
                        exportFormat = format
                        showExporter = true
                    }
                }
                Button(NSLocalizedString("取消", comment: ""), role: .cancel) {}
            }
            // 系统文件面板：导出落点交给用户（存到「文件」、iCloud、AirDrop 到别处）
            .fileExporter(isPresented: $showExporter,
                          document: exportDocument,
                          contentType: exportFormat?.contentType ?? .data,
                          defaultFilename: exportFormat?.defaultFilename() ?? "qinghe-events") { _ in }

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

    // MARK: - Alert / Overlay

    @ViewBuilder
    var conflictPolicyAlertButtons: some View {
        ForEach(ImportConflictPolicy.allCases, id: \.self) { p in
            Button(conflictPolicyButtonTitle(p)) {
                conflictPolicy = p
                showImportPicker = true
            }
        }
        Button("取消", role: .cancel) {}
    }

    func conflictPolicyButtonTitle(_ p: ImportConflictPolicy) -> String {
        p == conflictPolicy ? p.title + NSLocalizedString("（当前）", comment: "") : p.title
    }

    var conflictPolicyAlertMessage: some View {
        // 拆成两行而不是在一个 key 里塞 `\n`：字符串目录里的换行键既难翻译也易出错
        VStack(alignment: .leading, spacing: 4) {
            Text(String(format: NSLocalizedString("当前策略：%@ · %@", comment: ""),
                        conflictPolicy.title, conflictPolicy.subtitle))
            Text(NSLocalizedString("选完策略后会打开 Files 选择文件。", comment: ""))
        }
    }

    func importSummaryText(_ r: ImportMergeResult) -> String {
        // 这些是 String 上下文的文案：必须显式 NSLocalizedString，
        // 否则无论 .strings 里有没有条目都不会被查表（英文界面永远显示中文）
        var parts: [String] = []
        if r.added > 0   { parts.append(String(format: NSLocalizedString("新增 %d", comment: ""), r.added)) }
        if r.updated > 0 { parts.append(String(format: NSLocalizedString("更新 %d", comment: ""), r.updated)) }
        if r.skipped > 0 { parts.append(String(format: NSLocalizedString("保留本地 %d", comment: ""), r.skipped)) }
        if r.invalid > 0 { parts.append(String(format: NSLocalizedString("无效 %d", comment: ""), r.invalid)) }
        let main = parts.isEmpty
            ? NSLocalizedString("没有可导入的日程", comment: "")
            : parts.joined(separator: " · ")
        if r.hasConflicts {
            let note = String(format: NSLocalizedString("（检测到 %d 条冲突，已按「%@」处理）", comment: ""),
                              r.updated + r.skipped, conflictPolicy.title)
            return main + "\n" + note
        }
        return main
    }
    // MARK: - 导入操作

    func handleImportResult(_ result: Result<URL, Error>, fileType: ImportedFileType) {
        // 结果**只**走行内 toast（UI_DESIGN_REVIEW P0-3）。
        // 原先每条分支都同时置 `showImportResult = true` 与 `toast = ...`，
        // 同一件事既弹模态又弹 banner——正是报告 §42「同一件事不要既 Toast 又 Alert」禁止的重复播报。
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else {
                toast = .init(kind: .error, text: NSLocalizedString("导入失败：无权限读取该文件，请重新选择", comment: ""))
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else {
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
            // 新增/更新的事件如果是 reminder，需要被挂到 UNUserNotificationCenter。
            // 由于本 merge 是 O(N) 数据导入，用 rescheduleAllReminders（内部 cancelAll+重排）一次性刷新全局
            if r.added + r.updated > 0 {
                Task { @MainActor in
                    EventService.shared.rescheduleAllReminders()
                }
            }
            // 摘要用完整的 `importSummaryText`（含「保留本地 N / 无效 N」与冲突提示），
            // 而不是原先那句只报新增/更新的短文案——删掉模态后，这里是用户唯一能看到导入细节的地方。
            toast = .init(kind: r.added + r.updated > 0 ? .success : .warning,
                          text: importSummaryText(r))
        case .failure(let error):
            AppLogger.app.error("导入失败: \(error)")
            toast = .init(kind: .error,
                          text: String(format: NSLocalizedString("导入失败：%@", comment: ""),
                                       error.localizedDescription))
        }
    }

    // MARK: - 系统数据导入

    @MainActor
    func performSystemImport(source: SystemImportSource) async {
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
                              text: String(format: NSLocalizedString("%@ 中没有可导入的日程", comment: ""),
                                           source.displayName))
            }
            return
        }

        // P0 收口：批量合并导入走 EventService（内部转 EventStore.merge）
        let r = EventService.shared.mergeImportedEvents(events, policy: conflictPolicy, skipSync: true)
        // 系统导入的结果只走行内 toast（「导入结果」alert 已随 P0-3 一并删除）
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
}

#endif
