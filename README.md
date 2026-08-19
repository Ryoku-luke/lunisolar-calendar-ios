# Lunisolar Calendar · iOS 中国农历日历

一款简洁的 iOS 日历应用，内置公历↔农历转换、黄历黄道吉日、日程 / 记事 / 提醒本地持久化，界面遵循 iOS 标准设计规范。

## ✨ 功能

| 模块 | 说明 |
|---|---|
| 🗓️ 日历月视图 | 6×7 标准网格、月份切换、今日高亮、周末红字、优先级色圆点 |
| 🌕 中国农历 | 1900-2100 公历↔农历转换、闰月支持、干支纪年、十二生肖、月日中文名称 |
| 📜 黄历 | 黄道吉日判定、宜 / 忌事项、冲煞、五行纳音、喜神财神方位 |
| 📝 三种事件类型 | 日程 (schedule) / 提醒 (reminder) / 记事 (note) |
| 🔁 重复规则 | 不重复 / 每天 / 每周 / 每月 / 每年 / 工作日 |
| 🏷️ 优先级 | 紧急 / 高 / 普通 / 低（带颜色标识） |
| 💾 本地持久化 | JSON 自动保存到 App Documents，首启动带示例数据 |
| 🎨 iOS UI | SwiftUI · `NavigationStack` · `.formStyle(.grouped)` · 语义色 · SF Symbol |

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
│   ├── LunarDate.swift                # 公历↔农历算法（1900-2100 数据表）
│   ├── Huangli.swift                  # 黄历：吉日 / 宜忌 / 冲煞 / 五行 / 神位
│   └── CalendarEvent.swift            # 事件模型（类型 / 重复 / 优先级）
├── Stores/
│   └── EventStore.swift               # @MainActor @Observable + JSON 持久化
├── Support/
│   └── ColorExtensions.swift          # iOS 语义色 + 跨平台适配
└── Views/
    ├── CalendarMonthView.swift        # 主界面：月视图 + 底部摘要面板
    ├── CalendarComponents.swift       # 星期表头 / DayCell 组件
    ├── DayDetailView.swift            # 黄历详情 + 当日日程列表
    ├── EventEditView.swift            # 新建 / 编辑 / 删除
    └── EventRow.swift                 # 事件列表项
```

## 🔧 构建验证（命令行）

```bash
swift build        # 需要 macOS / Xcode 工具链
```

> Linux 环境仅能验证模型层（农历 / 黄历 / 事件 CRUD），SwiftUI 视图编译需要 iOS 或 macOS SDK。

## 🧪 农历转换真值示例（17/17 通过回归测试）

| 公历 | 农历 | 备注 |
|---|---|---|
| 1900-01-31 | 庚子年正月初一 | 基准日 |
| 2020-05-23 | 庚子年闰四月初一 | 闰四月 |
| 2023-03-22 | 癸卯年闰二月初一 | 闰二月 |
| 2024-02-10 | 甲辰年正月初一 | 甲辰年春节 |
| 2026-08-19 | 丙午年七月初七 | 今日 |
| 2100-02-09 | 庚申年正月初一 | 数据表上界 |

## 📄 License

MIT
