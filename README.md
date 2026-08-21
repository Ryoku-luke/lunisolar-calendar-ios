# Lunisolar Calendar · iOS 中国农历日历

一款简洁的 iOS / iPadOS 日历应用，内置公历↔农历转换、黄历黄道吉日、日程 / 记事 / 提醒本地持久化 + 本地通知，界面遵循 iOS 标准设计规范，支持 iPhone 和 iPad 自适应布局。

## ✨ 功能

| 模块 | 说明 |
|---|---|
| 🗓️ 日历月视图 | **7×6** 标准网格、左右切换月份、今日高亮 + **"今天"快捷按钮**、周末红字、优先级色圆点；底部面板可展开为当日时间轴 |
| 🌕 中国农历 | 1900-2100 公历↔农历转换、闰月支持、干支纪年、十二生肖、月日中文名称；**农历↔公历双向查询**；边界 nil 保护 |
| 📜 黄历 | 黄道吉日综合判定（黄黑道六神 + 建除十二神 + 28宿）、宜/忌事项、冲煞、五行纳音、喜神财神方位；**离散数据库（2025-2028）+ 算法兜底** |
| 📝 三种事件类型 | 日程 (schedule) / 提醒 (reminder) / 记事 (note) |
| 🔁 重复规则 | 不重复 / 每天 / 每周 / 每月 / 每年 / 工作日 / **农历每年（父母生日·传统节日）** |
| 🏷️ 优先级 | 紧急 / 高 / 普通 / 低（带颜色标识） |
| 🔔 本地通知 | `UNUserNotificationCenter` 提醒推送、`isNotified` 防重复、删除/编辑自动取消旧通知；异步权限查询不阻塞主线程 |
| 💾 本地持久化 | JSON 自动保存到 App Documents，首启动带示例数据 |
| 📤 数据逃离机制 | **.ics 导入导出** (iCalendar RFC5545，支持折叠行展开) + **.csv 导出** + **.json 全量备份**（含农历重复规则、通知状态）|
| 🔄 数据合并策略 | 导入冲突处理：`keepLatest` / `keepLocal` / `overwrite`；合并统计（新增/更新/跳过/无效）|
| 📱 系统数据导入 | **系统日历导入**（EventKit：EKEvent → CalendarEvent，RRULE 映射）+ **联系人导入**（CNContact 生日/纪念日，可选农历每年）；确定性 UUID 防重复导入 |
| ☁️ iCloud 同步 | 抽象接口 `ICloudSyncProvider` 协议 + `MockCloudKitProvider` 内存模拟容器，支持增量推送/拉取/墓碑删除 |
| 📊 Widget 小组件 | 3 种样式：**今日黄历概览**（宜忌+冲煞）、**农历日期卡片**（干支+节日）、**今日待办进度**（进度环+真实待办列表）；App Group 共享快照 |
| 🎨 节日主题色 | 春节/中秋等传统节日自动切换背景渐变和主题色点缀 |
| 📱 iPad 适配 | `NavigationSplitView` 双栏布局（左月历 + 右日详情），cell 尺寸自适应，Form 限宽 720pt；`horizontalSizeClass` 自动切换 |
| ⚙️ 设置页 | 通知权限状态（异步查询）+ 重新调度、导入导出入口、系统数据导入、冲突策略、数据清空（二次确认）、数据统计、版本信息 |
| 🧪 单元测试 | **53 个 XCTest** 覆盖农历真值 (17点) / 宜忌稳定性 / 冲煞 / ICS 往返 / CRUD / JSON 备份 / 合并策略 / Widget 快照 / 系统导入桥 |
| 🎨 iOS UI | SwiftUI · `NavigationStack` / `NavigationSplitView` · `.formStyle(.grouped)` · 语义色 · SF Symbol · 深浅色自适应 · FlowLayout 自动换行标签 |

## 📱 系统要求

- **iOS / iPadOS**: 17.0+
- **Swift**: 6.0
- **Xcode**: 16.0+

