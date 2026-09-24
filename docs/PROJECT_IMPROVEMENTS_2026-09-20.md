# 清和日历项目改进记录 · 2026-09-20

本次基于 2026-09-20 项目快照进行 P0/P1 级改进，目标是修复时间胶囊边界问题、收紧事件业务边界，并增加 Live Activities 用户控制。

## 已完成

### 1. 修复节气 nextTerm 精确时刻问题

旧逻辑按当天 00:00 判断“未过去”，导致某节气当天已经过了交节时间后，`nextTerm(from:)` 仍可能返回当天已经结束的节气。

现在按节气精确 `Date` 比较。

### 2. 修复节气 Live Activity 在交节后无法出现的问题

旧逻辑只查询 `nextTerm(from:)`。节气交节后的两小时窗口内，查询会跳到下一个节气，因此“节气已至”无法进入时间胶囊。

新增：

```swift
SolarTermProvider.termAround(_:window:)
```

时间胶囊现在支持：

- 交节前：未来节气进入候选
- 交节后 2 小时：当前节气进入候选
- 超过 2 小时：自动结束

### 3. 节气候选 ID 改为稳定 ID

旧实现每次生成节气候选都会创建 `UUID()`，容易导致同一个节气被识别为不同 Activity 内容。

现在使用交节时间构造确定性 UUID，使同一节气能够稳定 diff / update。

### 4. Live Activity staleDate 修正

旧实现对 upcoming 事件直接使用 `startDate` 作为 `staleDate`，可能在事件刚开始时就被系统标记为 stale。

现在：

- 有明确结束时间 → 使用 `endDate`
- 没有结束时间 → `startDate + 2h`

### 5. 时间胶囊跟随事件变更自动同步

AppRoot 现在监听 `EventStore.revision`。

当发生：

- 新增事件
- 修改事件
- 删除事件
- 完成状态变化
- iCloud merge

会重新选择当前最值得关注的时间胶囊，避免岛上继续显示旧事件。

### 6. 增加 Live Activities 总开关

设置 → 提醒通知 → 时间胶囊。

用户关闭后会立即结束当前清和时间胶囊；重新开启后重新计算候选。

同时尊重系统 `ActivityAuthorizationInfo().areActivitiesEnabled`。

### 7. EventService 进一步收紧业务边界

新增统一方法：

```swift
upsertEvent(_:flush:)
removeEvent(_:flush:)
setCompleted(_:flush:)
```

EventRow / EventEditView 的主要事件写操作改为通过 EventService，进一步减少 View 直接修改 EventStore 的情况。

### 8. 增加测试

新增覆盖：

- 同一天交节之后 `nextTerm` 不返回已过去节气
- `termAround` 可以找到刚刚交节的节气
- 节气交节后两小时仍可生成 Live Activity 候选
- 同一节气候选 ID 稳定

## 验证

在当前 Linux 环境执行：

```bash
swift build --disable-sandbox
```

结果：**Build complete**。

`swift test` 能完成源码编译，但当前容器的 Swift Observation Linux 链接器存在：

```text
libswiftObservation.so: undefined reference to swift::threading::fatal(...)
```

因此不能把该环境下的 XCTest 最终链接失败解释为项目 Swift 源码编译失败。项目源码本身已通过 `swift build` 编译。

## 下一阶段建议

1. ~~用 Xcode 真机 / iOS Simulator 完成 ActivityKit 真机验证。~~ ✅ 2026-09-23 真机测试通过。
2. 增加 Live Activity UI Snapshot / Preview。
3. 完成 iPad 横屏三栏细节优化。
4. ~~统一 EventService 与 CountdownService 的业务边界。~~ ✅ 2026-09-24：倒数日写操作收口进 EventService（saveCountdown/deleteCountdown）；倒数日灵动岛交互收口进新增 CountdownActivityController；iCloud 同步控制收口进 AppLifecycleCoordinator。
5. 增加完整时区 Golden Tests。
6. ~~继续清理 Package.swift 的 SwiftPM unhandled-file 警告。~~ ✅ 2026-09-24：LunarCore target 按目录 exclude，"found 66 file(s) unhandled" 警告消除。
7. 再进入 AI Assistant 的 Intent → Command → EventService 架构。

- 2026-09-20: 修复 `LunisolarCalendarApp.swift` 使用 `ActivityAuthorizationInfo` 但缺少 `ActivityKit` import 导致 Xcode 编译错误的问题。


---

# 清和日历项目改进记录 · 2026-09-24 追加

基于 2026-09-23 真机验证通过的 P0 架构稳定化，继续完成遗留收口并打通 macOS 命令行测试。

