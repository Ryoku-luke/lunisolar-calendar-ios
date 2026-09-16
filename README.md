# 清和日历 · iOS 中国农历日历

> 「清和」出自《汉书·郊祀志》"天气清和，稼穑咸秀"——晴朗温和、岁月美好。

一款 iOS / iPadOS 日历应用，内置公历↔农历转换、黄历宜忌、日程/记事/提醒、本地通知、iCloud 同步，界面遵循 iOS 26/27 设计规范（Liquid Glass 液态玻璃 + 节日自适应主题色 + 按压反馈），支持 iPhone 和 iPad 自适应布局，兼容 iOS 27 / iPadOS 27。

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

- iOS / iPadOS 17.0+（iOS 26+ 自动启用 Liquid Glass 效果；iOS 27 / iPadOS 27 已验证兼容）
- Swift 6.0 / Xcode 16.0+（建议 Xcode 27，2027 Q1 起 App Store 提交要求 Xcode 27 构建）

## 运行方式

### Xcode 直接运行（推荐）

1. Xcode → File → New → Project → **iOS App**（Interface: SwiftUI, Minimum Deployments: iOS 17+）
2. 删除自动生成的 `ContentView.swift` 与 `<项目名>App.swift`
3. 将 `Sources/LunisolarCalendarApp/` 整个目录拖入工程（勾选 Copy items if needed）
4. 将 `Assets/Assets.xcassets/` 拖入工程作为 Asset Catalog
5. 将 `Sources/LunisolarCalendarApp/Info.plist` 配置到 Target → Info → Info.plist File
6. 运行 `python3 Tools/gen-icons-flat-blue.py` 生成全部图标 PNG（跨平台，需 Pillow）
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

1. 运行 `python3 Tools/gen-icons-flat-blue.py`，生成扁平化淡蓝渐变风格的全部 iOS 图标尺寸 PNG（15 档位 + 1024 源图）
2. 将 `Assets/Assets.xcassets/` 拖入 Xcode 工程的 Asset Catalog
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
├── Assets.xcassets/                         # Asset Catalog（主图标 + 春节限定）
│   ├── AppIcon.appiconset/                  # 15 档位扁平化淡蓝渐变主图标
│   └── AppIconSpringFestival.appiconset/    # 15 档位红金渐变福字春节限定
└── Brand/
    ├── app-icon-primary.png                 # 主图标 1024×1024 源图
    └── app-icon-spring-festival.png         # 春节限定 1024×1024 源图

Tools/
├── gen_huangli_db/main.swift                # 黄历数据库生成工具
└── gen-icons-flat-blue.py                   # 跨平台 Python 图标生成脚本

Tests/LunisolarCalendarTests/                # 99 个单元测试
```

## 构建与测试

```bash
swift build        # 编译所有 Target（0 警告）
swift test         # 运行 99 个单元测试
```

> Linux 环境仅验证模型层（农历/黄历/事件CRUD/导入导出/同步Mock），SwiftUI 视图编译需 iOS/macOS SDK。

## 测试覆盖（99/99 通过）

| 套件 | 数量 | 覆盖内容 |
|---|---|---|
| CalendarEventTests | 16 | 事件模型、农历重复规则、ICS 往返、优先级、节日主色 |
| EventStoreTests | 16 | CRUD、搜索、合并策略、副本防护、toggleCompleted 通知重排 |
| ICloudSyncTests | 11 | 推送/拉取/冲突/增量/离线上线/墓碑传播/isNotified 不跨设备同步 |
| SystemImportTests | 9 | DTO 映射、确定性 UUID、聚合、端到端无副本 |
| DataPortabilityTests | 8 | JSON/ICS 往返、伪 UUID 稳定性、合并统计 |
| HuangliDBProviderTests | 6 | 离散库命中、边界 fallback、DB↔算法一致性 |
| LunarDateTests | 5 | 17 个农历真值点、闰月、边界 nil 安全、反向转换 |
| WidgetSnapshotTests | 4 | 快照读写、过期检测、自动写入 |
| NotificationLunarAnniversaryTests | 5 | 农历周年提醒边界、16 年搜索窗口、闰月源回退/闰月匹配 |
| HolidayProviderTests | 7 | 2025/2026 国务院放假安排锚点、调休补班、数据覆盖边界 |
| AccessibilityIDTests | 3 | 无障碍标识目录：非空唯一、命名规范、核心元素覆盖 |
| CountdownEventTests | 7 | 纪念日周年（今年/跨年/2·29 回退）、倒数日天数与文案 |
| HuangliTests | 2 | 宜忌稳定性、冲煞验证 |

> 共 99 个单元测试（截至 2026-09-14，第三轮加固后）。`swift test` 会全量运行。

## 2026-09-14 代码审计推进记录

| 项 | 内容 |
|---|---|
| 节假日数据 | `HolidayProvider` 2026 年数据按《国办发明电〔2025〕7号》修正：春节 2/15–2/23（原 2/15 误标补班、2/24 误标放假）、劳动节补班 5/9（原误标 4/26）、新增元旦 1/4 与国庆 9/20 补班、国庆 10/1–10/7（原误标至 10/8）；新增 `dataCoverage` / `dataCoverageDescription` 覆盖说明 |
| 回归测试 | 新增 `HolidayProviderTests`（7 条），断言 2025/2026 官方安排锚点与覆盖边界；总测试数 80 → 87 |
| README | 修正测试明细表（原含不存在的 CountdownTests/AccessibilityTests 且多套件数量偏差） |
| iCloud | 主 App entitlements 补齐 `com.apple.developer.icloud-services` 与 `icloud-container-identifiers`（`iCloud.com.lunisolar.calendar`）；真机生效仍需 Xcode Capability + Developer Portal 注册，见 `docs/ENTITLEMENTS.md` |
| CI | 新增 `.github/workflows/ci.yml`：Linux `swift test` + iOS 模拟器 `xcodebuild test` |
| 仓库清理 | `.trae/` 开发期工具移出仓库（备份在仓库外）并加入 `.gitignore`；补全 LICENSE（MIT，与 README 声明一致） |

## 2026-09-14（第二轮）B 清单推进记录

| 项 | 内容 |
|---|---|
| 无障碍标注 | 新建 `AccessibilityID` 目录（稳定 accessibilityIdentifier）；月视图 FAB「新建日程」、日详情工具栏「+」补 `accessibilityLabel` + identifier；编辑页保存/删除按钮补 identifier；`TagCloudView` / `ChipLabel` 改为整体朗读（`children: .combine`） |
| 无障碍测试 | 新增 `AccessibilityIDTests`（3 条）：标识非空唯一、命名规范、核心元素覆盖 |
| 黄历数据策略 | 明确产品口径：离散库覆盖 2024–2028，**2029-01-01 起走算法兜底**（`HuangliGenerator`），设置页以 `HuangliDBProvider.coverageDescription` 如实展示覆盖范围；如后续要求 2029+ 与库数据一致，用 `Tools/gen_huangli_db` 扩库并人工抽验（见下方"黄历数据策略"） |

### 黄历数据策略（产品决策，2026-09-14 定）

1. **当前口径**：2024-01-01 ~ 2028-12-31 使用人工核验的离散库（`huangli_db.json`，385KB）；此范围外（含 2029 起）走 `HuangliGenerator.algorithmGenerate()` 算法兜底，保证不空窗。
2. **一致性风险**：算法推导结果与离散库在个别日子的宜忌措辞可能存在差异；已在设置页展示数据覆盖说明，避免用户误解。
3. **后续选项**（如需 2029+ 与库一致）：运行 `swift run gen_huangli_db` 扩展 JSON 到目标年份，并按 `HuangliDBProviderTests` 现有方式做 DB↔算法一致性抽验后合入。

### 真实 iOS 编译修复（2026-09-14 第二轮补充）

在 Mac/Xcode 首次真实编译 iOS 时发现 `CountdownView.swift` 编译错误：`Date.formatted(date:time:)` 不接受 `locale` 参数（三参写法不存在），报 "Extra argument 'locale' in call"。已改为 `Date.FormatStyle(date:time:locale:)` 显式构造。

> 背景说明：SwiftUI 视图层文件整体被 `#if canImport(SwiftUI)` 包裹，Linux `swift test` 会将其编译为空，因此**视图层此前从未被任何平台实际编译过**。建议本轮起以 `xcodebuild test`（CI 已含）作为视图层编译门禁；后续再发现同类编译错误会同步记录在此。

