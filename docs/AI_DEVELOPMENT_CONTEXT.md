# 清和日历（Qinghe Calendar）AI 开发总任务文档

> 用途：把本文档直接提供给 Codex、Claude Code、ChatGPT、Trae、Cursor 等 AI 编程助手，作为项目上下文、产品需求、架构规范、UI 规范、Live Activity 规范和开发规则。

## 0. AI 总指令

你是一名资深 Apple 平台工程师、Swift/SwiftUI 架构师、产品设计师和代码审查工程师。你负责继续开发已经存在的 iOS/iPadOS App：**清和日历（Qinghe Calendar）**。

仓库：`https://github.com/Ryoku-luke/lunisolar-calendar-ios.git`

### 总原则
- 不从零重写项目；先理解真实代码。
- 优先保留已经成熟的 LunarCore、EventStore、CloudKit、WeatherService 等核心能力。
- UI、产品结构和业务边界可以重构，但必须小步实施。
- 不为“看起来高级”而引入不必要的第三方依赖；优先 Apple 原生框架。
- 遵守 Swift 6 strict concurrency。
- 涉及新 API 必须检查 deployment target / availability。
- 不假设不存在的文件、类型、API 或业务逻辑。
- 每次修改前先分析影响范围；每个阶段都要保证可以编译和测试。
- 如果本文档与实际代码冲突，以实际代码为准，并指出冲突后选择兼容、风险最低的方案。

---

# 1. 项目定位

清和日历不是简单的日期转换工具，而是一个现代化的中国文化日历，逐步形成：

**现代 Apple 日历体验 + 公历/农历 + 黄历 + 节气 + 日程 + 提醒 + 天气 + iCloud + Widget + Live Activities + AI 助手**。

当前已经具备：
- 公历 / 农历转换
- 农历日期展示
- 黄历、宜/忌、冲煞、五行、神位
- 24 节气
- 日程、提醒、笔记
- 农历生日
- 天气
- 本地通知
- iCloud / CloudKit 同步
- Widget
- Live Activity / Dynamic Island 的产品设计方向
- 多语言 / 主题基础能力

---

# 2. 当前项目结构

仓库主要包含：

```text
Assets/
LunisolarCalendar.xcodeproj
LunisolarHostApp/
LunisolarWidget/
Sources/LunisolarCalendarApp/
Tests/LunisolarCalendarTests/
Tools/
docs/
Package.swift
```

Package 主要包括：
- `LunarCore`：纯 Swift 农历核心
- `LunisolarCalendarApp`：UI + 业务逻辑 + 核心应用能力
- `gen_huangli_db`：黄历数据库生成工具
- Tests

项目使用 Swift 6 / SwiftUI；README 描述 iOS/iPadOS 17+，并建议使用较新的 Xcode。

注意：`docs/XCODE_BUILD_GUIDE.md` 与仓库实际存在 `.xcodeproj` 的描述存在潜在不一致，后续应统一文档。

---

# 3. 推荐目标架构

```text
HostApp
  ↓
AppRootView
  ↓
Features
  ├─ Calendar
  ├─ Huangli
  ├─ Event
  ├─ Settings
  ├─ AI
  └─ LiveActivity
  ↓
Application / Domain
  ↓
Services / Store / Sync
  ├─ EventStore
  ├─ Weather
  ├─ SolarTerm
  ├─ Notification
  ├─ Festival
  └─ CloudKit
  ↓
Persistence / Widget / Live Activity
```

长期可以逐步整理为：

```text
Sources/
├── Core/
│   ├── LunarCore/
│   ├── CalendarCore/
│   └── HuangliCore/
├── Domain/
│   ├── CalendarEvent/
│   ├── CountdownEvent/
│   └── CalendarData/
├── Data/
│   ├── LocalStore/
│   ├── CloudStore/
│   ├── Import/
│   └── Export/
├── Services/
│   ├── Weather/
│   ├── Notification/
│   ├── SolarTerm/
│   └── Festival/
├── Features/
│   ├── Calendar/
│   ├── Huangli/
│   ├── Event/
│   ├── Settings/
│   ├── AI/
│   └── LiveActivity/
└── Widgets/
```

