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

1. 用 Xcode 真机 / iOS Simulator 完成 ActivityKit 真机验证。
2. 增加 Live Activity UI Snapshot / Preview。
3. 完成 iPad 横屏三栏细节优化。
4. 统一 EventService 与 CountdownService 的业务边界。
5. 增加完整时区 Golden Tests。
6. 继续清理 Package.swift 的 SwiftPM unhandled-file 警告。
7. 再进入 AI Assistant 的 Intent → Command → EventService 架构。

- 2026-09-20: 修复 `LunisolarCalendarApp.swift` 使用 `ActivityAuthorizationInfo` 但缺少 `ActivityKit` import 导致 Xcode 编译错误的问题。