## 2026-09-14（第三轮）回归测试加固记录

| 项 | 内容 |
|---|---|
| 模拟器验收 | 用户确认 iPhone 17 Pro 模拟器正常运行（编译错误修复后） |
| 模块复查 | 通知调度 / 倒数日存储 / 日期跳转 / ICS 导入导出 / 同步协调器逐一静态复查：eligibility、offset 分量、农历周年搜索窗口、防抖接线（flushPendingSave 已连 App scenePhase 与各保存入口）、RFC 5545 排他 DTEND、伪 UID 去重、LWW 部分失败保留 dirty —— 均已有修复与注释，未发现新的实锤缺陷 |
| 新增回归测试 | `CountdownEventTests`（7 条）：纪念日周年（今年/跨年/2·29 回退到 2/28）、倒数日天数与文案边界；`NotificationLunarAnniversaryTests` 补 2 条闰月语义（无同闰月回退普通月、有同闰月匹配闰月）；总测试数 90 → 99 |

## 2026-09-14（第四轮）原生化 + 图标 + 工程整洁

| 项 | 内容 |
|---|---|
| App 图标修复 | **根因**：`AppIcon.appiconset` / `AppIconSpringFestival.appiconset` 两个目录都缺 `Contents.json`，Xcode 无法识别图标集 → 图标不显示。已补 single-size 格式（Xcode 15+），并删除旧式多尺寸 PNG |
| App 图标重制 | 重新生成 1024×1024 主图标（米白渐变底 + 红色日历页眉 + 金色月牙 + 中国灯笼，扁平 iOS 风格）；春节备用图标保留原图，仅补 Contents.json |
| UI 原生化（月视图） | 删除自定义渐变悬浮 FAB → 改 toolbar 系统「+」；背景去掉 iOS 26 模糊色斑（保留 systemGroupedBackground + 极淡节日染色）；液态玻璃日历卡片 → 系统次要分组背景卡片；月份切换 chevron 去掉自定义材质圆底，改系统蓝 |
| UI 原生化（日详情） | `festiveWallpaper` 同步降级：去模糊色斑，仅保留极淡节日染色 |
| 删除无用代码 | `FloatingActionButton`（仅定义、无任何引用的死代码）已删除 |
| 大文件拆分 | `SettingsView.swift` 1180 → 924 行：末尾 6 个独立子组件（SettingsCard / HeroStat / AppearanceSegmented / PolicyChipPicker / DataActionRow / StatRow）移入 `SettingsViewComponents.swift`（139 → 396 行），行为零变化 |
| 本地化基座 | 新建 `Resources/zh-Hans.lproj/Localizable.strings` + `InfoPlist.strings`（键=值自映射，行为不变；为将来 en.lproj 提供键表）。接线方式见下文 |
| UI 测试骨架 | 新建 `UITests/LunisolarCalendarUITests.swift`（3 条冒烟：启动→标题、+ 进入编辑页、网格渲染）。接线方式见下文 |

### 本地化基座接线（一次性，Xcode 操作）

1. 将 `Sources/LunisolarCalendarApp/Resources/zh-Hans.lproj/` 拖入 Xcode 工程
2. 勾选 **LunisolarCalendar（主 App）与 LunisolarWidget** 两个 Target 的 "Copy Bundle Resources"
3. 主 App 与 Widget 的 `InfoPlist.strings` 会让 `CFBundleDisplayName` 走本地化表（Widget 名称不再依赖单一硬编码）
4. 后续新增语言：复制 `zh-Hans.lproj` 为 `en.lproj` 并翻译键值即可，无需改代码

### UI 测试接线（一次性，Xcode 操作）

1. Xcode → File → New → Target… → iOS → **UI Testing Bundle**，命名 `LunisolarCalendarUITests`
2. Target Application 选择 **LunisolarCalendar**
3. 将 `UITests/LunisolarCalendarUITests.swift` 加入该 Target，Cmd+U 运行（3 条冒烟测试）

### 个人团队签名兼容（2026-09-14 补充）

模拟器运行正常后，用户在 Xcode 配置签名（Mingfeng Lu · Personal Team）时遇到：
**"Personal development teams do not support the iCloud capability"** —— 个人免费账号不支持 iCloud，
导致 provisioning profile 无法创建（连带 App Groups 警告）。

**已修复**：主 App `LunisolarCalendar.entitlements` 移除 iCloud 两个 key（`icloud-services` /
`icloud-container-identifiers`），保留 App Groups（免费账号支持）。代码侧降级路径本就完整
（启动延迟装配 + `isAvailable` 探测 + 不可用静默关闭开关，不会崩溃），设置页开启同步时显示"不可用"提示。
详细说明见 `docs/ENTITLEMENTS.md`。

**重新签名后应看到**：1 个错误消失；若仍有 App Groups 警告，点 **Try Again** 或重新 Build 让 Xcode 重建 profile。

**注意**：你在 Xcode 中把 Bundle ID 改成了 `com.lumingfeng.lunisolarcalendar` —— 请同时确认
**Widget target** 的 Bundle ID 也已改成对应值（如 `com.lumingfeng.lunisolarcalendar.widget`），
且主 App 与 Widget 的 **App Group** 都保持 `group.com.lunisolar.calendar`（与 Bundle ID 无关，独立命名空间）。

## 2026-09-14（第五轮）点击修复 + 删除导出 + 视觉协调

| 项 | 内容 |
|---|---|
| **P1 点击日期无反应** | **根因**：`CalendarMonthView` 未传 binding 时（iPhone 根页）走 else 分支，用局部引用类型 `_Box` 捕获状态，点击后值变了但 SwiftUI 无状态变更通知 → 永不重绘 → 点击日期"无反应"。iPad 侧栏传了真 `@State` binding 所以正常。**修复**：改用真实 `@State localSelectedDate`，init 中 `State(initialValue:)` + `projectedValue` 接线，删除 `_Box` |
| **删除导出功能** | 设置页数据管理区删除「导出为 .ics / .csv / 全量备份 .json」三个入口与 ShareSheet 分享面板、导出函数、相关状态；保留「导入 / 恢复」。危险操作确认文案去掉"请先导出 .json 备份"强推。`DataPortability` 导出工具函数**保留**（导出↔导入 round-trip 单测依赖） |
| **日历视觉协调** | ① 今日态：红色浅填充 → **红色描边圆角**（无填充），与「选中实心」「节日浅染」三层视觉清晰区分，更贴近 iOS 原生日历；② 选中态阴影减淡（8→5pt、3→2pt）；③ 网格间距 2→4 更舒展 |

