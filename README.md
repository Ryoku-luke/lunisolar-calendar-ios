# 清和日历 · iOS 中国农历日历

> 「清和」出自《汉书·郊祀志》"天气清和，稼穑咸秀"——晴朗温和、岁月美好。

一款 iOS / iPadOS 日历应用，内置公历↔农历转换、黄历宜忌、日程/记事/提醒、本地通知、iCloud 同步，界面遵循 iOS 26 设计规范（Liquid Glass 液态玻璃 + 节日自适应主题色 + 按压反馈），支持 iPhone 和 iPad 自适应布局。

## 功能

| 模块 | 说明 |
|---|---|
| 日历月视图 | 7×6 标准网格、左右滑动切换月份、"今天"快捷按钮、液态玻璃顶栏、节日染色壁纸、拖拽视差 |
| 中国农历 | 1900-2100 公历↔农历转换、闰月支持、干支纪年、十二生肖；农历↔公历双向查询 |
| 黄历 | 宜/忌事项、冲煞、五行纳音、神位；离散数据库（2024-2028）+ 算法兜底 |
| 事件管理 | 日程 / 提醒 / 记事三种类型，优先级标识，本地通知 |
| 重复规则 | 不重复 / 每天 / 每周 / 每月 / 每年 / **农历每年**（父母生日·传统节日）|
| 数据导入导出 | .ics (iCalendar) / .csv / .json 全量备份；冲突策略 keepLatest / keepLocal / overwrite |
| 系统数据导入 | 系统日历（EventKit）+ 联系人（Contacts）导入，确定性 UUID 防重复 |
| iCloud 同步 | 真实 CloudKit（私有DB + Custom Zone + 墓碑 + 增量拉取）+ Mock 测试容器 |
| Widget 小组件 | 今日黄历概览 / 农历日期卡片 / 今日待办进度，App Group 共享快照 |
| iPad 适配 | NavigationSplitView 双栏布局，cell 尺寸自适应 |
| iOS 26 UI | Liquid Glass 液态玻璃卡片/按钮/Toast、按压反馈动画、节日自适应强调色、SF Symbols hierarchical/palette 渲染 |
| 深浅色主题 | 品牌色动态适配深浅模式；设置页可选 跟随系统/浅色/深色 |
| App 图标 | 主图标（撕历 + 朱砂「农」印）+ 春节限定版（金箔「福」字 + 红灯笼），自动按春节窗口切换 |

## 系统要求

- iOS / iPadOS 17.0+（iOS 26+ 自动启用 Liquid Glass 效果）
- Swift 6.0 / Xcode 16.0+

## 运行方式

### Xcode 直接运行（推荐）

1. Xcode → File → New → Project → **iOS App**（Interface: SwiftUI, Minimum Deployments: iOS 17+）
2. 删除自动生成的 `ContentView.swift` 与 `<项目名>App.swift`
3. 将 `Sources/LunisolarCalendarApp/` 整个目录拖入工程（勾选 Copy items if needed）
4. 将 `Assets/XCAssets/` 拖入工程作为 Asset Catalog
5. 将 `Sources/LunisolarCalendarApp/Info.plist` 配置到 Target → Info → Info.plist File
6. 运行 `bash Tools/gen-app-icons.sh` 生成全部图标 PNG（需 macOS）
7. ⌘R 运行

### Swift Package

```swift
dependencies: [
    .package(url: "https://github.com/Ryoku-luke/lunisolar-calendar-ios.git", branch: "main")
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "LunisolarCalendarApp", package: "lunisolar-calendar-ios")
    ])
]
```

根视图：

```swift
import SwiftUI
import LunisolarCalendarApp

@main
struct YourApp: App {
    var body: some Scene {
        WindowGroup {
            AdaptiveRootView()
                .environment(EventStore.shared)
        }
    }
}
```

### App 图标配置

1. 在 macOS 上运行 `bash Tools/gen-app-icons.sh`，从 `Assets/Brand/` 下的 1024×1024 原图生成全部 iOS 图标尺寸 PNG
2. 将 `Assets/XCAssets/` 拖入 Xcode 工程的 Asset Catalog
3. TARGETS → General → App Icons and Launch Screen → App Icon Source 选 `AppIcon`
4. 将 `Info.plist` 中的 `CFBundleIcons` / `CFBundleIcons~ipad` 声明春节限定备用图标
5. App 运行时 `AlternateIconManager.shared.applyTodayIfNeeded()` 自动按春节窗口切换

### Widget 接入

1. 创建 Widget Extension Target → `@main` 用 `LunisolarWidgetsBundle()`
2. 主 App 和 Widget Extension 勾选同一 App Group
3. 主 App 设置 `EventStore().widgetAppGroupID = "group.com.you.lunisolar"`

### iCloud / CloudKit 接入

1. Xcode → 主 App Target → Signing & Capabilities → 添加 iCloud → 勾选 CloudKit
2. 运行 App → 设置页 → 「iCloud 同步」开关打开

> Linux / SwiftPM 环境不链接 CloudKit，测试使用 MockCloudKitProvider。

## 项目结构

