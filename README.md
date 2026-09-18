# 清和日历 · iOS 中国农历日历

> 「清和」出自《汉书·郊祀志》"天气清和，稼穑咸秀"——晴朗温和、岁月美好。

一款 iOS / iPadOS 日历应用：内置公历↔农历转换、黄历宜忌、日程/记事/提醒、天气、倒数日灵动岛、本地通知、iCloud 同步。界面遵循 iOS 26/27 设计规范（Liquid Glass 液态玻璃 + 节日自适应主题色 + 按压反馈），支持 iPhone / iPad 自适应布局，兼容 iOS 27 / iPadOS 27。

## 功能

| 模块 | 说明 |
|---|---|
| 日历月视图 | 7 列标准网格、卡片式左右滑动翻月、"今天"快捷跳转、月份标题点击选月、日期格长按菜单 |
| 年视图 | 全年 12 个月迷你网格总览，标注今日 / 事件 / 节气 / 节日，点击月份直达 |
| 中国农历 | 1900–2100 公历↔农历转换、闰月、干支纪年、十二生肖；农历↔公历双向查询 |
| 黄历 | 宜/忌、冲煞、五行纳音、财神/喜神方位；离散数据库（2024–2028）+ 算法兜底 |
| 节气 / 节日 | 格内文字标注节气（无需选中即可见）、传统节日主题色、国务院放假安排（休/班徽标） |
| 天气 | Open-Meteo 免 Key + 自动定位 + 城市反地理编码；日期卡片内随选中日显示当天天气 |
| 事件管理 | 日程 / 提醒 / 记事三类，优先级标识，本地通知，重复规则（含**农历每年**） |
| 倒数日 / 纪念日 | 周年计算（闰月 / 2·29 回退）、**灵动岛 + 锁屏实时活动**（系统级倒计时，零耗电） |
| 数据导入 | 系统日历（EventKit）+ 联系人（Contacts）+ .ics/.csv/.json 恢复，确定性 UUID 防重复 |
| iCloud 同步 | 真实 CloudKit（私有 DB + Custom Zone + 墓碑 + 增量拉取）+ Mock 测试容器 |
| Widget 小组件 | 今日黄历概览 / 农历日期卡片 / 今日待办进度，App Group 共享快照，数据变更即时刷新 |
| 多语言 | 简体中文 / 繁体中文 / 日文 / 英文（含 Widget、灵动岛全量本地化） |
| 主题 | 深浅色自适应、每周起始日设置、节日自动换图标（春节限定版） |

## 系统要求

- iOS / iPadOS 17.0+（iOS 26+ 自动启用 Liquid Glass；iOS 27 / iPadOS 27 已验证兼容）
- Swift 6.0 / Xcode 16.0+（建议 Xcode 27；2027 Q1 起 App Store 提交要求 Xcode 27 构建）

## 运行方式

### Xcode 直接运行（推荐）

1. 打开工程根目录的 `LunisolarCalendar.xcodeproj`
2. 选择 **LunisolarCalendar** target → Signing & Capabilities → 选择你的 Team
3. 主 App 与 Widget 扩展确认勾选同一 App Group（`group.com.qinghe.calendar`）
4. ⌘R 运行（模拟器无需签名；真机需先在开发者后台配置 Bundle ID 与 Profile）

> 完整签名 / Capability 指引见 [`docs/XCODE_BUILD_GUIDE.md`](docs/XCODE_BUILD_GUIDE.md) 与 [`docs/ENTITLEMENTS.md`](docs/ENTITLEMENTS.md)。

### 作为 Swift Package 接入

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

### App 图标

- 图标源文件位于 `Assets/Assets.xcassets/AppIcon.appiconset/`（四季日历主图标）与 `AppIconSpringFestival.appiconset/`（春节限定版）
- 重新生成全部尺寸 PNG：`python3 Tools/gen-icons-flat-blue.py`（需 Pillow）
- 春节窗口自动切换由 `AlternateIconManager.shared.applyTodayIfNeeded()` 处理