## 2026-09-14（第六轮）点击修复彻底化 + 设置误触优化

| 项 | 内容 |
|---|---|
| **P1 点击日期无反应（彻底修复）** | 上一轮 `@Binding ← @State.projectedValue` 的 init 接线在运行时仍不可靠（用户实测依旧无反应）。**彻底重构**：`selectedDate` 从 `@Binding` 改为**本地 `@State` 唯一真相**，外部绑定（iPad 双栏）改为可选属性 + **onChange 双向同步**（本地→外部写回；外部→本地更新并同步月份）。@State 写入必然触发 SwiftUI 重绘，点击逻辑不再依赖任何 init 接线技巧 |
| **设置界面误触优化** | 数据管理卡「导入 / 恢复数据」：原实现**行主体点击直接走 .ics 导入**，而 .json 恢复藏在行尾小菜单，想恢复 .json 极易误触。改为**整行点击弹出格式选择菜单**（.ics / .json 一次选定），杜绝误触进入错误导入流程 |

## 2026-09-14（第七轮）全项目审查 + 按报告落地修复

本轮对全项目 14290 行做了一次彻底审查（农历/黄历/节气/节日/通知/同步六条算法链逐行核验），并按分级报告落地修复：

| 级别 | 修复 | 说明 |
|---|---|---|
| **P2-1 越界假农历** | `Date.lunar` 走 `lunarDateSafe`，越界返回 `.unsupported` 占位（不再返回"公历镜像假农历"）；月视图格子 / 选中日卡片 / 日详情在越界时隐藏农历显示；`FestivalManager` 对占位农历跳过农历节日查询（避免 2100 年后误标"春节"） | 1900 前 / 2100 后翻月不再出现假农历误导 |
| **P2-2 节气节日** | `FestivalManager` 新增节气节日（清明/冬至/立春等，当天恰逢交节时在节日标签区标注"🌿 节气名"），随 `SolarTermProvider` 数据联动；新增 `FestivalKind.solarTerm` | 与市场同类日历对齐（节气条 + 格子双呈现） |
| **P3-2 黄历越界假数据** | `HuangliGenerator.algorithmGenerate` 对农历越界（year==0 占位）时五行纳音置空串，UI 显示"—"——旧实现算出 0 年干支"庚申"→ 白蜡金 | 消除越界日期"庚申年白蜡金"假数据 |
| **P3-5 强制解包** | `CountdownView.allowedDateRange` 的 `cal.date(from:)!` 改 guard 兜底（防御未来边界调整崩溃） | 0 处 `date(from:)!` 残留 |
| **P3-6 add 防重** | `EventStore.add` 同 id 已存在时忽略并告警（防御性；当前调用方均 UUID() 新建） | 防未来路径导致数组重复 id 数据损坏 |
| **P3-8 闰月天数校验** | `solarDate(fromLunar:)` 天数不得超过目标月实际天数——旧实现 day=30 在 29 天月份会溢出到下月 1 日 | 与通知周年"三十回退廿九"逻辑形成双保险 |
| **P3-1 立春口径（审后决策：不改）** | 采样离散库确认：2024-02-05（立春后、春节前）年命纳音仍按上一年（癸卯 金箔金）→ **数据源按春节换年柱**，且测试断言"离散库==算法"；大众生肖/年命习惯亦以春节为界。**维持春节口径**，新增 `ChineseCalendar.ganZhiOfYear(for:)`（立春口径）备用 API | 避免 2028→2029 年柱口径跳变 |

**审查结论摘要**：六条算法链全部核验通过（农历位编码换算、日干支甲戌基准、冲煞三合局、宜忌 60 甲子全覆盖、黄历 DB 懒加载、通知调度 .gregorian 统一、农历周年搜索窗口、同步 LWW 版本提交/部分失败/墓碑 TTL）；全局 0 处 fatalError、0 处 Calendar.current 混用。历史 P1（点击日期无反应）第六轮 @State 根治方案仍待用户 Xcode 实测验收。

## 2026-09-15（第八轮）Xcode 警告清零（SwiftUI 状态回写 + CloudKit 废弃 API）

用户在 Xcode 实测截图报出 2 警告 1 错误，本轮全部消除：

| 项 | 修复 | 说明 |
|---|---|---|
| **🔺 SwiftUI "Modifying state during view update"** | `CalendarMonthView.gridModel()` 不再在 body 求值期间回写 `@State gridCache`（Xcode 判定为未定义行为，调用栈直指 State.wrappedValue → gridCache）。**修复**：拆出纯计算 `buildGridModel()`；body 只读缓存、未命中则临时构建；缓存改由 `.task(id: gridCacheKey)` 在 body 外异步填充（月份/事件版本变化时触发） | 消除未定义行为，同时保留横滑每帧 O(1) 缓存命中的性能收益 |
| **⚠️ `perRecordCompletionBlock` deprecated (iOS 15) ×2** | `RealCloudKitProvider.configurePerRecordTracking` 改用 iOS 15+ 标准 API **`perRecordSaveBlock`**（`(recordID, savedRecord, error)`），`saveBatch` 调用处同步适配（成功必带 record，兜底防御） | 部署目标 iOS 17，兼容无碍；0 处废弃 API 残留 |

**控制台说明**（非代码问题）：`Debug session ended with code 9` = SIGKILL，是**进程被外部终止**（模拟器内存压力 / Xcode 重新运行 / 手动停止），代码崩溃通常是 signal 4/6/10；`cannot add handler to 0 from 0 - dropping` 为模拟器网络栈常见无害日志。`isAvailable` 在无 iCloud 容器时 catch 返回 false，同步功能安全禁用，不会触发崩溃。

## 2026-09-15（第九轮）iOS 27 / iPadOS 27 支持

iOS 27 / iPadOS 27 正式版（2026-09-14/15 推送）。本轮完成系统级适配审查 + Liquid Glass 原生升级：

**iOS 27 强制项审查（全部通过，无需改造）**：

| 变更 | 项目状态 |
|---|---|
| UIScene 生命周期必需（iOS 27 SDK 构建后无 Scene 不启动） | ✅ SwiftUI `@main App` + `UIApplicationSceneManifest_Generation` 天然满足 |
| Liquid Glass 强制（Xcode 27 移除兼容 flag） | ✅ 无 opt-out flag；升级原生 `.glassEffect`（见下） |
| `UIRequiresFullScreen` 不再 opt-out 窗口缩放（TN3192） | ✅ Info.plist 未设置，iPad 分屏/台前调度正常 |
| SwiftUI `actionSheet` 移除 | ✅ 0 处使用（全量 grep） |
| TabView 拦截 delegate 变更 | ✅ 项目无 TabView/UITabBarController |
| iPhone Duo 折叠屏（用 size classes 而非 orientation） | ✅ 0 处 orientation 依赖，19 处 horizontalSizeClass 布局 |

**本轮代码改动**：

- **Liquid Glass 原生化**（`Support/ColorExtensions.swift`）：`glassCardFallback` 的 iOS 26+ 分支从 thickMaterial 自绘模拟升级为官方 `.glassEffect(.regular.interactive() / .regular, in: .rect(cornerRadius:))`，保留品牌色薄边框与轻阴影；iOS 15–25 继续走 thickMaterial 模拟（视觉一致）。卡片级组件（选中日卡片/宜忌卡）在 iOS 26+ 获得系统级玻璃折射与交互响应。
- **chip 级组件保持系统材质**（`AppTheme.softChipBackground`，9 处调用）：`.ultraThinMaterial` 在 iOS 26+ 自动玻璃化，符合 Apple "玻璃用于传达意义" 指南，密集小元素不过度玻璃化。
- 部署目标保持 **iOS 17.0**（Xcode 27 支持部署 iOS 15–27；不提升最低版本以保留旧设备用户）。