```
Sources/LunisolarCalendarApp/
├── App/
│   └── LunisolarCalendarApp.swift         # @main 入口 + AdaptiveRootView + 外观偏好
├── Models/
│   ├── LunarDate.swift                     # 公历↔农历算法 + LunarDataProvider + Date扩展
│   ├── Huangli.swift                       # 黄历模型 + HuangliGenerator 算法生成器
│   └── CalendarEvent.swift                 # 事件模型（含农历重复 + Sendable）
├── Stores/
│   └── EventStore.swift                    # @Observable + JSON持久化 + merge + dirty追踪
├── Support/
│   ├── AppTheme.swift                      # 设计 Token（Motion/Touch/liquidCard/pressableFeedback）
│   ├── ColorExtensions.swift               # 语义色 + iOS 26 Liquid Glass 封装 + AppAppearance
│   ├── AlternateIconManager.swift          # 节日图标自动切换管理器
│   ├── NotificationManager.swift           # UNUserNotificationCenter 封装
│   ├── DataPortability.swift               # .ics/.csv/.json 导入导出
│   ├── FestivalManager.swift               # 节日匹配 + 主题色
│   ├── HuangliDBProvider.swift             # 离散黄历数据库（2024-2028）
│   ├── WidgetSnapshotStore.swift           # Widget 共享快照
│   ├── SystemImportBridge.swift            # 系统导入桥（确定性UUID + 聚合）
│   ├── CalendarImportProvider.swift        # EventKit 桥
│   ├── ContactsImportProvider.swift        # Contacts 桥
│   ├── Bundle+Resources.swift              # 跨平台 Bundle 资源定位
│   └── FlowLayout.swift                    # 流式标签布局
├── Sync/
│   ├── ICloudSyncProvider.swift            # 同步协议 + SyncRecord
│   ├── MockCloudKitProvider.swift          # 内存模拟容器（测试用）
│   ├── RealCloudKitProvider.swift          # 真实 CloudKit
│   └── EventSyncCoordinator.swift          # 同步协调器（push/pull/merge）
├── Widgets/
│   ├── LunisolarWidgetBundle.swift
│   ├── LunisolarWidgetProvider.swift
│   └── LunisolarWidgetViews.swift           # 3 种样式
├── Resources/
│   ├── lunar_calendar.json                 # 农历数据表（1900-2100）
│   └── huangli_db.json                     # 离散黄历数据库（2024-2028）
├── Info.plist                               # App 基本信息 + 图标声明 + 隐私权限
└── Views/
    ├── CalendarMonthView.swift              # 月视图主界面（液态玻璃 + 节日色 + 滑动手势）
    ├── CalendarComponents.swift             # 星期表头 / DayCell
    ├── DayDetailView.swift                  # 日详情（玻璃卡片 + 空态插画 + 节日色）
    ├── EventEditView.swift                  # 新建/编辑/删除（玻璃分区 + 按压芯片）
    ├── EventRow.swift                       # 事件列表项
    ├── SettingsView.swift                   # 设置页（液态玻璃分组 + Toast 动效）
    └── SettingsViewComponents.swift         # Toast 悬浮玻璃卡

Assets/
├── Brand/
│   ├── app-icon-primary.jpg                # 主图标 1024×1024（撕历 + 朱砂印）
│   └── app-icon-spring-festival.jpg        # 春节限定 1024×1024（金福 + 灯笼）
└── XCAssets/
    ├── AppIcon.appiconset/Contents.json     # 主图标 Asset Catalog 配置
    ├── AppIconSpringFestival.appiconset/    # 春节限定 Asset Catalog 配置
    └── Info.plist-EXAMPLE.xml               # CFBundleIcons 合并样例

Tools/
├── gen_huangli_db/main.swift                # 黄历数据库生成工具
└── gen-app-icons.sh                         # macOS sips 一键批量缩图脚本

Tests/LunisolarCalendarTests/                # 59 个单元测试
```

## 构建与测试

```bash
swift build        # 编译所有 Target（0 警告）
swift test         # 运行 59 个单元测试
```

> Linux 环境仅验证模型层（农历/黄历/事件CRUD/导入导出/同步Mock），SwiftUI 视图编译需 iOS/macOS SDK。

## 测试覆盖（59/59 通过）

| 套件 | 数量 | 覆盖内容 |
|---|---|---|
| LunarDateTests | 4 | 17 个农历真值点、闰月、边界 nil 安全、反向转换 |
| HuangliTests | 3 | 宜忌稳定性、冲煞验证 |
| HuangliDBProviderTests | 6 | 离散库命中、边界 fallback、DB↔算法一致性 |
| CalendarEventTests | 11 | 事件模型、农历重复规则、ICS 往返、优先级 |
| EventStoreTests | 7 | CRUD、搜索、合并策略、副本防护 |
| DataPortabilityTests | 3 | JSON/ICS 往返、伪 UUID 稳定性、合并统计 |
| ICloudSyncTests | 6 | 推送/拉取/冲突/增量/离线上线/墓碑传播 |
| WidgetSnapshotTests | 4 | 快照读写、过期检测、自动写入 |
| SystemImportTests | 9 | DTO 映射、确定性 UUID、聚合、端到端无副本 |

## 已修复的关键问题

共修复 44 个 BUG，涵盖数据安全、并发竞态、CloudKit API 兼容、日历一致性、Swift 6 并发隔离、UI 触碰区等。关键修复包括：

- **数据安全**：损坏数据不再覆盖用户数据；dirty 标记持久化防重启丢失；ContactsImportProvider year 强制解包安全化
- **并发安全**：推送队列序列化；同步防重入；NSLock → DispatchQueue；`@MainActor` 隔离 EventSyncCoordinator
- **日历一致性**：全模块统一 `Calendar(identifier: .gregorian)`，避免非公历系统环境月视图错乱
- **CloudKit 兼容**：适配 Xcode 16 / Swift 6 API 变更；延迟装配防 entitlement 崩溃
- **iOS 26 适配**：UIScreen.main 废弃、Color.tertiary 移除、Liquid Glass 液态玻璃、按压反馈、节日自适应色
- **UI 触碰优化**：全部交互元素 ≥ 44pt 触碰区；液态玻璃分组卡片；Toast 弹簧动画；芯片按压切换
- **性能优化**：月视图黄历预计算、Widget 快照自动写入、墓碑 TTL 清理

## License

MIT
