# P4 维护性重构评估（2026-10-04）

**结论先说**：值得拆的只有 **1 个文件**（`CalendarMonthView.swift`），
第 2 顺位是 `AIAssistantView.swift`；其余大文件**不建议动**——理由见下。

## 一、按规模排序（前 12）

| 行数 | 文件 |
|---:|---|
| 1122 | `Stores/EventStore.swift` |
| 894 | `Widgets/LunisolarWidgetViews.swift` |
| 685 | `Sync/RealCloudKitProvider.swift` |
| 661 | `Support/DataPortability.swift` |
| 657 | `Views/AIAssistantView.swift` |
| 613 | `Tests/…/EventStoreTests.swift` |
| 598 | `Services/AICommandParser.swift` |
| **583** | **`Views/CalendarMonthView.swift`** |
| 545 | `Tests/…/AIAssistantTests.swift` |
| 511 | `Tests/…/ICloudSyncTests.swift` |
| 507 | `Tests/…/CalendarEventTests.swift` |
| 507 | `Support/NotificationManager.swift` |

> 📌 **更正计划里的一处数字**：计划写「`CalendarMonthView` 900+ 行」——
> 实测 **583 行**（本轮的 P3 抽取也让它变短了）。行数不是本次决策依据，见下。

## 二、变更热点（近 60 次提交，改得最频繁）

| 次数 | 文件 |
|---:|---|
| **23** | **`Views/CalendarMonthView.swift`** |
| 10 | `Views/SettingsView.swift` |
| 10 | `App/LunisolarCalendarApp.swift` |
| 9 | 四张 `Localizable.strings`（机械性，可忽略）|
| 8 | `Views/CountdownView.swift` |
| 8 | `Views/AIAssistantView.swift` |
| 7 | `Views/EventEditView.swift` |

**这才是决策依据**：`CalendarMonthView` 一个文件占了近 60 次提交里的 23 次——
它每次改动都要在 583 行里找一个位置，且它内部**只有 1 个 MARK**
（`节日自适应背景与强调色`），说明**没有按职责组织**。

## 三、优先级与理由

### P4-1 `CalendarMonthView.swift`（建议做）

- 信号：变更频率第一（23/60）+ 内部无职责分区（仅 1 个 MARK）；
- 好消息：大块逻辑**已经抽走了**——网格派生在 `CalendarMonthGridModel`（`GridCellModel.derive`）、
  网格构建在 `CalendarMonthGridBuilder`、弹层在 `CalendarMonthSheets`、
  手势在 `CalendarMonthSwipeGesture`。**剩下的是视图组装**，正好适合抽成小 struct；
- 拆法（纯抽取，行为不变）：顶栏/工具栏、月份标题（含日期跳转按钮）、节气倒计时条、
  选中日卡片区各自独立成一个 `View` struct，父视图只做组合；状态仍由父视图持有，
  子视图通过参数 + 闭包（`@Binding`/回调）接入——**不搬家状态**，降低风险；
- 工作量：约 1 轮（抽取 + 编译 + **两条 UI 通道**——这个页面正是 UI 用例覆盖重点）；
- 风险：中。视图抽取容易碰掉布局与状态所有权，必须两通道验证。

### P4-2 `AIAssistantView.swift`（可选，第 2 顺位）

657 行、8 次变更。聊天界面天然可拆（消息气泡 / 输入条 / 预览卡）。
**但它没有 P4-1 那么痛**，建议等 P4-1 做完看效果再定。

### 不建议动

| 文件 | 为什么不 |
|---|---|
| `EventStore.swift`（1122 行，最大）| 是数据层、测试覆盖最重（613 行测试），**改动风险最高而变更频率不在前十**；拆分收益（找代码快一点）远小于回归风险 |
| `LunisolarWidgetViews.swift`（894）| 变更频率不在前十；小组件视图之间高度耦合于同一份快照模型 |
| `RealCloudKitProvider.swift`（685）/ `DataPortability.swift`（661）| 变更频率低、职责已经单一（一个同步、一个导入导出）|

## 四、建议的推进方式

1. **一轮只做一个文件**，且**只做抽取、不改行为**——这样两条 UI 通道能作为等价性证据；
2. 抽取后跑：`swift test`（4 时区）+ 两条 UI 通道；
3. 若某次抽取导致 diff 超过「移动代码」的量级（例如顺手改了布局），
   **停下来拆成两次提交**——否则出问题时分不清是抽取还是改动引起的；
4. 验收标准不是"文件变小了"，而是：**同一个改动需要打开的文件数下降**（下次真实需求时检验）。