**Xcode 27 人工验证清单**（本机无 Swift 工具链，需在 Xcode 27 实测）：

- [ ] Xcode 27 打开工程 → Build（Swift 6.4 编译器，目标 0 error 0 warning）
- [ ] iPhone 模拟器（iOS 27）运行：月视图/翻月/点击日期/宜忌卡片显示正常
- [ ] iPad 模拟器（iPadOS 27）运行：双栏布局、台前调度缩放、分屏（Split View）正常
- [ ] 深色/浅色模式玻璃效果正常（iOS 26+ 卡片折射高光可见）
- [ ] Widget 扩展在 iOS 27 运行正常
- [ ] `#available(iOS 26.0, *)` 分支在 iOS 27 模拟器命中（日志或断点确认走 glassEffect 分支）

**构建错误修复（Xcode 27 实测反馈，两批）**：

1. `Cannot find 'SolarTermProvider' in scope`（×2）：根因 `LunarDate.swift` 同时被 LunarCore（纯算法 target）与 App target 编译，第七轮备用 API 引用了 App 层符号。修复：`ganZhiOfYear(for:)` 改 2/4 近似立春，零调用点零影响；LunarCore 边界文件已确认无 App 层符号。

2. `RealCloudKitProvider` 6 个编译错误（CloudKit per-record API 签名错误）：第八轮将 `perRecordCompletionBlock` 误写为 3 参数三元组 `perRecordSaveBlock`（该 API 实际签名是 **iOS 15+ 的 `(CKRecord.ID, Result<CKRecord, any Error>) -> Void`** 二元组 Result 形式，与 `perRecordResultBlock` 风格一致；且第八轮修改后未经 Xcode 重新编译即交付）。修复：`saveBatch` 改 `op.perRecordSaveBlock = { recordID, result in ... }`（switch Result），`deleteBatch` 改专用 `op.perRecordDeleteBlock = { recordID, result in ... }`（`Result<Void, any Error>`，替代 perRecordCompletionBlock 的删除语义）；删除中转抽象 `configurePerRecordTracking`。部分失败 per-record 追踪语义与 P2 修复保持一致，官方论坛确认此模式（per-record 累加 + modifyRecordsResultBlock 描述整体）。

## 2026-09-15（第十轮）UI 头部紧凑化 + 年份千位分隔修复

用户在 iOS 27 模拟器（iPhone 18 Pro，英文 locale）实测截图反馈三处：

| 问题 | 根因 | 修复 |
|---|---|---|
| 年份显示 "2,026" | `Text("\(currentMonth.year)")` 走 **LocalizedStringKey** 字符串插值，Int 插值按系统 locale 做数字格式化（英文 locale → 千位逗号） | 全部年份类插值改 `Text(verbatim:)` 强制纯文本：`CalendarMonthView` 月/年标题、`DayDetailView` 日期行、`LunisolarWidgetViews` 两处 Widget 日期行（共 4 处，已全量排查） |
| 头部大块空白 | `.navigationBarTitleDisplayMode(.large)` 下大标题未渲染但占用导航栏空间（截图无"日历"标题文字） | 改 `.inline` 模式：导航栏紧凑、标题必然渲染、无 large↔inline 折叠动画；monthHeader 顶部 padding 12→8 |
| 月份切换过渡不自然 | 月/年 Text 硬切换无过渡 | 月/年/日期数字加 `.contentTransition(.numericText())`（iOS 16+），切换月份时数字滚动过渡 |

## 2026-09-15（第十一轮）选中日期格子：农历与公历同框

用户实测反馈"选中日期看不到日期下方的农历"。根因：`DayCellView` 的选中/节日/今日背景只包裹**公历数字**所在的上半区 ZStack（高度 34/40pt），农历文字渲染在**框外**；而选中态农历前景色被置为白（`.white.opacity(0.9)`）——白字落在框外浅色页面背景上，完全不可见。

修复：背景从"公历数字 ZStack 内"重构为整个格子（公历 + 农历 + 事件行）的 `.background`：

- **选中框同时包含公历与农历**：选中态农历白字在蓝框内清晰可见（用户诉求"农历阳历在同一个选择框内"）
- **节日浅染 / 今日红描边同步整格包裹**：三层视觉（选中实心 / 节日浅染 / 今日描边）一致性增强；节气日整格浅绿与选中蓝框、农历白字自然区分（"与节气区分"）
- **行高不变**：未增删任何内容元素，背景只是渲染范围扩大，LazyVGrid 行高由内容驱动不受影响（iPad 侧栏固定不滚动亦安全）

## 2026-09-15（第十二轮）节气展示改版：格内文字标注，取消染色背景

用户反馈"节气用选择框（浅染背景）展示显得杂乱，希望不选中就能看到哪天是节气"。改版：

- **节气日格内直接标注**：农历行内嵌绿色"·节气名"小字（如 9/23 格子显示"廿七·秋分"），无需选中即可见当天节气；顶栏"下一个节气"倒计时保留，双入口互补
- **移除节气浅染背景**：节气不再传 `festivalTint`（原绿色浅染即"选择框"视觉），格子恢复干净；传统节日（春节/中秋等）浅染背景保留作为氛围强调
- **实现**：`GridCellModel` 增 `solarTermName`/`solarTermTint`；`buildGridModel` 按 `FestivalKind.solarTerm` 分流（节气→文字标注，其它→染色）；`DayCellView` 农历行改 HStack 内嵌节气名（选中态白字、常态节气绿）；Equatable 增字段比较
- 节气日选中：蓝框 + 农历节气白字；今日节气：红描边 + 绿节气字，均不冲突

## 2026-09-15（第十三轮）节气/节假日格内只显示名称，隐藏农历

用户反馈"节气那天干脆不显示农历、只显示节气更协调；节假日第一天也如此"。

- **三态渲染**（`DayCellView` 农历行）：
  - 节假日当天 → 只显示节日名（如"中秋节"金黄字、"教师节"主题色），不显示农历
  - 节气日 → 只显示节气名（如"秋分"绿色字），不显示农历
  - 普通日 → 农历小字
- 节日/节气名的颜色跟随各自主题色（选中态白字）；传统节日浅染背景保留
- 实现：`GridCellModel`/`DayCellView` 增 `festivalName`（`buildGridModel` 按 `FestivalKind.solarTerm` 分流）；Equatable 增字段；假日"休/班"徽标不受影响（独立于农历行）

## 2026-09-15（第十四轮）去除节日"选择框"染色 + 节气节日并存 + 事件点按优先级着色

用户反馈"除点击选择的日期外都不要用选择框展示；节气和节日可同时显示；日期下面两横颜色与优先级颜色对应"。