### Widget 接入

1. Widget 扩展 target 的 `@main` 使用 `LunisolarWidgetsBundle()`
2. 主 App 与 Widget 扩展勾选同一 App Group（`group.com.qinghe.calendar`）
3. 主 App 启动时设置 `EventStore.shared.widgetAppGroupID = appGroupID`（HostApp.swift 已接线）
4. 灵动岛（Live Activity）：主 App 与 Widget 扩展的 Info.plist 均需 `NSSupportsLiveActivities = true`

### iCloud / CloudKit

1. Xcode → 主 App Target → Signing & Capabilities → 添加 iCloud → 勾选 CloudKit
2. 设置页打开「iCloud 同步」开关

> 个人免费开发者账号不支持 iCloud capability（已从 entitlements 移除相关 key，App 内自动降级为"不可用"提示，不影响其他功能）；Linux / SwiftPM 环境使用 MockCloudKitProvider。

## 项目结构

```
LunisolarCalendar.xcodeproj/     # Xcode 宿主工程（仅编译入口 + 资源，业务代码走 SwiftPM）
LunisolarHostApp/                # 主 App 宿主入口（HostApp.swift + entitlements）
LunisolarWidget/                 # Widget 扩展宿主（WidgetMain.swift + Info.plist + entitlements）
Assets/Assets.xcassets/          # App 图标（主图标 + 春节限定）
Sources/LunisolarCalendarApp/
├── App/                         # @main 入口 + AdaptiveRootView + 外观偏好
├── Models/                      # LunarDate（农历算法）/ Huangli（黄历）/ CalendarEvent / CountdownEvent
├── Stores/EventStore.swift      # @Observable + JSON 持久化 + dirty 追踪 + Widget 快照
├── Support/                     # 设计 Token、天气、节日/节气、黄历库、通知、导入桥、评分引导等
├── Sync/                        # CloudKit 同步（协议 / Mock / 真实 / 协调器）
├── Widgets/                     # 3 种小组件 + 倒数日灵动岛（Live Activity）
├── Views/                       # 月视图 / 年视图 / 日详情 / 编辑 / 倒数日 / 设置 / 天气卡
└── Resources/                   # lunar_calendar.json、huangli_db.json、4 套 lproj 本地化
Tools/                           # 黄历库生成工具 + 图标生成脚本
Tests/LunisolarCalendarTests/    # 99 个单元测试
UITests/                         # UI 冒烟测试（3 条）
docs/                            # 上架 / 签名 / 构建指引
```

## 构建与测试

```bash
swift build        # 编译所有 Target
swift test         # 运行 99 个单元测试
```

> Linux 环境仅验证模型层（农历/黄历/事件 CRUD/导入导出/同步 Mock），SwiftUI 视图编译需 iOS/macOS SDK；CI（`.github/workflows/ci.yml`）额外跑 iOS 模拟器 `xcodebuild test`。

## 测试覆盖（99 条）

| 套件 | 数量 | 覆盖内容 |
|---|---|---|
| CalendarEventTests | 16 | 事件模型、农历重复规则、ICS 往返、优先级、节日主色 |
| EventStoreTests | 16 | CRUD、搜索、合并策略、副本防护、toggleCompleted 通知重排 |
| ICloudSyncTests | 11 | 推送/拉取/冲突/增量/离线上线/墓碑传播 |
| SystemImportTests | 9 | DTO 映射、确定性 UUID、聚合、端到端无副本 |
| DataPortabilityTests | 8 | JSON/ICS 往返、伪 UUID 稳定性、合并统计 |
| HuangliDBProviderTests | 6 | 离散库命中、边界 fallback、DB↔算法一致性 |
| LunarDateTests | 5 | 农历真值点、闰月、边界 nil 安全、反向转换 |
| NotificationLunarAnniversaryTests | 5 | 农历周年提醒边界、闰月回退/匹配 |
| HolidayProviderTests | 7 | 2025/2026 官方放假安排锚点、调休补班 |
| CountdownEventTests | 7 | 纪念日周年（今年/跨年/2·29 回退）、倒数日文案 |
| WidgetSnapshotTests | 4 | 快照读写、过期检测、自动写入 |
| AccessibilityIDTests | 3 | 无障碍标识目录一致性 |
| HuangliTests | 2 | 宜忌稳定性、冲煞验证 |