**不要机械搬迁目录。先检查真实 Target / Package / 文件依赖，再渐进迁移。**

---

# 4. LunarCore：必须保留

`LunarDate.swift` 是核心能力：
- 纯 Swift，不依赖 SwiftUI/UIKit
- 支持公历 → 农历、农历 → 公历
- 支持闰月
- 约覆盖 1900–2100
- 表格数据转换
- 日期合法性校验
- 农历 30 日在目标月份只有 29 日时的处理

不要为了架构重构而重写 LunarCore。

---

# 5. 关键日期问题：立春 / 干支年

当前 `LunarCore.ganZhiOfYear(for:)` 使用近似的 **2 月 4 日 00:00** 作为干支年边界；但项目已有 `SolarTermProvider`，其中存在精确节气时间。例如：

```text
2026 立春：2026-02-04 04:01 Asia/Shanghai
```

因此最终业务层不能继续简单使用 2 月 4 日 00:00。

推荐：

```text
LunarCore
  ↓
基础农历算法

SolarTermProvider
  ↓
精确节气

App Layer / YearBoundaryProvider
  ↓
干支年判断
```

LunarCore 保持通用，精确年界逻辑放到 App 层。

---

# 6. 黄历系统

现有：
- `Huangli.swift`
- `HuangliDBProvider.swift`

当前黄历数据分两层：

```text
2024-01-01 ~ 2028-12-31
    ↓
离散黄历数据库

数据库范围外
    ↓
HuangliGenerator.algorithmGenerate
```

因此产品必须区分数据可信等级，不能让所有年份看起来完全同等准确。

建议：

```swift
enum HuangliDataSource {
    case verifiedDatabase
    case astronomical
    case algorithmicFallback
}
```

UI/内部模型可以知道数据来源；产品宣传不得把算法 fallback 与经过验证的数据库描述成完全同等级准确。

---

# 7. 时区统一

当前部分黄历/节气逻辑使用 `Asia/Shanghai`，其他业务可能使用设备系统时区或 `Calendar(identifier: .gregorian)`。

未来必须建立统一的：

```text
CalendarEnvironment / QingheCalendarContext
├── businessTimeZone
├── calendar
└── locale
```

明确：
- 黄历日期时区
- 节气时区
- 农历生日时区
- 普通日程时区
- Widget 时区
- Live Activity 时区

所有日期边界测试都必须考虑时区。

---

# 8. EventStore

`EventStore.swift` 是核心基础设施，已经具备：
- `@Observable @MainActor`
- 排序
- revision
- eventCache / statsCache / lunarCache
- `idToIndex`
- O(1) ID 查询
- binary insertion
- cache invalidation
- dirty / deleted ID 集合
- atomic persistence
- save debounce
- background/inactive flush
- corrupt file quarantine
- 删除时取消本地通知
- Widget snapshot
- Widget timeline reload
- merge / conflict handling

持久化文件：

```text
calendar_events.json
dirty_event_ids.json
deleted_event_ids.json
```

这些能力不要轻易重写。

---

# 9. EventService：建立业务边界

未来推荐增加：

```text
EventService
```

架构：

```text
UI
 ↓
EventService
 ↓
EventStore
```

EventService 同时协调：

```text
EventStore
NotificationScheduler
WidgetSnapshot
QingheActivityCoordinator
```

不要让 SwiftUI View 同时操作 EventStore、UserNotifications、WidgetKit、ActivityKit。

---

# 10. CalendarEvent

当前事件类型：

```text
schedule
reminder
note
```

重复：

```text
never
daily
workday
weekly
monthly
yearly
lunarAnnually
```

优先级：

```text
low
normal
high
urgent
```

支持：
- 开始 / 结束
- 全天
- 地点
- 备注
- 重复
- 优先级
- 完成状态
- 提醒偏移
- 创建/更新时间