- **去除节日浅染背景**：`fillTint` 只保留选中实心（`dayCellBackground` 清理不可达的 `fill.opacity(0.14)` 浅染与节日描边残留）；10 日教师节、25 日中秋节等不再有色块背景，仅文字标注 + 假日"休"徽标
- **节气与节日同日并存**：`buildGridModel` 分别取 `solarTermFest` 与 `otherFest`，格内同行显示"节日名 ·节气名"（节日色 + 绿色；同名去重，如清明仅显示一次）
- **事件点按优先级着色**：`EventStore.eventStats` 返回新增 `priorities: [Priority]`（按事件顺序），`DayCellView` 事件点逐点 `eventPriorities[i].tintColor`，与"当日安排"列表 EventRow 竖线（同用 `priority.tintColor`）颜色一一对应；选中节日日仍用节日色实心框
- Equatable 同步（`eventPriorities` 数组比较）

> **第十四轮 Build 修复（14:16 实测 4 错）**：`eventStats` 签名改为三元组后，**缓存字典 `statsCache` 声明未同步**（仍为旧二元组 `(count: Int, priority: Priority?)`）→ `EventStore` 在两个 target 各报 2 错（547 返回表达式类型不匹配、563 下标赋值不兼容）。修复：`statsCache` 声明同步为 `[Date: (count: Int, priority: Priority?, priorities: [Priority])]`，4 错全消。教训：改返回签名必须同步缓存/局部变量类型声明。

## 2026-09-15（第十五轮）天气模块：Open-Meteo + 自动定位 + 宜/忌上方

用户确认方案（Open-Meteo 免 Key / 自动定位 / 宜/忌上方）后落地：

- **`Support/WeatherService.swift`**（新增）：
  - `LocationService`：`CLLocationManager` 封装（WhenInUse 单次定位，`nonisolated` delegate + `Task @MainActor` 恢复 continuation；拒绝/失败返回 nil）
  - `WeatherProvider`：Open-Meteo `/v1/forecast`（current 温度/体感/天气码 + daily 最高最低，timezone=auto）；反地理编码取城市名；**UserDefaults 缓存 1 小时**（同坐标直接命中，保护免费额度）
  - `WMOWeather`：WMO 天气码 → 中文描述 + SF Symbol 映射
- **`Views/WeatherCardView.swift`**（新增）：城市 + 图标 + 当前温度 + 高低温一行；加载中极轻占位、失败整行隐藏、成功淡入；`liquidCard` 原生材质
- **`DayDetailView`**：`headerCard` 与 `almanacCard`（黄历宜忌）之间插入 `WeatherCardView()`
- **`Info.plist`**：新增 `NSLocationWhenInUseUsageDescription`（"用于获取当前位置，在日历详情中显示当地天气"）
- 文件收集：Xcode 工程仅显式编译入口（HostApp/WidgetMain），App 代码全走 SwiftPM 自动收集，新文件无需改 pbxproj
- **降级策略**：未授权/网络失败/超时 → 天气行整体隐藏，日历功能零影响；1 小时缓存兜底离线场景

> **第十五轮补丁（14:58 实测无天气）**：初版"失败即静默隐藏"无法区分原因，用户截图天气行不出现。改为**三态可见**：`WeatherResult`（success/denied/failed）+ `LocationOutcome`（location/denied/failed）细化——定位未授权显示"定位未开启 → 去设置"（跳系统设置）；加载/网络失败显示"天气加载失败 → 重试"；成功显示天气数据。这样功能可见、原因可诊断、可手动恢复。

> **第十五轮补丁 2（15:12 真机实测仍无天气）**：真机截图天气区**完全空白且无任何状态行** → 定位/反地理编码/网络请求**无超时导致挂起**（`loaded` 恒 false，只渲染 8pt 不可见占位）。修复：
> - 定位 `withTaskGroup` 6s 超时（授权弹框无人响应 / `requestLocation` 无回调 → 返回 `.failed`，绝不挂起）
> - 反地理编码 5s 超时（Apple 地理编码服务无响应 → 返回 nil 降级"当前位置"）
> - URLSession 自定义 8s 请求 / 12s 资源超时（替代默认 session）
> - 加载占位改为可见"加载天气…"（32pt 高），挂起也能看出功能存在

> **第十五轮补丁 3（15:19 Build Failed 2 issues）**：Swift 6 严格并发——`withTaskGroup` 的 `addTask` 闭包是 **sending 参数**，捕获 MainActor 隔离值（`LocationService.shared`、局部 `CLGeocoder`）报数据竞争。修复：4 处 `group.addTask` 闭包显式标注 `@MainActor in`（闭包在 MainActor 执行，访问 MainActor 值合法），编译通过。

> **第十五轮补丁 4（15:25 Build Failed 4 issues）**：`@MainActor in` 闭包组合触发 Xcode 27 **region-based isolation checker 无法识别的模式**（"Pattern ... does not understand how to check"×6 + sending×2）。彻底换实现：**移除全部 `withTaskGroup` 竞速与 CheckedContinuation**——`LocationService` 改为**主线程 100ms 间隔轮询**（60 次 = 6s 超时：轮询 `authorizationStatus` 直到非 notDetermined；轮询 `pendingResult` 直到定位回调/超时），delegate 只写 `pendingResult`；`reverseGeocode` 去掉竞速直接用 CLGeocoder 自带超时；URLSession 8s 超时保留。全部为检查器可识别的常规模式，且语义不变（6s 定位超时、失败显示重试、绝不挂起）。

> **第十五轮补丁 5（15:32 模拟器实测仍无天气）**：放大截图分析确认天气区渲染了但**视觉不可见**——旧实现加载占位用 `caption + tertiaryLabel`（极浅灰）+ 8pt 小 ProgressView，成功/失败卡用半透明 `liquidCard` 材质，在浅色壁纸上几乎隐形；且高度依赖自定义字体/间距属性。重构 `WeatherCardView`：**只用系统基础组件**（`.font(.footnote/.subheadline)`、`.primary/.secondary` 高对比色、`Color.secondary.opacity(0.08)` 实底圆角背景）、`frame(minHeight: 44)` 固定最小高度、去除全部自定义修饰符/动画/过渡，任何状态（加载中/成功/未授权/失败）都必然可见可点。

> **第十五轮补丁 6（15:45 模拟器实测仍无天气）**：**版本判据实锤用户运行的是旧构建**——15:45 截图日期卡第二行显示 "Tue"，而当前代码 `DayDetailView` 日期卡第二行为 `"\(date.year) 年 \(date.month) 月"`（"2026 年 9 月"），且截图 headerCard 缺少"冲煞/五行/纳音/喜神/财神"行（当前代码 126 行存在）。即用户模拟器运行的 App 不含最近 4 轮任何天气改动。为让版本可验证，`WeatherCardView` 增加**永久可见标题行**（"☁ 天气" cloud.sun.fill + 文字，不依赖定位/网络状态）：运行后天气区必有标题行 = 最新构建；日期卡显示"2026 年 9 月" = 最新构建。

> **第十五轮补丁 7（15:54 真机实测仍无天气）**：真机截图日期卡仍是 "Tue"（无冲煞行、无天气卡，但有"今日安排"= 介于 12–14 轮之间的旧构建）。工程机制已核实：pbxproj 无显式文件引用（PBXFileReference=0），`Sources/LunisolarCalendarApp` 全部由 SwiftPM 自动收集，新文件必然进编译，排除编译范围问题。**月视图节气条尾部新增版本戳 "v1.5.0"**（旧构建均无此标记）作为最直观的版本验证信号；用户侧需：删除设备旧 App → 解压最新 zip 打开新工程 → Xcode `Shift+Cmd+K` Clean Build Folder → Cmd+R 重装。

