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
    @Environment(EventStore.self) var store
    @Environment(\.openURL) private var openURL
    /// 用于回到前台时重新读一次通知授权状态（用户可能刚去系统设置里开过）
    @Environment(\.scenePhase) private var scenePhase

    // —— 通知 / 导入状态
    @State var notifStatus: NotificationAuthStatus = .unavailable
    @State var showImportPicker = false
    @State var importingFileType: ImportedFileType = .ics
    @State var importedResult: ImportMergeResult?
    @State var showImportResult = false
    @State var showClearConfirm = false
    @State var toast: ToastMessage? = nil
    @State var conflictPolicy: ImportConflictPolicy = .keepLatest
    @State var showConflictPolicy = false
    // 系统导入
    @State var isImportingSystem = false
    @State var importingSystemSource: SystemImportSource = .systemCalendar
    /// 联系人生日是否按农历每年（跨启动保留）。
    /// 旧实现是 `@State`：每次冷启复位为 false，而用户往往"导入一次就不再想这事"，
    /// 于是这个偏好等于设不上。
    @AppStorage("Lunisolar.contactsImport.lunarAnnually") var importLunarToggle = false
    // 外观
    @AppStorage("Lunisolar.appearance") var appearanceSelection: AppAppearance = .system
    /// 每周起始日（Calendar weekday 语义：1=周日，2=周一；默认周日起始，保持既有用户布局）
    @AppStorage("Lunisolar.weekStart") var weekStart: Int = 1
    @AppStorage("Lunisolar.liveActivity.enabled") var liveActivityEnabled: Bool = true
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

    func storeCount(of type: EventType) -> Int {
        store.events.filter { $0.type == type }.count
    }

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
    func statRow(label: String, value: String) -> some View {
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

    private func openSystemSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
        #endif
    }
}

#endif