其中 `lunarAnnually` 支持农历生日；源日期为农历三十时，如果目标年份该月只有二十九日，应允许匹配二十九日。

---

# 11. CloudKit / EventSyncCoordinator

现有同步系统已经有：
- Push / Pull / 双向同步
- last sync timestamp
- version map
- per-event version
- LWW
- tombstone
- 失败记录保留
- tombstone TTL
- 并发 sync 保护

当前核心策略：

```text
remote version > local
    → remote wins
```

CloudKit 使用 Private DB + 自定义 zone `LunisolarZone`，RecordType 为 `CalendarEvent`，并处理 change tag、cursor、分页、单条失败等。

未来可以研究 CloudKit 原生 zone change token 机制，逐步增强增量同步；不要为了升级而立即重写现有 CloudKit。

---

# 12. WeatherService

现有 WeatherService 使用 Open-Meteo：
- 无 API Key
- 7 天窗口：过去 3 天 + 今天 + 未来 3 天
- location cache 60 秒
- weather cache 1 小时
- URLSession timeout
- resource timeout
- inflight Task dedupe

UI 必须明确天气预测范围，不要让用户误以为任意未来日期都有天气数据。

---

# 13. Settings 2.0

当前设置使用：

```swift
List
.listStyle(.insetGrouped)
```

已有：
- 外观
- 提醒通知
- 数据
- iCloud 同步
- 导入冲突策略
- 数据统计
- 危险操作
- 关于

主要 IA 问题：`导入冲突策略` 技术性太强，不应该与普通设置平级。

推荐：

```text
设置
├── 外观
│   ├── 外观模式
│   ├── 每周起始日
│   └── 主题
├── 日历
│   ├── 默认显示方式
│   ├── 农历
│   ├── 黄历
│   ├── 节气
│   └── 节日
├── 通知
│   ├── 通知权限
│   ├── 日程提醒
│   ├── 重要纪念日
│   ├── 节气提醒
│   └── Live Activities
├── 数据与同步
│   ├── iCloud
│   ├── 导入 / 恢复
│   ├── 系统日历
│   ├── 联系人
│   └── 高级数据设置
│       ├── 冲突策略
│       └── 数据统计
└── 关于
```

---

# 14. 产品视觉方向

目标不是“传统中国风 App”，而是：

> **Apple 原生现代感 + 中国文化信息。**

关键词：

```text
简洁
克制
留白
层级
原生
高信息密度但可控
```

避免大量：
- 毛笔字
- 红金配色
- 祥云
- 古典纹理
- 复杂装饰

---

# 15. 主日历信息层级

第一眼：

```text
今天是哪一天？
```

第二眼：

```text
农历是什么？
```

第三眼：

```text
今天有什么重要事情？
```

推荐信息层级：

```text
日期
 ↓
农历
 ↓
节气 / 节日
 ↓
天气
 ↓
黄历
 ↓
今日安排
```

---

# 16. 黄历 UI

第一屏不要堆满所有信息。

推荐：

```text
今日黄历
────────
宜
搬家 · 祭祀 · 出行

忌
动土 · 开仓

更多 →
```

展开后再展示：
- 冲
- 煞
- 五行
- 神位
- 财神 / 喜神方向
等详细信息。

---

# 17. Widget

Widget 的职责是快速获取信息，不是完整 App。

### Small

```text
今日
九月二十
农历八月初九
```

### Medium

```text
今日
九月二十 · 星期日
农历八月初九
宜 出行 · 会友
```

### Large

可以加入：
- 日期
- 农历
- 节气
- 天气
- 今日事件

继续使用现有 App Group：

```text
group.com.qinghe.calendar
```

推荐维持：

```text
EventStore
 ↓
WidgetSnapshot
 ↓
App Group
 ↓
Widget
```

Widget 不应直接依赖完整 EventStore。

---

# 18. iPad UI

iPad 不应该只是把 iPhone UI 放大。

推荐：