## 配置说明

### Bundle ID 与 App Group（当前值）

| 项 | 值 |
|---|---|
| 主 App Bundle ID | `com.qinghe.calendar` |
| Widget 扩展 Bundle ID | `com.qinghe.calendar.widget` |
| App Group | `group.com.qinghe.calendar` |

### 黄历数据策略（产品决策）

1. **当前口径**：2024-01-01 ~ 2028-12-31 使用人工核验的离散库（`huangli_db.json`）；此范围外（含 2029 起）走算法兜底，保证不空窗。
2. **一致性风险**：算法与离散库在个别日子的宜忌措辞可能有差异；设置页已展示数据覆盖说明。
3. **扩展库**：如需 2029+ 与库一致，运行 `swift run gen_huangli_db` 扩展 JSON 并按 `HuangliDBProviderTests` 方式抽验后合入。

### 多语言接线（已内置）

- 4 套 `lproj`（zh-Hans / zh-Hant / ja / en）已注册进主 App 与 Widget 两个 target 的 Resources phase
- 新增语言：复制任一 `lproj` 并翻译键值即可，无需改代码

### UI 测试

- 新建 **UI Testing Bundle** target（命名 `LunisolarCalendarUITests`），Target Application 选 LunisolarCalendar
- 将 `UITests/LunisolarCalendarUITests.swift` 加入该 target，Cmd+U 运行 3 条冒烟测试

## 发布清单（Release Checklist）

- [ ] `CFBundleShortVersionString` / `CFBundleVersion` 已递增（当前 `MARKETING_VERSION = 1.0.1`）
- [ ] Xcode → Product → Archive 成功（无 codesign 错误）
- [ ] 主 App + Widget 扩展均勾选同一 App Group（`group.com.qinghe.calendar`）
- [ ] iCloud Capability 已启用，CloudKit Container ID 已配置（付费账号）
- [ ] 隐私权限文案（定位 / 通讯录 / 日历）已审核
- [ ] App Icon 1024×1024 无透明通道（App Store 要求）
- [ ] 春节限定备用图标声明完整
- [ ] 真机测试：通知 → 提醒锁屏弹窗；iCloud 多设备一致性；Widget 快照刷新；灵动岛上下岛
- [ ] 隐私清单（Privacy Manifest）已声明
- [ ] App Store Connect：截图、描述、关键词、隐私标签已填写

详见 [`docs/APP_STORE.md`](docs/APP_STORE.md)、[`docs/ENTITLEMENTS.md`](docs/ENTITLEMENTS.md) 与 [`docs/XCODE_BUILD_GUIDE.md`](docs/XCODE_BUILD_GUIDE.md)。

## 已修复的关键问题

累计修复 56+ 个 BUG，覆盖数据安全、并发竞态、CloudKit API 兼容、日历一致性、Swift 6 并发隔离、UI 触碰区等，关键方向：

- **数据安全**：损坏数据不再覆盖用户数据；dirty 标记持久化防重启丢失；越界日期不再显示"假农历"
- **并发安全**：推送队列序列化、同步防重入、`@MainActor` 隔离协调器、Swift 6 region-based 检查合规
- **日历一致性**：全模块统一 `.gregorian`，避免非公历系统环境错乱；农历周年/闰月边界正确
- **平台适配**：iOS 26/27 Liquid Glass 原生化、Live Activity 新 API、CloudKit 废弃 API 迁移
- **UI/性能**：全部交互元素 ≥ 44pt 触碰区、月历渲染 O(1) 缓存、静态 `Calendar.gregorian` 高频路径优化

## License

MIT