## 已完成

### P0 六项收口（2026-09-23，真机验证通过）

1. `App/AppLifecycleCoordinator.swift`：launch / scenePhase / 事件 revision / 时间胶囊开关 等生命周期副作用全部收拢；AppRootView 不再 import ActivityKit / CloudKit / os。
2. `App/NavigationCoordinator.swift`：iPhone Tab / iPad Sidebar / 选中日期统一状态源（此前已就位，本轮确认接线完整）。
3. `App/DeepLinkRouter.swift`：qinghe:// 统一路由；移除旧 NotificationCenter 深链机制（qingheDeepLinkOpenEvent + onReceive 死监听）。
4. `Services/TimeCapsuleCoordinator.swift`：选候选 → 组装 display → 调 ActivityKit 链路收拢（此前已就位，删除 AppRootView 内重复副本）。
5. Store 写入收口：`EventService` 新增 `flushPendingSave()` / `mergeImportedEvents(_:policy:skipSync:)` / `clearAllEvents()` / `saveCountdown(_:flush:)` / `deleteCountdown(id:flush:)`；`SettingsView` / `CountdownView` / `EventEditView` 直连 store 写入全部清除。
6. `Package.swift`：`LunarCore` target 按目录 exclude，SwiftPM "found 66 file(s) which are unhandled" 警告消除。

### P0 遗留收口（本轮）

7. CloudKit 收口：`AppLifecycleCoordinator` 新增 `CloudSyncEnableResult` + `enableCloudSync()` / `setCloudSyncEnabled(_:)` / `syncNow()`；`SettingsView` 删除 `enableSyncForFirstTime()` / `handleSyncToggle()`，首开同步的 toast 时机改为"首次双向同步 + 通知重排完成后"（旧代码 fire-and-forget 先弹）。
8. ActivityKit 收口：新增 `Services/CountdownActivityController.swift`（`ToggleOutcome` + `isOnIsland` / `toggleIsland` / `endAllActivities` / `autoStartAfterSave`）；`CountdownView` 行内上岛/下岛、编辑器自动上岛、SettingsView 时间胶囊开关的"结束全部活动"均改走控制器。Views 层对 ActivityKit / CloudKit / UserNotifications / WidgetKit 零直连。

### macOS 测试宿主打通（本轮）

9. `swift build` / `swift test` 在 macOS 宿主上现在可用（此前仅 Linux 可用）：
   - 全部 ActivityKit/WidgetKit 编译守卫追加 `&& !os(macOS)`（ActivityKit API 在 macOS SDK 标记 unavailable，但 canImport 为真）；
   - `AppTheme.scaled()` 的 `UIFont.TextStyle` 参数改为按平台 typealias（macOS 用占位枚举，退化为固定字号）；
   - `YearOverviewView` / `CalendarDisplaySettingsView` / `CalendarMonthView` / `EventEditView` / `DayDetailView` 的 iOS-only API（`insetGrouped`、`systemGroupedBackground`、`navigationBarTitleDisplayMode`、`.topBarLeading/Trailing`）补齐 `#if canImport(UIKit)` 守卫或改用 `ColorExtensions` / `platformTopBar*` 跨平台封装；
   - `WeatherService`：`authorizedWhenInUse` 在 macOS 不可用 → 抽 `isAuthorized(_:)` 按平台判定（iOS = WhenInUse|Always，macOS = Always）。

### 小债清理

10. `EventEditView`：删除保存后与 `upsertEvent` 内部重复的 `refreshNotification` 调用（消除双份 cancel+schedule 系统调用）及随之失效的 `resultingEvent` 变量。

## 验证

- `swift build`（macOS 宿主）✅ Build complete
- `swift build --triple arm64-apple-ios17.0-simulator --sdk <iphonesimulator>` ✅ Build complete（iOS SDK 编译零告警）
- `swift test`（macOS 宿主）✅ **150 tests, 0 failures**（2026-09-24 首次全绿，含 SolarTermGolden / YearBoundary / FestivalGolden / EventStore / ICloudSync 全部门类）。
- Xcode 构建 / 真机路径仍以下一节的真机验证清单为准。

## 下一阶段建议（更新）

1. Live Activity UI Snapshot / Preview（P1）。
2. iPad 横屏三栏细节（P1）。
3. 完整时区 Golden Tests（部分已由 SolarTermGoldenTests 的 Asia/Shanghai 断言覆盖，补跨时区对照用例）。
4. AI Assistant 的 Intent → Command → EventService 架构（P1+）。
5. （可选）拆独立 `CountdownService`：现 EventService 的 5 个倒数日方法就是现成搬迁单元。