```text
Sidebar + Calendar + Inspector
```

例如：

```text
┌────────────┬───────────────────────┬──────────────┐
│ 日历       │         月历          │ 今日         │
│ 月         │                       │ 农历         │
│ 年         │                       │ 黄历         │
│ 日程       │                       │ 天气         │
│ 设置       │                       │ 今日安排     │
└────────────┴───────────────────────┴──────────────┘
```

空间足够时，同时显示月历和今日详情。

**iPad 没有 iPhone Dynamic Island。不要制作假的 Dynamic Island。**

---

# 19. App Icon

保留当前“日历 / 笔记本”方向，不要彻底换风格。

改进：
- 更扁平
- 更现代
- 减少复杂阴影
- 优化螺旋装订
- 保持日历识别度
- 缩小到 Home Screen 仍清晰

不要加入大量传统纹样。

---

# 20. Dynamic Island / Live Activities 产品定位

核心概念：

# 清和时间胶囊

Dynamic Island 不是“迷你日历”，而是：

> **当前最值得关注的时间事件。**

不要长期展示：
- 完整农历
- 黄历
- 天气
- 大量宜忌
- AI 文案

推荐优先级：

```text
普通日程        ❌
高优先级提醒    ✅
倒计时          ✅
即将发生事件    ✅
节气            ⚪
重要纪念日      ✅
节日            ⚪
黄历            ❌
天气            ❌
AI 建议         ❌
```

V1 推荐同一时间只维护一个主要时间胶囊。

---

# 21. Live Activity 生命周期

定义：

```swift
enum QingheActivityPhase: String, Codable, Hashable {
    case scheduled
    case upcoming
    case live
    case ending
    case completed
    case stale
}
```

业务生命周期：

```text
scheduled → upcoming → live → ending → completed
```

`stale` 是系统内容状态，不要简单当作业务阶段。

---

# 22. Live Activity 类型

```swift
enum QingheActivityType: String, Codable, Hashable {
    case event
    case reminder
    case countdown
    case anniversary
    case solarTerm
}
```

---

# 23. Live Activity 数据模型

建议：

```swift
struct QingheLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: QingheActivityPhase
        var title: String
        var subtitle: String?
        var startDate: Date?
        var endDate: Date?
        var eventType: QingheActivityType
        var icon: String
        var progress: Double?
        var countdownTarget: Date?
        var isImportant: Bool
    }

    var activityID: String
    var eventID: String?
    var title: String
    var createdAt: Date
    var deepLink: String
}
```

实际实现前检查当前 ActivityKit API、Swift 版本和 deployment target。

---

# 24. Live Activity Manager

推荐：

```swift
@MainActor
final class QingheLiveActivityManager {
    func start(event: CalendarEvent)
    func update(eventID: UUID, phase: QingheActivityPhase)
    func end(eventID: UUID)
    func endAll()
}
```

但 `EventStore` 不应该直接调用 ActivityKit。

正确：

```text
EventService
 ↓
QingheActivityCoordinator
 ↓
QingheLiveActivityManager
 ↓
ActivityKit
```

---

# 25. Activity Coordinator

职责：决定当前哪个事件应该进入时间胶囊。

优先级：

```swift
enum QingheActivityPriority {
    case normal
    case important
    case urgent
}
```

综合：
- 事件优先级
- 距离当前时间
- 是否正在发生
- 是否重要
- 是否纪念日
- 用户设置

最终选择：

```text
currentActiveEvent
```

而不是同时塞入所有事件。

---

# 26. Dynamic Island UI

必须支持：

```text
compactLeading
compactTrailing
minimal
expanded
```

### compactLeading

只显示图标，例如时钟、生日等。

### compactTrailing

显示剩余时间，例如：

```text
23m
1h 08m
```

不要每秒手动刷新；优先使用系统 timer 文本，例如：

```swift
Text(date, style: .timer)
```

或适用的 `Text(timerInterval:countsDown:)`。

### expanded

推荐：

