#if canImport(SwiftUI)
import SwiftUI

extension SettingsView {
    // MARK: - 3. 数据（导入 / 恢复 + 系统数据导入）

    var dataSection: some View {
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

    // MARK: - Alert / Overlay

    @ViewBuilder
    var importResultAlertMessage: some View {
        if let r = importedResult {
            Text(importSummaryText(r))
        } else {
            Text("导入完成")
        }
    }

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

    func handleImportResult(_ result: Result<URL, Error>, fileType: ImportedFileType) {
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
}

#endif
