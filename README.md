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
| ☁️ iCloud 同步 | **真实 CloudKit**（`RealCloudKitProvider`：私有 DB + Custom Zone + `CKQuery` 增量 + 墓碑 + `CKQuerySubscription`）+ `MockCloudKitProvider` 内存模拟容器；`ICloudSyncProvider` 协议抽象，UI 一键开关、状态展示、手动同步 |
| 📊 Widget 小组件 | 3 种样式：**今日黄历概览**（宜忌+冲煞）、**农历日期卡片**（干支+节日）、**今日待办进度**（进度环+真实待办列表）；App Group 共享快照 |
| 🎨 节日主题色 | 春节/中秋等传统节日自动切换背景渐变和主题色点缀 |
| 📱 iPad 适配 | `NavigationSplitView` 双栏布局（左月历 + 右日详情），cell 尺寸自适应，Form 限宽 720pt；`horizontalSizeClass` 自动切换 |
| ⚙️ 设置页 | 通知权限状态（异步查询）+ 重新调度、导入导出入口、系统数据导入、**iCloud 同步开关+状态+手动同步**、冲突策略、数据清空（二次确认）、数据统计、版本信息 |
| 🧪 单元测试 | **53 个 XCTest** / **9 个测试套件**：农历真值(17点) / 黄历算法 / 离散DB一致性 / 事件模型 / EventStore CRUD+合并 / 数据导入导出 / iCloud同步(Mock) / Widget快照 / 系统导入桥 |
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

### iCloud / CloudKit 接入（Xcode 工程）

App 已内置 `RealCloudKitProvider`（私有数据库 + Custom Zone `LunisolarZone` + 墓碑删除 + `CKQuerySubscription`）。真机启用步骤：

1. Xcode → 主 App Target → **Signing & Capabilities** → 添加 **iCloud** Capability
2. 勾选 **CloudKit**，勾选/创建你的 iCloud Container（如 `iCloud.com.you.lunisolar`）
3. （可选）在 [LunisolarCalendarApp.swift](Sources/LunisolarCalendarApp/App/LunisolarCalendarApp.swift) 里把 `RealCloudKitProvider(containerIdentifier:)` 指定为你自己的 Container ID
4. 运行 App → 设置页 → 「iCloud 同步」开关打开 → 自动后台首次同步
5. 多设备登录同一 iCloud 账号即可自动同步事件（增删改 + 墓碑 + last-write-wins 冲突解决）

> 测试环境（Linux / SwiftPM）不链接 CloudKit，`RealCloudKitProvider` 整文件 `#if canImport(CloudKit)` 跳过，单元测试继续使用 `MockCloudKitProvider`。

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
│   ├── SystemImportBridge.swift       # 系统导入桥：DTO + 协议 + Mapper（确定性 UUID）+ Aggregator
│   ├── CalendarImportProvider.swift   # EventKit 桥：EKEvent → CalendarEvent（#if canImport(EventKit)）
│   ├── ContactsImportProvider.swift   # Contacts 桥：CNContact 生日/纪念日 → CalendarEvent（#if canImport(Contacts)）
│   └── FlowLayout.swift               # Layout 协议流式标签排列（iOS 16+）
├── Sync/
│   ├── ICloudSyncProvider.swift       # 同步抽象协议 + SyncRecord + SyncResult + SyncCoders
│   ├── MockCloudKitProvider.swift     # 内存模拟云端容器（本地测试/预览/Linux）
│   ├── RealCloudKitProvider.swift     # 真实 CloudKit（私有DB+CustomZone+CKQuery+墓碑+订阅）（#if canImport(CloudKit)）
│   └── EventSyncCoordinator.swift     # @Observable 协调器：push/pull/merge/双向同步 + 版本追踪
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
    └── SettingsView.swift             # 设置页（通知+导入导出+系统导入+iCloud同步+冲突策略+清空+Toast）

Tests/LunisolarCalendarTests/
└── LunisolarCalendarTests.swift       # 53个 XCTest（农历/黄历/事件/导入导出/合并/Widget/系统导入）
```

## 🔧 构建 & 测试（命令行）

```bash
swift build        # 编译所有 Target
swift test         # 运行 53 个单元测试（Linux 仅模型层，Apple 平台全量）
```

> Linux 环境仅能验证模型层（农历 / 黄历 / 事件 CRUD / 导入导出 / 系统导入桥），SwiftUI 视图编译需要 iOS 或 macOS SDK。EventKit/Contacts/WidgetKit 代码用 `#if canImport` 包住，Linux 编译不报错。

## 🧪 单元测试覆盖（53/53 通过 · 0 失败 · 0 警告）

```
执行套件数:  9
执行用例数:  53
通过:        53 ✅
失败:        0
总耗时:      0.50s
```

### LunarDateTests（4个） — 公历↔农历核心转换
- `testLunarConversionAccuracy`：**17 个农历真值点**（基准日/2020闰四月/2023闰二月/春节/今日/2100上界），年/月/日/闰月标记四元组精确匹配
- `testLeapMonthYears`：2020→闰四月 / 2023→闰二月 / 2024→无闰月
- `testBoundaryNilSafe`：1899 & 2101 → `lunarDateSafe` 返回 nil；2026 → 非 nil
- `testReverseConversion`：2024正月初一 → 公历 2024-02-10

