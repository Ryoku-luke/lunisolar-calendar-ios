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
    @State private var notifStatus: NotificationAuthStatus = .unavailable
    @State private var showExportOptions = false
    @State private var showImportPicker = false
    @State private var importedCount = 0
    @State private var showImportResult = false

    var body: some View {
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
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("导出为 .ics 日历文件")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Color.tertiaryLabel)
                    }
                }

                Button {
                    exportAsCSV()
                } label: {
                    HStack {
                        Image(systemName: "tablecells")
                        Text("导出为 .csv 表格文件")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Color.tertiaryLabel)
                    }
                }

                Button {
                    showImportPicker = true
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text("从 .ics 文件导入")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Color.tertiaryLabel)
                    }
                }
            } header: {
                Text("数据管理")
            } footer: {
                Text("导出文件可保存至 Files 或通过微信/邮件分享。导入 .ics 文件支持从 iCloud/Files 选择。")
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
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            notifStatus = NotificationManager.shared.authorizationStatus
        }
        #if canImport(UniformTypeIdentifiers)
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [UTType(filenameExtension: "ics") ?? .data]
        ) { result in
            handleImportResult(result)
        }
        #endif
        .alert("导入完成", isPresented: $showImportResult) {
            Button("好") {}
        } message: {
            Text("成功导入 \(importedCount) 条事件")
        }
    }

    // MARK: - 辅助视图

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

    // MARK: - 操作

    private func exportAsICS() {
        let content = DataPortability.exportICS(from: store.events)
        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
            .replacingOccurrences(of: "/", with: "-")
        if let url = DataPortability.writeToTempFile(
            content: content,
            filename: "lunisolar_calendar_\(dateStr).ics"
        ) {
            shareFile(url)
        }
    }

    private func exportAsCSV() {
        let content = DataPortability.exportCSV(from: store.events)
        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
            .replacingOccurrences(of: "/", with: "-")
        if let url = DataPortability.writeToTempFile(
            content: content,
            filename: "lunisolar_calendar_\(dateStr).csv"
        ) {
            shareFile(url)
        }
    }

    private func shareFile(_ url: URL) {
        // 在 iOS 上通过 UIDocumentInteractionController 或 ShareLink 分享
        // 这里简单地写入临时文件，实际可用 ShareLink 包裹
        print("导出文件路径: \(url.path)")
    }

    private func handleImportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                let imported = DataPortability.importICS(content)
                for event in imported {
                    store.add(event)
                }
                importedCount = imported.count
                showImportResult = true
            }
        case .failure(let error):
            print("导入失败: \(error)")
        }
    }

    private func openSystemSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}

#endif
