**Language / 语言：** 简体 | [繁體](README.zh-Hant.md) | [English](README.en.md) | [日本語](README.ja.md)

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
| AI 日历助手 | 本地自然语言解析（"明天下午3点提醒我开会"），预览后一键创建日程，不上传数据 |
| 底部导航 | iPhone TabBar（日历 / 黄历 / AI 助手 / 我的）；iPad 三栏 Sidebar（日历 / 年视图 / 倒数日 / 设置） |

## 系统要求

- iOS / iPadOS 17.0+（iOS 26+ 自动启用 Liquid Glass；iOS 27 / iPadOS 27 已验证兼容）
- Swift 6.0 / Xcode 16.0+（建议 Xcode 27；2027 Q1 起 App Store 提交要求 Xcode 27 构建）

## 运行方式

### Xcode 直接运行（推荐）

1. 打开工程根目录的 `LunisolarCalendar.xcodeproj`
2. 选择 **LunisolarCalendar** target → Signing & Capabilities → 选择你的 Team
3. 主 App 与 Widget 扩展确认勾选同一 App Group（<同一 App Group>）
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
2. 主 App 与 Widget 扩展勾选同一 App Group（<同一 App Group>）
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
Tests/LunisolarCalendarTests/    # 309 个单元测试（36 个套件）
UITests/                         # UI 冒烟测试（3 条）
docs/                            # 上架 / 签名 / 构建 / 真机复测清单 / 待做方案（全天事件、黄历数据源）
```

## 构建与测试

```bash
swift build        # 编译所有 Target
swift test         # 运行 309 个单元测试
```

> Linux 环境仅验证模型层（农历/黄历/事件 CRUD/导入导出/同步 Mock），SwiftUI 视图编译需 iOS/macOS SDK；本仓库**未配置 CI**（无 `.github/workflows`，推送不会触发构建）。本地自检：`swift build` / `swift test`（macOS 宿主，2026-09-24 起可用）+ `swift build --triple arm64-apple-ios17.0-simulator --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)"`（iOS 视图层与宿主编译），详见 `docs/XCODE_BUILD_GUIDE.md` §4。真机行为验证见 [`docs/DEVICE_TEST_CHECKLIST.md`](docs/DEVICE_TEST_CHECKLIST.md)。

## 测试覆盖（309 条 / 36 个套件）

| 套件 | 数量 | 覆盖内容 |
|---|---|---|
| AIAssistantTests | 43 | AI 解析与执行：中文数字/时间词归一化、创建/查询/删除/修改意图、执行层写入与只读查询 |
| AICommandParserEdgeCaseTests | 18 | 解析边界：显式年份、下周三、孤立时段词、凌晨/晚上 12 点、head/tail 日期分工 |
| SolarTermGoldenTests | 17 | 24 节气真值点、交节时刻前后判定 |
| EventStoreTests | 16 | CRUD、排序不变量、批量添加、合并策略、损坏文件隔离 |
| CalendarEventTests | 16 | 事件模型、农历重复规则、ICS/CSV 往返、全天时长 |
| QingheActivityCoordinatorTests | 12 | 时间胶囊候选挑选：优先级、窗口、全天过期、节气两小时 |
| ICloudSyncTests | 11 | 推送/拉取/冲突/增量/离线上线/墓碑传播 |
| AllDayTimeZoneTests | 11 | 全天事件跨时区：年月日物化、本机日漂移才改写、旧数据与计时事件不动 |
| SystemImportTests | 9 | DTO 映射、确定性 UUID、聚合、重复导入无副本、农历生日开关 |
| QingheLiveActivityLifecycleTests | 9 | 实时活动 sync 的 start/update/end/none 判定 |
| NotificationManagerTests | 9 | 「稍后提醒」ID 往返、保留策略、畸形 ID 安全 |
| WidgetSnapshotTests | 8 | 快照读写、跨天窗口、过期检测 |
| LegacyImportNoteCleanupTests | 8 | 旧 ICS 备注污染清理的边界与幂等 |
| DataPortabilityTests | 8 | JSON/ICS 往返、时区、伪 UUID 稳定、合并计数 |
| CountdownEventTests | 8 | 纪念日周年、2·29 回退、倒数日文案 |
| CloudKitEntitlementTests | 8 | entitlement 探测（无 entitlement 不得放行） |
| AllEventsGroupingTests | 8 | 全部日程分组：跨天不判已过去、组头夹取今天 |
| HolidayProviderTests | 7 | 2025/2026 放假锚点、调休补班、未发布年份回退 |
| DeepLinkRouterTests | 7 | qinghe:// 各路由与非法 URL 不受影响 |
| TimeZoneGoldenTests | 6 | 节气/黄历/干支年与设备时区无关 |
| SyncDirtyFlagTests | 6 | 脏标记推送后清理、失败集保留、事件时钟下限 |
| ReminderPolicyTests | 6 | 提醒口径统一（是否排通知） |
| ICSImportRobustnessTests | 6 | ICS 子块跳过、formatter 固定 locale/calendar |
| HuangliDBProviderTests | 6 | 离散库命中、边界 fallback、DB↔算法一致性 |
| NotificationLunarAnniversaryTests | 5 | 农历周年提醒边界、闰月回退/匹配 |
| MiniMonthGridTests | 5 | 年视图小月历表头与星期对齐 |
| LunarDateTests | 5 | 农历真值点、闰月、边界 nil 安全、反向转换 |
| EventServiceTimeCapsuleTests | 5 | 事件→时间胶囊候选的优先级映射 |
| LiveActivityOccupancyTests | 4 | 实时活动「是否仍在岛上」判据（已结束的活动不算占用） |
| FestivalGoldenTests | 4 | 节日农历↔公历往返、闰月不位移 |
| EventServiceCompletionTests | 4 | 完成/取消完成幂等、批量完成 |
| AIOccurrenceResolutionTests | 4 | 重复日程「命中那一次」的解析 |
| LunarDataResourceTests | 3 | lunar_calendar.json 合法性与内置表一致 |
| AccessibilityIDTests | 3 | 无障碍标识命名与唯一性 |
| HuangliTests | 2 | 宜忌稳定性、冲煞验证 |
| EventServiceIsolationTests | 2 | EventService 可注入，不倒向共享单例 |