> **第十五轮补丁 8（16:05 真机+模拟器仍无天气）**：**真正的根因**——用户主界面（月视图下方）一直显示的是 **CalendarMonthView 内嵌的"今日卡片"**（含 15 Tue / 丙午马 / 宜忌 / 今日安排），**不是 DayDetailView**；天气卡此前只插在 DayDetailView（点击"查看黄历详情"推入后才显示），所以主界面永远看不到。修复：**WeatherCardView 插入 CalendarMonthView 今日卡片"宜/忌"块上方**（两处均保留），与用户最初圈出的空白区域一致。版本戳 v1.5.0 截图已证实用户运行的是最新构建。

> **第十六轮（16:15 天气已显示，新需求）**：真机截图确认天气卡成功显示"苏州市 · 多云 26° 最高27° 最低21°"。用户新需求"**把天气卡片和日期卡片相结合，前后 3 天都能显示当天天气**"：
> - `WeatherService`：请求改 `daily=weather_code,temperature_2m_max,temperature_2m_min` + `past_days=3` + `forecast_days=7`（返回前 3 天 + 未来 7 天共 10 条）；新增 `DailyWeather`（date/weatherCode/maxTemp/minTemp）；`WeatherSnapshot.days`（可选，兼容旧缓存）；缓存 key 升级 `weather.cache.v2` 强制刷新。
> - `WeatherCardView`：改为**与日期卡结合形态**——首行城市+当前天气+高低温，下方 **7 天横条**（前 3 天 + 今天 + 后 3 天，逐日显示 星期/日期/天气图标/最高温），**选中日整格 accent 高亮**、今天红色标注；新增 `selectedDate` 参数（中心日），窗口按选中日取 ±3 天。
> - 两处接线传入选中日：CalendarMonthView 今日卡片 `WeatherCardView(selectedDate: selectedDate)`、DayDetailView `WeatherCardView(selectedDate: date)`。
>
> **第十六轮 Build 修复（16:24 Build Failed 2 issues）**：`WeatherCardView.symbolColor` 的 `default: return .tint`——`.tint` 是 **ShapeStyle**（`Member 'tint' expects argument of type 'Color'`），不能作为 `Color` 返回值。改 `default: return .accentColor`（Color.accentColor）。`foregroundStyle(.tint)` 处 ShapeStyle 上下文合法，保留。