```text
┌──────────────────────────┐
│  ◷  妈妈生日              │
│     还有 12 天            │
│                          │
│  农历八月初三              │
│                          │
│  查看日历    稍后提醒      │
└──────────────────────────┘
```

原则：信息少、一眼懂、时间优先。

---

# 27. Lock Screen

锁屏可以比 Dynamic Island 更完整，例如：

```text
妈妈生日
还有 12 天

农历八月初三
星期日

打开清和日历 →
```

Live Activity 的核心是 glanceable information，不是复制通知中心。

---

# 28. iPad Live Activity

同一个 Live Activity 在：

```text
iPhone
→ Dynamic Island + Lock Screen

iPad
→ Lock Screen + Home Screen
```

不要在 iPad 中模拟 Dynamic Island。

---

# 29. 节气 Live Activity

节气可以做短生命周期活动，例如：

```text
白露
04:48
```

或者：

```text
白露已至
今天 04:48
```

不要全年常驻 Dynamic Island。节气是事件，不是常驻状态。

---

# 30. Live Activity 设置

建议位于：

```text
设置 → 通知 → Live Activities
```

设置：

```text
Live Activities             开
重要日程                     开
重要纪念日                   开
节气                         开
仅高优先级事件               关
默认提前时间
  ○ 15 分钟
  ● 30 分钟
  ○ 60 分钟
```

---

# 31. Live Activity 技术策略

第一版：

```text
本地 ActivityKit
```

不需要服务器。

未来：

```text
ActivityKit Push / APNs
```

再考虑远程更新。

Activity 应合理设置 `staleDate`，让系统知道内容可能过期。不要自己高频刷新。

---

# 32. Deep Link

点击 Live Activity 必须进入对应事件，而不是统一打开首页。

建议：

```text
qinghe://event/{eventID}
```

需要有明确的 Deep Link Router。

---

# 33. Live Activity 文件建议

结合现有仓库，优先考虑：

```text
Sources/LunisolarCalendarApp/
└── Features/
    └── LiveActivity/
        ├── QingheLiveActivityAttributes.swift
        ├── QingheActivityType.swift
        ├── QingheActivityPhase.swift
        ├── QingheActivityPriority.swift
        ├── QingheActivityCoordinator.swift
        └── QingheLiveActivityManager.swift
```

Widget Extension 中：

```text
LunisolarWidget/
└── LiveActivity/
    ├── QingheLiveActivity.swift
    ├── LiveActivityLockScreenView.swift
    ├── LiveActivityExpandedView.swift
    ├── LiveActivityCompactView.swift
    ├── LiveActivityMinimalView.swift
    ├── LiveActivityTheme.swift
    └── LiveActivityPreview.swift
```

**开发前必须检查当前 Widget Target 的真实结构，不得盲目创建。**

---

# 34. Accessibility

所有 Live Activity 和关键 UI 都要考虑：
- Dynamic Type
- VoiceOver
- Reduce Motion
- Reduce Transparency
- `isLuminanceReduced`
- Always-On / 低亮度环境

不要使用复杂动画或高频变化。

---

# 35. AI 功能架构

未来增加 AI 助手时，禁止：

```text
AI → 直接修改 EventStore
```

正确：

```text
AI Assistant
 ↓
Intent Parser
 ↓
Structured Command
 ↓
Validation
 ↓
EventService
 ↓
EventStore
```

例如：

> 明天下午三点提醒我给妈妈打电话。

AI 应转换成类似：

```json
{
  "intent": "create_reminder",
  "title": "给妈妈打电话",
  "start": "tomorrow 15:00",
  "reminder": "at_start"
}
```

再由业务层验证并创建事件。

AI 不应直接写 JSON 文件、数据库或 CloudKit。

---

# 36. AI 功能路线

第一阶段：
- 自然语言创建日程
- 查询日程
- 修改日程
- 删除日程

第二阶段：
- 智能整理日程
- 生日识别
- 农历生日转换
- 节气提醒建议