## 配置说明

### 黄历数据策略（产品决策）

1. **数据来源（重要，勿夸大）**：宜忌 / 冲煞 / 神位等由**传统干支规则集在 App 内推导**（规则见 `Models/Huangli.swift` 的 `yiPool` / `jiPool`）。
   `huangli_db.json` 是 2024-01-01 ~ 2028-12-31 的**预生成结果**（同一规则集的离线缓存，用于加快加载），
   **不是人工核验的权威黄历数据**：实测该库 1827 天仅 9 种「宜」组合、10 种「忌」组合（按当日天干分组），属粗粒度规则推导。
   此范围外由同一规则集实时推导，保证不空窗。
2. **表述边界**：App 内文案与商店描述不得把该数据称为"权威 / 经核验"；宜忌等内容仅供参考。
3. **应用内可见性**：设置 → 数据与同步 → 高级数据设置 已展示数据来源说明（`HuangliDBProvider.coverageDescription`）。
4. **替换 / 扩展**：接入权威数据源时替换 `huangli_db.json`（key 保持 `yyyy-MM-dd`）；
   规则集升级则运行 `swift run gen_huangli_db` 重新生成，并按 `HuangliDBProviderTests` 抽验后合入。

### 多语言接线（已内置）

- 4 套 `lproj`（zh-Hans / zh-Hant / ja / en）已注册进主 App 与 Widget 两个 target 的 Resources phase
- 新增语言：复制任一 `lproj` 并翻译键值即可，无需改代码

### UI 测试

- 新建 **UI Testing Bundle** target（命名 `LunisolarCalendarUITests`），Target Application 选 LunisolarCalendar
- 将 `UITests/LunisolarCalendarUITests.swift` 加入该 target，Cmd+U 运行 3 条冒烟测试

## 发布清单（Release Checklist）

- [ ] `CFBundleShortVersionString` / `CFBundleVersion` 已递增（当前 `MARKETING_VERSION = 1.0.1`）
- [ ] Xcode → Product → Archive 成功（无 codesign 错误）
- [ ] 主 App + Widget 扩展均勾选同一 App Group（<同一 App Group>）
- [ ] iCloud Capability 已启用，CloudKit Container ID 已配置（付费账号）
- [ ] 隐私权限文案（定位 / 通讯录 / 日历）已审核
- [ ] App Icon 1024×1024 无透明通道（App Store 要求）
- [ ] 春节限定备用图标声明完整
- [ ] 真机测试：按 [`docs/DEVICE_TEST_CHECKLIST.md`](docs/DEVICE_TEST_CHECKLIST.md) 逐项走一遍
      （至少覆盖通知锁屏弹窗、iCloud 多设备一致性、Widget 跨天刷新、灵动岛上下岛与互斥）
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
