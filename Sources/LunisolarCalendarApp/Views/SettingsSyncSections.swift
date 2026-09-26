#if canImport(SwiftUI)
import SwiftUI

extension SettingsView {
    // MARK: - 4. iCloud 同步

    var syncSection: some View {
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
                .accessibilityIdentifier(AccessibilityID.settingsSyncToggle)

                HStack {
                    Text(NSLocalizedString("同步状态", comment: ""))
                    Spacer()
                    Text(syncStatusText(co.status))
                        .font(AppTheme.Font.subheadline.weight(.semibold))
                        .foregroundStyle(syncStatusColor(co.status))
                }
                .accessibilityIdentifier(AccessibilityID.settingsSyncStatus)

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
                .accessibilityIdentifier(AccessibilityID.settingsSyncToggle)

                HStack {
                    Text(NSLocalizedString("同步状态", comment: ""))
                    Spacer()
                    Text(NSLocalizedString("未启用", comment: ""))
                        .font(AppTheme.Font.subheadline)
                        .foregroundStyle(Color.secondaryLabel)
                }
                .accessibilityIdentifier(AccessibilityID.settingsSyncStatus)
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

    // MARK: - iCloud 同步辅助
    //
    // P0 遗留收口：CloudKit 装配 / 开关切换 / 立即同步全部在 AppLifecycleCoordinator，
    // 这里只把首次开启的结果映射成 toast（文案与旧行为一致）。

    @MainActor
    func enableSyncFirstTime() async {
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

    func syncStatusText(_ status: SyncStatus) -> String {
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

    func syncStatusColor(_ status: SyncStatus) -> Color {
        switch status {
        case .idle: return Color.secondaryLabel
        case .inProgress: return Color.systemBlue
        case .succeeded: return Color.systemGreen
        case .failed: return Color.systemRed
        }
    }

    func syncErrorBrief(_ e: SyncError) -> String {
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

    func syncErrorBrief(_ e: Error) -> String {
        if let se = e as? SyncError { return syncErrorBrief(se) }
        return e.localizedDescription
    }

    func syncResultSummary(_ r: SyncResult) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        let time = f.string(from: r.finishedAt)
        let status = r.isSuccess
            ? NSLocalizedString("成功", comment: "")
            : NSLocalizedString("部分失败", comment: "")
        return "\(time) · \(status)"
    }

    func isSyncing(_ status: SyncStatus) -> Bool {
        if case .inProgress = status { return true }
        return false
    }
}

#endif