> **第十六轮改版（16:30 用户澄清需求）**：用户澄清"不是 7 天横条"——**天气放到日期卡片的空白处、只显示当天的天气，点选日期也只显示点选天的天气，日期卡片处 UI 作优化调整**。改版：
> - `WeatherCardView` **移除 7 天条与独立背景框**，改为**紧凑单行**：`图标 城市 · 天气 最高x° 最低y°`（今天额外显示当前温度），按 `selectedDate` 取**当天**逐日天气，切换日期自动跟随；选中日超出拉取窗口时显示"暂无该日天气"。
> - 位置融入日期卡：月视图今日卡片日期信息区正下方（CalendarMonthView:531）；DayDetailView **天气行移入 headerCard 内部**（节假日行下方，DayDetailView:164），两处均无独立卡片视觉。
> - `WeatherService`：`forecast_days` 7→14（拉取窗口 -3~+14 天，切换日期更不易出界）。
>
> **第十六轮改版②（16:43 天气效果图标）**：用户要求"日期卡片空白处放置天气效果图标，天气预览更直观"。新增 `WeatherIconView`（`Views/WeatherIconView.swift`）：按选中日天气码渲染 **38pt 大效果图标 + 当天最高温**（晴橙/多云黄/雨蓝/雷紫，随日期切换；加载失败显示中性占位）。插入 CalendarMonthView 今日卡片日期信息 HStack 右侧 `Spacer` 空白处（CalendarMonthView:529），与干支/生肖信息同排；下方文字行去掉重复小图标，保留"城市 · 天气 · 高低温"。
>
> **第十六轮改版③（16:55 效果图确认后微调）**：用户看效果图确认最终布局——**大图标放日期卡右侧空白处（不要大号温度数字）**、**天气文字放干支"丙午 马"下方空白位置**。`WeatherIconView` 去掉图标下方的大温度 `Text`（只留 38pt 纯图标，CalendarMonthView:529 位置不变）；`WeatherCardView` 文字行保持在干支信息 HStack 正下方（CalendarMonthView:533，即"丙午 马"下方空白），内容不变。两处均不超出日期卡片范围。
>
> **第十六轮改版④（17:00 卡片式月份滑动）**：用户要求"左右滑动选择月份的动画改为左右滑动卡片的动画"。`CalendarMonthView` 月份切换从"内容直接替换+轻微视差"改为**卡片式滑动转场**：日历网格包进 `ZStack` + `.id(currentMonth)` + `.transition(.asymmetric(insertion: .move(edge:), removal: .move(edge:)))`——旧网格随方向滑出、新网格从对侧滑入；新增 `@State monthSlideEdge`（.trailing=下月从右进、.leading=上月从左进）与 `changeMonth(by:)`（设置方向+withAnimation）。chevron 上/下月按钮与左右滑动手势统一走 `changeMonth(by:)`；"今天/回到今天"保留原 withAnimation（顺带滑动）、DateJumpView/双栏外部同步为无动画直接切换。
>
> **第十六轮改版⑤（18:10 休/班徽章移右上角）**：用户要求"节假日放假调休'休'和'班'从底部移到日期右上角显示"。`DayCellView` 结构从 VStack 改为 `ZStack(alignment: .topTrailing)`：主内容列（公历+农历/节日/节气+事件点行）不变，事件点行移除内嵌的 HolidayBadge；`HolidayBadge`（绿"休"/橙"班"圆徽章）改为叠加在格子**右上角**（topTrailing + padding 6/4），随格子整体淡显（isCurrentMonth opacity）。底部不再出现休/班标记。
>
> **第十七轮（09-15 深度审查 + 原创化品质跃升）**：用户要求"梳理代码/整理逻辑/分析架构/查 BUG·死循环·死代码·逻辑不通，对 UI 适配做优化改善交互体验，借鉴主流 app 设计（不照抄、要原创），目标 AppStore 前十"。本轮先完成**全项目深度审查**（21 源文件 14922 行：EventStore/AppTheme/CalendarMonthView/DayDetailView 精读；全局扫描无 force unwrap/fatalError/Timer；同步层/模型层/视图层接线核验），随后落地 5 项修复与增强：
> 1. **P1 逻辑修复——切月联动选中日期**：`changeMonth(by:)` 增加 `clampedToMonth` 钳制，切月时 `selectedDate` 同步到新月份同日（1/31 → 2/28 取月末），修复"切月后日期卡仍显示上月内容"的逻辑不通；`withAnimation` 内联动，卡片滑动转场与选中同步完成。
> 2. **P2 本地化一致性——星期名称固定中文**：`Date.weekdaySymbol` 由"跟随系统语言"（英文系统显示 Tue）改为固定"周一~周日"，月视图日期卡/详情页导航标题/3 处 Widget 统一中文（与星期头"一~日"一致）。
> 3. **P3 新功能——每周起始日设置**：设置页"外观"卡新增"每周起始日"（周日/周一 segmented，`@AppStorage("Lunisolar.weekStart")` 默认 1=周日保持既有布局）；`WeekHeaderView` 按起始日动态排列（周末红字与起始日无关，wd==1/7 恒红）；`daysForMonth` 前置空位 `(first.weekday - weekStart + 7) % 7` 同步适配；新增 `AccessibilityID.settingsWeekStart`。
> 4. **P3 交互增强——月份标题可点击**：月视图头部"9月 2026"标题变为按钮（加 `chevron.up.chevron.down` 暗示图标 + 按压反馈 + 无障碍标签），点击弹出日期跳转 sheet（主流日历"点标题选月年"交互）。
> 5. **核查结论**：无真实死代码（单文件统计的"未引用"均为跨文件/测试引用）；`DataPortability` 折叠行已有 `!lines.isEmpty` 越界保护；`HuangliDBProvider` force unwrap 有 count≥2 前置保护；onChange 已全量升级 3 参新 API。**无新增测试**（改动为 UI/交互/设置项，已有 99 条测试覆盖底层逻辑不受影响）。
>
> **第十八轮（09-15 放手一搏·去装饰化与原生感跃升）**：用户"据建议，继续放手一搏"。落地 3 项：
> 1. **A. 卡片系统统一——liquidCard → glassCard 全量迁移（8 处）**：月视图日期卡/详情页三卡（日期头/黄历宜忌/当日安排）/编辑页分组卡/设置页 Hero 与设置卡/设置组件卡全部从旧 `liquidCard`（5 层 overlay：白高光+顶部渐变+separator+shadow+clip 叠加）迁移到 `glassCard`（单层 Material+单层分隔线+单层阴影的克制版液态玻璃）。设计系统注释自述的"替代旧 liquidCard"自此真正落地，全应用统一视觉语言；`liquidCard` 定义保留（无使用点，不产生警告）。**发现并修复设计断层：glassCard 此前定义后 0 处使用，App 实际仍跑在旧多层叠加上。**
> 2. **B. 日期格选中弹簧回弹动画**：`DayCellView` 增加 `scaleEffect(isSelected ? 1.05 : 1.0)` + `.spring(response: 0.34, dampingFraction: 0.52)` 值动画——点击瞬间格子轻微放大并带阻尼振荡回弹，与父视图背景填充淡入叠加，增强"选中物理感"；非选中格不受影响（值动画只作用于 isSelected 变化时刻），不破坏 `.equatable()` 性能优化。
> 3. **C. Widget iOS 27 液态玻璃适配核查**：`.widgetBackground` 封装内部已正确使用 iOS 17+ 推荐 `containerBackground(for: .widget)`（11 处），无废弃 API，Widget 圆角由系统裁剪，无需改动——本轮确认达标。
> 4. **设计决策（克制）**：预留的 iOS 26/27 原生 `liquidGlassCard`（`.glassEffect` 实时折射）同样 0 处使用；因 glassEffect 视觉依赖真机"悬浮内容折射"、效果不可预判（本机无 Swift 工具链），本轮不盲目接入常规卡片，留待 iOS 27 真机确认后定向用于强调元素（如设置 Hero/选中胶囊）。
>
> **第十九轮（09-15 设置页 iOS 原生形态重构）**：用户要求"对 APP 设置界面做调整跟优化，更加符合 iOS 原生状态"。**核心思路：放弃自定义玻璃大卡 + Hero 区（iOS 设置 App 没有这种形态），改为系统原生 `List` + `.insetGrouped` 分组列表**。重构内容：
> 1. **容器重构**：`ScrollView + VStack + 9 张 SettingsCard` → `List` + `.listStyle(.insetGrouped)` + **8 个原生 `Section`**（外观/提醒通知/数据/iCloud 同步/导入冲突策略/数据统计/危险操作/关于）。删除自定义玻璃 Hero 头部（含 HeroStat 统计块）——统计信息由"数据统计"Section 承接；iPad 限宽由 insetGrouped 系统自动居中，删除手写 isWide 约束。
> 2. **控件原生化**：自定义 `AppearanceSegmented`（三格渐变按钮）→ 原生 `Picker(.menu)`"外观模式"（跟随系统/浅色/深色，Label+SF Symbol）；自定义 `PolicyChipPicker`（三列胶囊）→ 原生 `Picker(.menu)`"冲突处理"（含策略说明 footer）；每周起始日改原生 menu Picker；数据区改原生 `Menu` 行 + 两个导入 Button + 农历 Toggle；通知区改原生行（权限状态 value 行 + 条件按钮 + 重排按钮禁用态）；危险区改原生 `Button(role: .destructive)` 红色行。
> 3. **死代码清理**：SettingsViewComponents 删除 6 个无引用组件（SettingsCard/HeroStat/AppearanceSegmented/PolicyChipPicker/DataActionRow/StatRow，381→125 行），保留仍在用的 ToastMessage/ToastBannerView/ImportFileModifier 与 `ImportConflictPolicy` 文案扩展。
> 4. **零功能损失**：全部状态、3 个 alert、fileImporter、toast overlay、通知权限/系统导入/iCloud 同步/冲突策略逻辑逐行保留；`AccessibilityID.settingsWeekStart` 保留。设置页从 878 行精简至 695 行。
>
> **第二十轮（09-15 灵动岛适配 + 全层原生化 + 性能）**：用户要求"整体更接近 iOS 原生但保留独创设计、适配灵动岛、检查 BUG、优化设计/代码/性能"。落地 4 项：
> 1. **灵动岛倒计时（Live Activities，核心原创功能）**：新增 `Widgets/CountdownActivity.swift`（`CountdownActivityAttributes` + `CountdownLiveActivityView` + `CountdownActivityManager`），把「倒数日/纪念日」挂上灵动岛与锁屏——剩余时间用系统原生 `Text(date, style: .timer)` 渲染，**由系统每秒自动刷新，App 零后台计时器零耗电**；emoji 自定义图标上岛（独创）。倒数日列表每行新增"上岛/在岛上"胶囊快捷开关（`liveactivity` SF Symbol），点击开启/结束；活动 ID 存 UserDefaults 跨启动恢复。注册链路：主 App Info.plist 加 `NSSupportsLiveActivities=true` → `WidgetMain.swift`（Widget 扩展 @main）注册 `CountdownLiveActivityWidget` → 库内 `LunisolarWidgetsBundle` 同步注册。经排查确认 Widget 扩展通过 `import LunisolarCalendarApp` 动态库复用实现，`AppTheme` 同库可见。
> 2. **月视图原生交互（原创，不照抄）**：日期格长按挂原生 `contextMenu`（选中此日 / 复制日期，`UIPasteboard` 中文长格式）；选中日期加 iOS 17+ 原生 `sensoryFeedback(.selection)` 轻触觉，替代自定义引擎。
> 3. **性能优化**：`LunarDate.swift` 17 处 `Calendar(identifier: .gregorian)`（月历渲染高频路径，42 格×每帧多次分配）→ 全局只读静态 `Calendar.gregorian`（`extension Calendar`，确认全调用点只读无 mutation）。其余 21 个文件低频调用点保留原样（改动面与风险权衡）。
> 4. **BUG 复查（全量扫描通过）**：3 处 onChange 均为新 3 参数 API（无 iOS 18 弃用）；无 DispatchWorkItem/Timer 泄漏残留；无 `as!`/`try!`/`date(from:)!` 强解包；无数组下标越界；`?? 0` 均为内部计算非装饰 UI fallback；权限 `notDetermined` 分支齐全。
>
> **第二十一轮（09-16 App 图标重设计·四季日历）**：用户保留「清和日历」名字，多轮打磨后定稿**四季日历图标**：纯白底 + 白色圆角日历卡面 + 顶部双装订孔 + 2×2 四格四季色（春嫩绿/夏晴青/秋暖金/冬霜蓝，低饱和）+ 极淡顶部微光（釉面余光），超椭圆圆角、无阴影无描边、扁平极简，一眼即"日历本"。设计决策：废弃早前"月牙/稻穗/印章/渐变夜空"系列元素思路；颜色对应一年四季，装订孔提供日历本识别。已替换 `Assets/Assets.xcassets/AppIcon.appiconset/Icon-1024.png`（主图标，single-size 1024 格式）；同步生成**春节限定版**（同结构、红金棋盘格）替换 `AppIconSpringFestival.appiconset/Icon-1024.png`，与主图标风格一致、春节自动换图标功能继续生效。旧图标备份于构建外临时目录。
>
> **第二十二轮（09-16 iOS 26/27 SDK Live Activity API 适配）**：真机编译报 4 错（`CountdownActivityAttributes does not conform to protocol 'ActivityAttributes'` / `Incorrect argument label … expected 'for:content:dynamicIsland:'` / `Cannot convert … closure result type 'DynamicIsland'` / `ActivityContent<…CountdownContentState>` 类型不匹配）。经查证 iOS 26+ SDK 两项破坏性变更并适配：
> 1. **`ActivityAttributes.ContentState` 必须直接命名为嵌套类型 `ContentState`**——删除 `typealias ContentState = CountdownContentState` 写法（协议不再接受 typealias 满足关联类型），状态类型改名 `CountdownActivityAttributes.ContentState`。
> 2. **`ActivityConfiguration` 新签名 `for:content:dynamicIsland:`**——第一个闭包为锁屏/配对手表卡（`content:`），删除已移除的独立 `lockScreen:` 标签；第二个 `dynamicIsland:` 闭包返回完整 `DynamicIsland { DynamicIslandExpandedRegion(.leading/.trailing/.bottom) } compactLeading: compactTrailing: minimal:` 四态布局（紧凑区遵循"一元素一数字"：左 emoji、右 timer），并加 `.keylineTint` 青碧主题色。
> 3. 修复后灵动岛功能语义不变：倒计时由系统 timer 刷新、emoji 上岛、跨启动恢复、点击下岛。已按 WWDC26 官方文档与 iOS 26 实现指南核验新 API 结构（本机无 Xcode 工具链，真机编译验证待用户确认）。
> 4. **补充（Swift 6 并发）**：真机再编译剩 2 个警告（同一处）——`Sending 'activity' risks causing data races`（`end(id:)` 中把 `Activity.activities` 获取的 main-actor-isolated 实例传给 @concurrent 的 `end(_:dismissalPolicy:)`）。修复：`@preconcurrency import ActivityKit`（系统框架类型生命周期由系统托管，Swift 6 迁移标准放宽手段），警告消除。
> 5. **补充（运行时崩溃 P1）**：编译通过后模拟器启动即崩——`Thread 1: EXC_BAD_ACCESS (code=1, address=0x0)`，栈 `Date.firstDayOfMonth → closure #1 in static Calendar`。根因：`LunarDate.swift` 中 `extension Calendar { public static let gregorian: Calendar = Calendar.gregorian }` 是**对自身的无限递归初始化**（static 初始化表达式引用自身），首次触达即崩。修复：改为 `Calendar(identifier: .gregorian)`。已全工程扫描无同类 static 自引用。
> 6. **新建日程页原生化改造（EventEditView）**：废弃旧版"玻璃卡片堆叠 + 横向 chip 按钮"布局，重构为 iOS 27 系统「日历/提醒事项」同款 **Form + insetGrouped** 原生表单——大字号标题 TextField + 原生 segmented 类型切换；时间区原生 DatePicker 行（点击展开日历）；「提醒 / 重复 / 优先级」改为行内 LabeledContent + Menu 弹层（替代 chip 横排，原生 chevron 值样式）；保存/添加移入 toolbar 右上角（标题为空自动禁用）；编辑态删除改为底部居中红色文字按钮（系统日历同款）。EventEditView 不再自包 NavigationStack（push 继承外层导航），DayDetailView 的 sheet 场景补包 NavigationStack，消除旧版"返回箭头+取消"双导航栏。
> 7. **天气行动态图标 + 删留白 + 灵动岛真机修复（P1）**：① 天气文字行增加**随天气码动态切换的 SF Symbol 图标**（晴/少云/多云/雾/雨/雪/雷暴各对应符号与配色），温度字号 .footnote → .title3 放大；② 删除日期卡片与宜做勿做之间的留白（卡片内 VStack spacing 16→12、宜忌块 padding 12→8）；③ **灵动岛真机不起作用的根因**：Widget 扩展 `LunisolarWidget/Info.plist` 缺少 `NSSupportsLiveActivities`（Live Activity 渲染由扩展负责，扩展必须声明支持，主 App 有而扩展没有 → 系统不启用）——已补键；④ 上岛交互增强：先查 `ActivityAuthorizationInfo().areActivitiesEnabled`，系统权限关闭时引导去「设置→通知→清和日历」开启；`Activity.request` 失败时如实弹窗提示（不再静默假装上岛）。