第三阶段：
- AI 日历助手
- 根据空闲时间生成计划
- 用户确认后批量创建事件

核心对象可以设计为：

```text
CreateEventRequest
UpdateEventRequest
DeleteEventRequest
CalendarPlan
```

---

# 37. 通知架构

建议独立：

```swift
NotificationScheduler
```

负责：
- schedule
- cancel
- reschedule

EventService 调用它；不要让 CalendarView 直接操作 `UNUserNotificationCenter`。

---

# 38. 测试策略

必须增加 Golden Tests，重点：

```text
春节
元宵
清明
端午
七夕
中秋
重阳
冬至
立春
```

重点覆盖：
- Gregorian → Lunar
- Lunar → Gregorian
- 闰月
- 农历三十
- 农历生日
- 立春边界
- 24 节气
- 干支
- 时区
- 跨年
- 重复事件
- CloudKit merge
- 删除 tombstone

特别要测试 2026 立春前后，例如：

```text
2026-02-04 03:59
2026-02-04 04:01
```

不能简单得到相同的干支年判断。

---

# 39. 架构改进优先级

推荐顺序：

```text
1. 日期 / 节气 / 干支边界
2. 时区统一
3. Golden Tests
4. EventService
5. Settings 2.0
6. Calendar UI
7. Widget
8. Live Activity
9. iPad
10. AI
```

不要为了追求“AI”而先破坏基础日期系统。

---

# 40. Dynamic Island MVP

第一版只做：

```text
重要日程
倒计时
重要纪念日
```

暂时不要把以下内容放入核心 Live Activity：

```text
黄历
天气
AI 建议
全部节日
完整农历信息
```

---

# 41. 完整用户流程示例

用户输入：

> 明天下午 3 点提醒我开会。

系统：

```text
AI / UI
 ↓
CreateEventRequest
 ↓
EventService
 ├── EventStore
 ├── NotificationScheduler
 ├── WidgetSnapshot
 └── ActivityCoordinator
        ↓
   Live Activity
```

临近会议：

```text
Dynamic Island
会议
29m
```

展开：

```text
会议
下午 3:00
29 分钟后开始
打开日历
```

点击后：

```text
qinghe://event/xxxx
```

直接进入该事件。

---

# 42. Swift 6 并发要求

新增代码必须正确处理：

```text
Sendable
@MainActor
nonisolated
actor
async/await
```

尤其：
- CloudKit
- URLSession
- ActivityKit
- UserNotifications
- Widget

不要为了“消除错误”而滥用：

```swift
@unchecked Sendable
```

只有证明线程安全时才允许使用。

---

# 43. AI Coding Agent 工作流程

每次任务严格执行：

## Step 1：扫描
读取：

```text
Package.swift
README.md
项目结构
Target 配置
相关 Feature
相关 Tests
```

## Step 2：分析
输出：

```text
当前实现
问题
影响范围
建议修改
风险
```

## Step 3：计划
逐文件说明：

```text
文件路径
为什么修改
修改什么
不修改什么
```

## Step 4：小步实施
不要一次性重构整个项目。

## Step 5：验证
至少运行适用的：

```text
swift build
swift test
xcodebuild
```

并运行相关单元测试。

## Step 6：总结
输出：

```text
修改文件
核心变化
测试结果
剩余问题
下一步
```

---

# 44. UI 任务的强制检查项

如果任务涉及 UI，必须考虑：

```text
信息架构
视觉层级
组件结构
Loading
Empty State
Error State
Accessibility
Dark Mode
Dynamic Type
iPhone
iPad
```

---

# 45. 数据任务的强制检查项

必须考虑：

```text
Model
Persistence
Migration
Sync
Conflict
Timezone
Concurrency
Tests
```

---

# 46. Live Activity 任务的强制检查项

必须检查：

```text
ActivityAttributes
ContentState
Activity.request
Activity.update
Activity.end
staleDate
DynamicIsland
Lock Screen
iPad
Deep Link
Accessibility
Availability
```

---

# 47. AI 任务的强制检查项