### HuangliTests（3个） — 黄历算法生成
- `testYiJiStability`：同一日期连续 2 次 generate → 宜忌结果完全一致
- `testChongSha20241001`：2024-10-01 戊戌日 → 冲龙（地支+生肖验证）
- `testAuspiciousIsBool`：吉日标记不崩溃

### HuangliDBProviderTests（6个） — 离散黄历数据库
- `testDiscreteDBHit20240101`：2024-01-01 命中离散库，宜忌/冲煞/五行/神位字段齐全
- `testDiscreteDBHit20260819Today`：今日 2026-08-19 七月初七，离散库与算法生成 7 项字段逐字相等
- `testDiscreteDBBoundaryTail`：2028-12-31 仍命中；2029-01-01 自动切回算法 fallback
- `testOutOfRangeReturnsNil`：1899/2101 越界日期 source=algorithm
- `testDBConsistentWithAlgorithmForRange`：2024-2028 区间随机 30 天抽样，DB 与算法在 yi/ji/chong/sha/wuxing/shenwei/auspicious 逐字相等
- `testCoverageDescriptionNotEmpty`：coverageDescription 声明覆盖 2024-2028

### CalendarEventTests（11个） — 事件模型
- `testEndDateAutoFix`：endDate ≤ startDate 时自动修正
- `testAllDayEventDuration`：全天事件 duration = 86399 秒
- `testLunarAnnuallyRepeat`：农历八月十五中秋节 → 次年同农历日匹配
- `testLunarAnnuallySpringFestivalAcross3Years`：春节正月初一跨 3 年 occurs 命中；正月初二不命中
- `testLunarAnnuallyLeapMonthMatchesFlatMonth`：闰月生日在平月年同月同日命中
- `testRepeatRuleLabelAndAnchor`：label/anchor 文本格式正确
- `testPriorityComparison`：urgent > high > normal > low
- `testICSExportImport`：ICS 导出→导入字段无损
- `testCSVExport`：CSV 导出含表头和标题
- `testLunarAnnuallySameDayEarlyHourMustMatch`：**BUG #1 回归** — 20:00 起锚事件当天 09:00 查询必须命中
- `testLunarAnnuallyOutOfBoundsAnchorIsNilSafe`：**BUG #2 回归** — 1899/2101 超范围锚点不崩溃

### EventStoreTests（7个） — 事件存储
- `testCRUD`：add → toggleCompleted → delete 全链路
- `testMarkNotified`：isNotified 从 false → true
- `testSearch`：关键词搜索命中标题
- `testLunarBirthdayAppearsOnSpringFestival2026`：正月初一事件在 2026 春节出现
- `testMergeAddNewNoDuplicate`：**副本 BUG 回归** — 同一事件第二次 merge 不产生副本
- `testMergeConflictPoliciesAllThree`：keepLatest / keepLocal / overwrite 三种策略
- `testClearAllReturnsCountAndResets`：clearAll 返回数量 + 事件归零

### DataPortabilityTests（3个） — 数据导入导出
- `testJSONRoundTripPreservesLunarAndFlags`：JSON 往返 version/exportedAt/count + 农历规则 + isNotified
- `testICSImportPseudoUUIDStableAndRRULEParsed`：同一 ICS 两次导入伪 UUID 一致；RRULE WEEKLY/BYDAY 正确解析
- `testMergeResultCounters`：合并统计 added=1, updated=1

### ICloudSyncTests（6个） — iCloud 同步（Mock 驱动）
- `testPushLocalEventsToCloud`：3 条本地 push → 云端 3 条
- `testPullCloudIntoLocalMerge`：云端注入 → pullAndMerge → 本地 2 条
- `testConflictLastWriteWins`：本地 v2 vs 云端 v3 → 云端胜出
- `testIncrementalPull`：sinceMs 增量拉取仅返回新变更
- `testOfflineGoOnlineBidirectionalSync`：离线新增 4 条 → syncBidirectional → 云端 4 条
- `testTombstoneDeletePropagation`：跨设备墓碑删除传播

### WidgetSnapshotTests（4个） — Widget 数据桥
- `testWriteThenReadRoundTrip`：写入→读取 7 项字段全保留
- `testReadIgnoresStaleSnapshot`：旧快照 targetDay 不匹配返回 nil
- `testReadMissingReturnsNil`：不存在文件安全返回 nil
- `testEventStoreAutoWritesSnapshotTodayCounts`：EventStore.add 后自动写快照

### SystemImportTests（9个） — 系统导入桥
- `testMapperPreservesAllFields`：DTO → Event 10 项字段全保留
- `testDeterministicUUIDStableAcrossCalls`：同 sourceID → 同 UUID
- `testDifferentSourceIDsDifferentUUIDs`：不同 sourceID → 不同 UUID
- `testStubProviderFetchEvents`：Stub 正常授权
- `testStubProviderUnauthorized`：未授权抛 unauthorized
- `testAggregatorCombinesAndCollectsFailures`：多 Provider 聚合 + 失败收集
- `testContactBirthdayDTOMapsToYearlyReminder`：联系人生日映射正确
- `testContactBirthdayLunarAnnuallyToggle`：农历每年规则正确
- `testEndToEndImportNoDuplicatesOnReimport`：**副本 BUG 回归** — 重复导入无副本