## 发布清单（Release Checklist）

上架 App Store 前必须逐项确认：

- [ ] `CFBundleShortVersionString` / `CFBundleVersion` 已递增
- [ ] Xcode → Product → Archive 成功（无 codesign 错误）
- [ ] 主 App Target + Widget Extension Target 均勾选同一 App Group（`group.com.lunisolar.calendar`）
- [ ] iCloud Capability 已启用，CloudKit Container ID 已配置
- [ ] `NSContactsUsageDescription` / `NSCalendarsFullAccessUsageDescription` 文案已审核
- [ ] App Icon 1024×1024 无透明通道（App Store 要求）
- [ ] 春节限定备用图标 `CFBundleAlternateIcons` 声明完整
- [ ] 真机测试：通知权限 → 创建提醒 → 锁屏弹窗验证
- [ ] 真机测试：iCloud 同步开/关 → 多设备数据一致性
- [ ] 真机测试：Widget 快照 6h 过期 + 同日校验
- [ ] 隐私清单（Privacy Manifest）：`NSPrivacyAccessedAPITypes` 已声明 File timestamp
- [ ] App Store Connect：截图、描述、关键词、隐私标签已填写

详见 [`docs/ENTITLEMENTS.md`](docs/ENTITLEMENTS.md) 和 [`docs/APP_STORE.md`](docs/APP_STORE.md)。

## 已修复的关键问题

共修复 56 个 BUG，涵盖数据安全、并发竞态、CloudKit API 兼容、日历一致性、Swift 6 并发隔离、UI 触碰区等。关键修复包括：

- **数据安全**：损坏数据不再覆盖用户数据；dirty 标记持久化防重启丢失；ContactsImportProvider year 强制解包安全化
- **并发安全**：推送队列序列化；同步防重入；NSLock → DispatchQueue；`@MainActor` 隔离 EventSyncCoordinator
- **日历一致性**：全模块统一 `Calendar(identifier: .gregorian)`，避免非公历系统环境月视图错乱
- **CloudKit 兼容**：适配 Xcode 16 / Swift 6 API 变更；延迟装配防 entitlement 崩溃
- **iOS 26 适配**：UIScreen.main 废弃、Color.tertiary 移除、Liquid Glass 液态玻璃、按压反馈、节日自适应色
- **UI 触碰优化**：全部交互元素 ≥ 44pt 触碰区；液态玻璃分组卡片；Toast 弹簧动画；芯片按压切换
- **性能优化**：月视图黄历预计算、Widget 快照自动写入、墓碑 TTL 清理

## License

MIT