## 🚀 运行方式

### Xcode 直接运行（推荐）

1. Xcode → File → New → Project → **iOS App**
   - Interface: **SwiftUI** ；Language: **Swift**
   - Minimum Deployments: **iOS 17+**
2. 删除 Xcode 自动生成的 `ContentView.swift` 与 `<项目名>App.swift`
3. 将 `Sources/LunisolarCalendarApp/` 整个目录拖入 Xcode 工程（勾选 *Copy items if needed*、加入 App target）
4. ⌘R 运行即可

### Swift Package 方式（作为库集成）

在你的 `Package.swift` 里添加依赖：

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

### Widget 接入（Xcode 工程）

1. 创建 Widget Extension Target → `@main` 用 `LunisolarWidgetsBundle()`
2. 主 App 和 Widget Extension 同时勾上同一个 App Group Capability（例如 `group.com.you.lunisolar`）
3. 主 App 启动时设置 `EventStore().widgetAppGroupID = "group.com.you.lunisolar"`

## 🏗️ 项目结构

```
Sources/LunisolarCalendarApp/
├── App/
│   └── LunisolarCalendarApp.swift     # @main 入口 + AdaptiveRootView（iPhone/iPad 自适应）
├── Models/
│   ├── LunarDate.swift                # 公历↔农历算法（1900-2100, JSON资源化+fallback）
│   ├── Huangli.swift                  # 黄历：吉日 / 宜忌 / 冲煞 / 五行 / 神位
│   └── CalendarEvent.swift            # 事件模型（含.lunarAnnually + isNotified + Codable + Sendable）
├── Stores/
│   └── EventStore.swift               # @MainActor @Observable + JSON持久化 + merge + clearAll + Widget快照
├── Support/
│   ├── ColorExtensions.swift          # iOS 语义色 + 屏幕尺寸辅助
│   ├── NotificationManager.swift      # UNUserNotificationCenter（授权/调度/取消 + 异步查询）
│   ├── DataPortability.swift          # .ics/.csv/.json 导入导出 + 冲突策略 + 合并统计
│   ├── FestivalManager.swift          # 公历/农历节日匹配 + 主题色
│   ├── HuangliDBProvider.swift        # 离散黄历数据库（2025-2028 JSON）+ 算法兜底
│   ├── HuangliGenerator.swift         # 黄历算法生成器（离线兜底）
│   ├── LunarDataProvider.swift        # 农历数据表 JSON 资源加载器
│   ├── WidgetSnapshotStore.swift      # Widget 共享快照（App Group → Documents → tmp 三级回退）
│   ├── ICloudSyncProvider.swift       # iCloud 同步抽象协议 + SyncRecord + EventSyncCoordinator
│   ├── MockCloudKitProvider.swift     # 内存模拟云端容器（本地测试/预览）
│   ├── SystemImportBridge.swift       # 系统导入桥：DTO + 协议 + Mapper（确定性 UUID）+ Aggregator
│   ├── CalendarImportProvider.swift   # EventKit 桥：EKEvent → CalendarEvent（#if canImport(EventKit)）
│   ├── ContactsImportProvider.swift   # Contacts 桥：CNContact 生日/纪念日 → CalendarEvent（#if canImport(Contacts)）
│   └── FlowLayout.swift               # Layout 协议流式标签排列（iOS 16+）
├── Widgets/
│   ├── LunisolarWidgetProvider.swift  # Widget EntryProvider + Timeline
│   └── LunisolarWidgetViews.swift     # 3 种样式视图
├── Resources/
│   ├── lunar_calendar.json            # 农历数据表（201年，编译为Bundle资源）
│   └── huangli_db.json                # 离散黄历数据库（2025-2028，宜/忌/冲煞/五行/神位）
└── Views/
    ├── CalendarMonthView.swift        # 主界面：月视图 + 今天按钮 + 底部面板（iPad 双栏联动）
    ├── CalendarComponents.swift       # 星期表头 / DayCell 组件（自适应尺寸）
    ├── DayDetailView.swift            # 黄历详情 + 当日日程列表（FlowLayout 标签）
    ├── EventEditView.swift            # 新建/编辑/删除（自动管理通知生命周期 + 农历重复规则UI）
    ├── EventRow.swift                 # 事件列表项（重复规则标签 + 优先级色条）
    └── SettingsView.swift             # 设置页（通知+导入导出+系统导入+冲突策略+清空+Toast）

Tests/LunisolarCalendarTests/
└── LunisolarCalendarTests.swift       # 53个 XCTest（农历/黄历/事件/导入导出/合并/Widget/系统导入）
```

