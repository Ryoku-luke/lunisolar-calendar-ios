# Lunisolar Calendar · iOS 中国农历日历

一款简洁的 iOS 日历应用，内置公历↔农历转换、黄历黄道吉日、日程 / 记事 / 提醒本地持久化 + 本地通知，界面遵循 iOS 标准设计规范。

## ✨ 功能

| 模块 | 说明 |
|---|---|
| 🗓️ 日历月视图 | **7×6** 标准网格、左右切换月份、今日高亮 + **"今天"快捷按钮**、周末红字、优先级色圆点 |
| 🌕 中国农历 | 1900-2100 公历↔农历转换、闰月支持、干支纪年、十二生肖、月日中文名称；**农历↔公历双向查询**；边界 nil 保护 |
| 📜 黄历 | 黄道吉日综合判定（黄黑道六神 + 建除十二神 + 28宿）、宜/忌事项、冲煞、五行纳音、喜神财神方位 |
| 📝 三种事件类型 | 日程 (schedule) / 提醒 (reminder) / 记事 (note) |
| 🔁 重复规则 | 不重复 / 每天 / 每周 / 每月 / 每年 / 工作日 / **农历每年（父母生日·传统节日）** |
| 🏷️ 优先级 | 紧急 / 高 / 普通 / 低（带颜色标识） |
| 🔔 本地通知 | `UNUserNotificationCenter` 提醒推送、`isNotified` 防重复、删除/编辑自动取消旧通知 |
| 💾 本地持久化 | JSON 自动保存到 App Documents，首启动带示例数据 |
| 📤 数据逃离机制 | **.ics 导入导出** (iCalendar RFC5545) + **.csv 导出**（换机备份/跨 App 迁移） |
| ⚙️ 设置页 | 通知权限状态 + 重新调度、导入导出入口、数据统计、版本信息 |
| 🧪 单元测试 | 16 个 XCTest 覆盖农历真值 (17点) / 宜忌稳定性 / 冲煞 / ICS 往返 / CRUD |
| 🎨 iOS UI | SwiftUI · `NavigationStack` · `.formStyle(.grouped)` · 语义色 · SF Symbol · 深浅色自适应 |

## 📱 系统要求

- **iOS**: 17.0+
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
            CalendarAppRootView()
                .environment(EventStore.shared)
        }
    }
}
```

## 🏗️ 项目结构

```
Sources/LunisolarCalendarApp/
├── App/
│   └── LunisolarCalendarApp.swift     # @main 入口 + 宿主启动
├── Models/
│   ├── LunarDate.swift                # 公历↔农历算法（1900-2100, JSON资源化+fallback）
│   ├── Huangli.swift                  # 黄历：吉日 / 宜忌 / 冲煞 / 五行 / 神位
│   └── CalendarEvent.swift            # 事件模型（含.lunarAnnually + isNotified）
├── Stores/
│   └── EventStore.swift               # @MainActor @Observable + JSON持久化
├── Support/
│   ├── ColorExtensions.swift          # iOS 语义色 + 屏幕尺寸辅助
│   ├── NotificationManager.swift      # UNUserNotificationCenter（授权/调度/取消）
│   └── DataPortability.swift          # .ics 导入导出 / .csv 导出
├── Resources/
│   └── lunar_calendar.json            # 农历数据表（201年，编译为Bundle资源）
└── Views/
    ├── CalendarMonthView.swift        # 主界面：月视图 + 今日按钮 + 底部面板
    ├── CalendarComponents.swift       # 星期表头 / DayCell 组件
    ├── DayDetailView.swift            # 黄历详情 + 当日日程列表
    ├── EventEditView.swift            # 新建/编辑/删除（自动管理通知生命周期）
    ├── EventRow.swift                 # 事件列表项
    └── SettingsView.swift             # 设置页（通知+导入导出+统计）含ShareSheet

Tests/LunisolarCalendarTests/
└── LunisolarCalendarTests.swift       # 16个 XCTest（农历/黄历/事件/导入导出/CRUD）
```

## 🔧 构建 & 测试（命令行）

```bash
swift build        # 编译所有 Target
swift test         # 运行 16 个单元测试（Linux 仅模型层，Apple 平台全量）
```

> Linux 环境仅能验证模型层（农历 / 黄历 / 事件 CRUD），SwiftUI 视图编译需要 iOS 或 macOS SDK。

## 🧪 单元测试覆盖（16/16 通过）

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
- `.lunarAnnually` 农历每年重复匹配
- 优先级排序（紧急>高>普通>低）
- ICS 导出→导入往返一致性
- CSV 导出格式正确

### EventStoreTests（3个）
- CRUD 完整流程
- `markNotified` 防重复通知
- 标题/地点/备注全文搜索

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

## 📥 导入导出

| 格式 | 导出 | 导入 | 用途 |
|---|---|---|---|
| **.ics** (iCalendar) | ✅ RRULE/优先级/全天状态 | ✅ SUMMARY/DTSTART/DTEND/LOCATION | 导入到系统日历/Google日历/Outlook |
| **.csv** (表格) | ✅ 11列完整属性 | — | Excel/Numbers 分析/打印 |

入口：主界面右上角菜单 → **设置** → 数据管理。

## 🔔 本地通知（提醒）

```
新建 reminder
   ↓
申请 UNUserNotificationCenter 权限
   ↓
UNCalendarNotificationTrigger 精确触发
   ↓
通知到达 → markNotified=true（防重复）
   ↓
编辑/删除 → cancelNotification 清理旧请求
```

权限申请仅在用户**首次创建 reminder** 时触发，不打扰纯记事/日程用户。

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