> 详细测试报告见 [TEST_REPORT.md](TEST_REPORT.md)

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

## 🐛 已修复 BUG 清单

### BUG #1（🔴 致命）：数据损坏时 insertSampleData 覆盖用户数据
- **文件**: `Stores/EventStore.swift`
- **根因**: `load()` 解码失败时调用 `insertSampleData()`，直接覆盖用户所有本地数据
- **修复**: 改为清空 events 数组 + 打印警告，不再用示例数据替换
- **回归测试**: `testLunarAnnuallySameDayEarlyHourMustMatch`（关联 #1）

### BUG #2（🔴 高）：ICS unescapeICS 处理顺序错误
- **文件**: `Support/DataPortability.swift`
- **根因**: 先处理 `\n` 再处理 `\\`，导致 `\\n`（字面反斜杠+n）被错误解析为换行符
- **修复**: 先用 `\u{0000}` 占位 `\\`，再处理其他转义，最后还原
- **回归测试**: `testICSImportPseudoUUIDStableAndRRULEParsed`

### BUG #3（🟡 中）：autoPush 多任务并发竞争
- **文件**: `Stores/EventStore.swift`
- **根因**: 每次 CRUD 创建独立 `Task`，并发推送导致丢失/重复
- **修复**: 改为序列化推送队列 `enqueuePush/drainPushQueue`，FIFO 执行

### BUG #4（🟡 中）：syncBidirectional 竞态 + 全量推送
- **文件**: `Sync/EventSyncCoordinator.swift`
- **根因**: 无并发保护；`pendingDirtyEvents()` 全量推送
- **修复**: 增加 `isSyncing` 防重入；改用 `dirtyEventIDs/deletedEventIDs` 增量追踪
- **回归测试**: `testOfflineGoOnlineBidirectionalSync`

### BUG #5（🟢 低）：MockCloudKitProvider 死代码
- **文件**: `Sync/MockCloudKitProvider.swift`
- **根因**: 无效 `await MainActor.run {}` 和空 `Task {}`
- **修复**: 清理死代码和无效 await

### BUG #6（🟢 低）：weekdaySymbol 数组越界
- **文件**: `Models/LunarDate.swift`
- **根因**: `weekday - 1` 可能越界
- **修复**: 增加 `max(0, min(6, ...))` 边界保护

### BUG #7（🔴 高）：iCloud 同步关闭→重开后变更永久丢失
- **文件**: `Stores/EventStore.swift`
- **根因**: `flushDirtyAndDeleted()` 中当 `syncCoordinator` 为 nil（用户关闭 iCloud 或尚未初始化）时，直接清空 `dirtyEventIDs` 和 `deletedEventIDs`。用户关闭同步期间的所有变更，在重新打开同步后永远不会被推送到云端
- **修复**: 移除 `syncCoordinator` 为 nil 时的清空逻辑，改为保留 dirty 标记，等用户重新启用 iCloud 同步后通过 `syncBidirectional()` 推送

### BUG #8（🟡 中）：LunarDate baseDate 日历体系不一致
- **文件**: `Models/LunarDate.swift`
- **根因**: `baseDate`（农历计算基准日 1900-01-31）使用 `Calendar.current` 计算，而核心转换函数统一使用 `Calendar(identifier: .gregorian)`。当用户在 iOS 设置中切换日历偏好（如日本历、佛历），`Calendar.current` 返回非公历实例，导致基准日偏差
- **修复**: `baseDate` 改用 `Calendar(identifier: .gregorian)` 计算，与全模块保持一致

### BUG #9（🔴 Xcode）：CloudKit API 变更导致多处编译错误
- **文件**: `Sync/RealCloudKitProvider.swift`
- **根因**: CloudKit 在新版 SDK（Xcode 16+）中多处 API 变更：
  - `CKContainer.privateDatabase` 已移除 → `database(with: .private)`
  - `CKDatabase.recordZone(forID:)` → `recordZone(for:)`
  - `CKModifyRecordsOperation.perRecordResultBlock` → `perRecordCompletionBlock`
  - `CKFetchRecordsOperation.perRecordResultBlock` → `perRecordCompletionBlock`
  - `queryResultBlock` cursor 处理错误（结果类型改为 `Cursor?`）
  - `CKError.Code.initiallyUnavailable` → `.temporarilyUnavailable`
  - `CKError.Code.accountFailure` 已移除
- **修复**: 重写 `RealCloudKitProvider`，统一使用新 API，移除 `#available(iOS 17)` 分支，修正 cursor 翻页逻辑

### 附加改进
- `skipSync: true` 仍标记 `dirtyEventIDs`，确保后续 `syncBidirectional()` 检出
- `Date` 扩展清理冗余 `public` 修饰符，零警告构建

## 📄 License

MIT