## 🔧 构建 & 测试（命令行）

```bash
swift build        # 编译所有 Target
swift test         # 运行 53 个单元测试（Linux 仅模型层，Apple 平台全量）
```

> Linux 环境仅能验证模型层（农历 / 黄历 / 事件 CRUD / 导入导出 / 系统导入桥），SwiftUI 视图编译需要 iOS 或 macOS SDK。EventKit/Contacts/WidgetKit 代码用 `#if canImport` 包住，Linux 编译不报错。

## 🧪 单元测试覆盖（53/53 通过）

### LunarDateTests（4个）
- `testLunarConversionAccuracy`：**17 个农历真值点**（基准日/2020闰四月/2023闰二月/春节/今日/2100上界）
- `testLeapMonthYears`：2020→4 / 2023→2 / 2024→0
- `testBoundaryNilSafe`：1899 & 2101 → `lunarDateSafe` 返回 nil
- `testReverseConversion`：2024正月初一 → 公历2024-02-10

### HuangliTests（3个）
- 宜忌稳定性（同日5次连续调用一致）
- 2024-10-01 冲龙煞北 验证
- 黄道吉日判定无崩溃

### CalendarEventTests（6个）
- endDate≤startDate 自动兜底
- 全天事件时长 = 86399s
- `.lunarAnnually` 农历每年重复匹配（闰月/非闰月年）
- 优先级排序（紧急>高>普通>低）
- ICS 导出→导入往返一致性
- CSV 导出格式正确

### EventStoreTests（3个）
- CRUD 完整流程
- `markNotified` 防重复通知
- 标题/地点/备注全文搜索

### DataPortabilityTests（4个）
- JSON 往返保留农历重复规则和 isNotified
- ICS 导入伪 UID 稳定性（重复导入不产生副本）
- ICS RRULE 解析（FREQ/BYDAY → RepeatRule）
- 三种合并策略（keepLatest/keepLocal/overwrite）

### WidgetSnapshotTests（4个）
- 快照读写往返
- 过期/错日回 nil
- 文件缺失回 nil
- EventStore.save 自动写快照并按优先级排序

### SystemImportTests（9个）
- DTO → CalendarEvent 字段全保留
- 确定性 UUID 稳定性（同 sourceID 多次映射同一 UUID）
- 不同 sourceID 不同 UUID
- Stub Provider 授权/未授权
- Aggregator 多源合并 + 失败收集
- 联系人生日 DTO 映射（yearly / lunarAnnually）
- 端到端 Provider → Aggregator → merge 重复导入无副本

## 📦 农历数据资源化

农历核心数据表已从硬编码迁移为 Bundle 资源：

```
Resources/lunar_calendar.json
├── version: 1
├── data: [201个 hex 字符串]  # 1900-2100 年
└── bit 编码:
    bit0-3  闰月月份(0=无)
    bit4-15 12个月大小(1=30天)
    bit16   闰月大小(1=30天)
```

加载策略：`Bundle.module` JSON 优先 → 内置 fallback 数组兜底（**JSON 加载失败也能正常工作**），方便未来云配置 / 热更新替换。

## 📜 离散黄历数据库

放弃纯算法推导，内置 2025-2028 年固定宜/忌枚举值：