必须检查：

```text
Intent
Command
Validation
Confirmation
Domain Service
Persistence
Undo
Error Handling
Privacy
```

AI 不应该直接：

```text
写数据库
改 CloudKit
改底层 JSON
```

---

# 48. 不允许的开发方式

禁止：

### 48.1 随意重写核心算法
尤其：

```text
LunarCore
Huangli
EventStore
CloudKit
```

### 48.2 为 UI 随意增加第三方框架
优先 Apple 原生。

### 48.3 在 View 中堆业务逻辑
错误：

```text
View
 ├── 日期计算
 ├── CloudKit
 ├── 通知
 ├── ActivityKit
 └── 数据库
```

### 48.4 AI 直接写数据层
必须经过 Domain / Service。

### 48.5 一次性大规模移动文件
应该分阶段迁移，每一步可编译、可测试、可回滚。

---

# 49. 推荐产品路线

## Phase 1：基础产品化

```text
主日历
黄历
日程
设置
Widget
```

## Phase 2：数据能力

```text
iCloud
导入
联系人
系统日历
通知
```

## Phase 3：时间胶囊

```text
Live Activities
倒计时
重要事件
纪念日
节气
```

## Phase 4：iPad

```text
Sidebar
多栏
Inspector
Widget
Live Activity
```

## Phase 5：AI

```text
自然语言日程
AI 查询
AI 计划
AI 日历助手
```

---

# 50. 最终产品哲学

清和日历应该成为：

> 一个真正适合中国用户日常生活的现代日历。

核心体验：

```text
今天
 ↓
农历
 ↓
节气
 ↓
黄历
 ↓
天气
 ↓
日程
 ↓
提醒
 ↓
时间胶囊
 ↓
AI 助手
```

不是功能堆砌，而是：

> **围绕“时间”组织所有信息。**

用户最终不应该觉得这是一个复杂的传统历法工具，而应该觉得：

> **这是一个非常自然、非常现代，但真正懂中国时间文化的日历。**

---

# 51. AI 最终执行命令

从现在开始，把本文档视为：

```text
PROJECT_CONTEXT
PRODUCT_REQUIREMENTS
ARCHITECTURE_SPEC
UI_SPEC
LIVE_ACTIVITY_SPEC
AI_DEVELOPMENT_RULES
```

在修改清和日历之前：

1. 阅读本文档。
2. 阅读真实代码。
3. 不假设代码存在。
4. 不重复实现已有能力。
5. 优先复用现有核心模块。
6. 不破坏 Swift 6 concurrency。
7. 不随意增加第三方依赖。
8. 不直接重写整个项目。
9. 所有日期逻辑考虑时区。
10. 所有农历 / 节气 / 干支逻辑必须有测试。
11. 黄历必须区分数据来源。
12. EventStore 不直接承担 UI 副作用。
13. AI 不直接修改数据库。
14. Live Activity 不直接耦合 EventStore。
15. iPad 不模拟 Dynamic Island。
16. Live Activity 优先显示“时间事件”。
17. UI 遵循 Apple 原生设计语言。
18. 修改后执行编译 / 测试验证。
19. 遇到架构冲突先分析，再修改。
20. 每次任务输出修改文件、测试结果、风险和下一步。

**第一步永远是：扫描项目结构并分析现有实现，而不是立即写代码。**

---

# 52. AI 每次修改后的固定输出模板

```text
## 1. 任务目标

## 2. 当前代码分析

## 3. 发现的问题

## 4. 修改方案

## 5. 修改文件
- path/to/fileA
- path/to/fileB

## 6. 核心代码变更

## 7. 编译 / 测试结果

## 8. 兼容性检查
- iOS
- iPadOS
- Swift 6
- Dark Mode
- Accessibility

## 9. 风险

## 10. 下一步
```

---

# END

**执行要求：先理解、后设计；先小改、后重构；先保证正确性，再增加功能；先建立稳定的时间/日期底座，再做 Live Activity、iPad 和 AI。**