```
Resources/huangli_db.json
├── version: 1
├── range: ["2025-01-01", "2028-12-31"]
└── days: { "yyyy-MM-dd": { yi: [], ji: [], chong: "", sha: "", wuXing: "", shenWei: "" } }
```

查询策略：离散库命中 → 返回固定数据；未命中 → 算法生成器兜底。

## 📥 导入导出

| 格式 | 导出 | 导入 | 用途 |
|---|---|---|---|
| **.ics** (iCalendar) | ✅ RRULE/优先级/全天状态 | ✅ RFC5545 折叠行展开 + SUMMARY/DTSTART/DTEND/LOCATION/RRULE | 系统日历/Google日历/Outlook |
| **.csv** (表格) | ✅ 11列完整属性 | — | Excel/Numbers 分析/打印 |
| **.json** (全量备份) | ✅ 含农历重复规则/通知状态/时间戳 | ✅ 保留全部字段 | 换机备份/数据迁移 |

入口：主界面右上角菜单 → **设置** → 数据管理。

## 📱 系统数据导入

| 来源 | 权限 | 映射 | 防重复 |
|---|---|---|---|
| **系统日历** (EventKit) | `requestFullAccessToEvents` (iOS 17+) | EKRecurrenceRule.frequency → RepeatRule | sourceID SHA-1 → 确定性 UUID |
| **联系人** (Contacts) | `requestAuthorization(.contacts)` | 生日→reminder/high/yearly，纪念日→reminder/normal/yearly | 同上 |

联系人导入支持**农历每年**开关（父母农历生日按农历重复）。多次导入同一条系统事件不会产生副本。

## ☁️ iCloud 同步抽象

```
ICloudSyncProvider 协议
├── push(events:deletedIDs:) → 增量推送 + 墓碑删除
├── pull(since:) → 增量拉取
└── MockCloudKitProvider：内存模拟容器（本地测试/预览）
```

`EventStore.syncCoordinator` 设置后，CRUD 自动 fire-and-forget 推送云端。

## 📊 Widget 小组件

| 样式 | 尺寸 | 内容 |
|---|---|---|
| **今日黄历概览** | Small / Medium | 宜忌条目 + 冲煞 + 节日胶囊 |
| **农历日期卡片** | Small / Medium | 大号月日 + 干支 + 公历副标题 + 节日/冲煞 |
| **今日待办进度** | Small / Medium | 进度环 + 真实待办列表（优先级色点） |

数据桥：主 App `EventStore.save()` 自动写入 App Group 共享快照 → Widget 读取展示。

## 📊 农历转换真值表（17 点回归测试）

| 公历 | 农历 | 备注 |
|---|---|---|
| 1900-01-31 | 庚子年正月初一 | 基准日 |
| 1900-02-01 | 庚子年正月初二 | |
| 1900-02-28 | 庚子年正月廿九 | 正月小29天 |
| 1900-03-01 | 庚子年二月初一 | |
| 2020-05-22 | 庚子年四月三十 | |
| 2020-05-23 | 庚子年闰四月初一 | **闰四月** |
| 2020-06-20 | 庚子年闰四月廿九 | |
| 2020-06-21 | 庚子年五月初一 | |
| 2023-03-21 | 癸卯年二月三十 | |
| 2023-03-22 | 癸卯年闰二月初一 | **闰二月** |
| 2023-04-19 | 癸卯年闰二月廿九 | |
| 2023-04-20 | 癸卯年三月初一 | |
| 2024-02-10 | 甲辰年正月初一 | 甲辰年春节 |
| 2025-01-29 | 乙巳年正月初一 | 乙巳年春节 |
| 2026-02-17 | 丙午年正月初一 | 丙午年春节 |
| 2100-02-09 | 庚申年正月初一 | 数据表上界 |
| 2026-08-19 | 丙午年七月初七 | 今日 |

## 📄 License

MIT
