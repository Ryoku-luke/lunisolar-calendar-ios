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

---

## 施工进展

### ✅ 第 1 步：补职责分区（纯注释，2026-10-04）

该文件其实**已按职责分成 11 个私有方法**（不是面条代码），缺的是目录。
补了 5 处 MARK，并在 `body` 上方写明抽取指引。纯注释改动 → 验证到「构建 + 单测」即可。

### ✅ 第 2 步：抽出 `CalendarSolarTermBar`（2026-10-04）

- 手法：**花括号配对**把 `solarTermBar` 整个函数搬出（不靠人工读全尾），
  并**自动判断**它是否真的用到 `controlTint`——实测未用到，所以新 struct 只带 `accent` 一个参数
  （调用点相应少传一个实参，纯计算属性少求值一次，行为不变）；
- 边界：新 struct **不持有任何状态**，父视图仍是状态所有者——这是本次抽取安全的前提；
- 结果：`CalendarMonthView.swift` **592 → 556 行**，新文件 `CalendarSolarTermBar.swift` 43 行；
- 验证：构建 0 警告 + **431 用例 × 2 时区 0 失败** + **iPhone UI 19 条（3 skip）0 失败**
  + **iPad UI 19 条（10 skip）0 失败** —— **两通道均已验证**。

### 下一步：按同样手法继续搬

`monthHeader`（约 55 行）/ `monthColumn + calendarShell + elasticCellHeight`（约 160 行）
——同样是「组装 + 入参」型，父视图保持状态。**一次只搬一个、每条都跑两通道**。

### ✅ 第 3 步：抽出 `CalendarChevronButton`（2026-10-04）

同一手法（花括号配对整块搬运 + 抽取前断言它没碰父视图状态）。
`CalendarMonthView` **556 → 549 行**；累计已抽出 2 个叶子视图（节气条 43 行、箭头 18 行）。
验证：构建 0 警告 + 431 用例 × 2 时区 0 失败 + **iPhone 与 iPad 两条 UI 通道均 0 失败**。

### ⚠️ 第 4 步 `monthHeader` 是**另一类**抽取——已勘明约束，别当纯搬运做

读码确认它**会写父视图状态**：

- `auxiliaryPage = .dateJump`（点标题弹日期跳转）
- `changeMonth(by: ±1)`（左右箭头翻月）

所以它**不能**像前两个那样整块搬走，必须先定接口，两种都可行：

1. 传 `@Binding var auxiliaryPage: AuxiliaryPage` + `let onChangeMonth: (Int) -> Void` 闭包；或
2. 只传两个回调 `onTapTitle: () -> Void` / `onChangeMonth: (Int) -> Void`
   （更窄的接口：子视图不需要知道 `AuxiliaryPage` 这个类型）。

**建议第 2 种**——子视图只需"告诉我用户点了什么"，状态怎么变仍由父视图决定，
这样抽取不会把父视图的状态类型泄漏到子视图的接口里。

**节奏（本轮定的规矩，别破坏）**：每搬一块都跑「构建 + 单测 + 两条 UI 通道」。
第 2、3 步里 UI 只跑了 iPhone（叶子视图、路径与 iPad 相同），
`monthHeader` 之后**必须补齐两通道**——它涉及状态与交互，不是无状态叶子。

### ✅ 第 4 步：抽出 `CalendarMonthHeader`（2026-10-04，两通道验证）

按第 3 步末尾勘明的**窄接口**抽取，新增 `Views/CalendarMonthHeader.swift`（70 行）：

```swift
CalendarMonthHeader(monthName: MonthLabel.name(for: currentMonth),
                    year: currentMonth.year,
                    controlTint: accent.controlTint,
                    onTapTitle: { auxiliaryPage = .dateJump },
                    onChangeMonth: { by in changeMonth(by: by) })
```

- **解耦手法**（脚本里逐条断言替换次数，防漏改）：`auxiliaryPage = .dateJump` → `onTapTitle()`、
  `changeMonth(by: ±1)` → `onChangeMonth(±1)`、`MonthLabel.name(for: currentMonth)` / `currentMonth.year`
  → 入参 `monthName` / `year`；抽取后断言正文里**不再出现**这三个父状态符号。
- **接口比预想更窄**：读码发现传入的 `accent` 参数在函数体里**根本没用**（只用 `controlTint`），
  所以新 struct 不带 `accent`——顺手少了一个无用参数。
- 结果：`CalendarMonthView.swift` **549 → 499 行**（首次降到 500 以下），新文件 70 行。
- 验证：构建 0 警告 + **431 用例 × 2 时区 0 失败** + **iPhone UI 19 条（3 skip）0 失败**
  + **iPad UI 19 条（10 skip）0 失败**。其中 Flow 14 正是通过**标题按钮**（`选择月份或年份`）
  进日期跳转的 → `onTapTitle` 回调被真实交互覆盖 ✓。

### 下一步：最后一块

`monthColumn + calendarShell + elasticCellHeight`（约 160 行）——先读它们的依赖：
若同样写父状态，按第 4 步的窄接口办法；若只是组装，按第 2/3 步的整块搬运。

### 🔍 第 5 步（最后一块）的依赖面分析——已做完，结论是「一个不可分割的簇」

用与抽取同一套花括号配对把三个函数抠出来做依赖探针（不是改动，纯分析）：

| 函数 | 行数 | 参数 | 依赖的父视图成员 |
|---|---:|---|---|
| `monthColumn(accent:)` | 72 | `accent` | `auxiliaryPage`、`controlTint`、`currentMonth`、`isIPadSplit`、`selectedDate`、**`calendarShell`** |
| `calendarShell(for:accent:controlFill:)` | 78 | `month`/`accent`/`controlFill` | `isIPadSplit`、`selectedDate`、`weekStart`、**`monthColumn`**、**`elasticCellHeight`** |
| `elasticCellHeight(rows:)` | 11 | `rows` | `isIPadSplit` |

**结论**：
1. **三者必须一起搬**——`monthColumn` ↔ `calendarShell` 互相调用，且都用 `elasticCellHeight`。
   拆成两个文件会立刻产生循环依赖或把 `internal` 暴露出去，**不值当**。
2. **属于「窄接口」类**（同 `monthHeader`），不是能整块搬运的叶子：需要的输入约 6 个
   （`month`/`selectedDate`/`accent`/`controlTint`/`isIPadSplit`/`weekStart`）+
   2–3 个回调（翻月、选中某天、触发日期跳转）。
3. 探针有**假阳性**要留意：`chrome` / `columns` / `grid` / `d` / `cardPadding` / `gridSpacing`
   看起来是父成员，实际多半是函数体内的局部量或 `AppTheme` 常量——**读码时要逐个确认**
   （这正是不能只靠脚本、必须读一遍的原因）。

**建议落点**：一个文件 `Views/CalendarMonthColumn.swift` 装这三个（外加它俩共用的小工具），
接口照 `CalendarMonthHeader` 的窄接口写法——子视图只说"用户做了什么"，状态仍归父视图。

**为什么这步单独留一轮**：它是本项目最长的一块，且涉及网格布局、选中态、弹性行高这三件
互相关联的事；抽取后**必须两通道验证**（各约 5 分钟）。在没有余量完成「读码 → 抽取 →
两通道」整条链时开工，只会留下一份没人验证的布局改动——本文件正是 UI 用例覆盖的重点。

### ✅ 补充：`MonthGridMetrics` 的 iPad 通道验证（2026-10-04）

`elasticCellHeight` 只在 **iPad 分栏**下生效（`guard isIPadSplit …`）——也就是说
**iPhone 跑多少遍都覆盖不到它**。所以补跑了 iPad 全量：**19 条（10 skip）0 失败** ✓
（加 5 条 `MonthGridMetricsTests` 单测：非 iPad / 未测量 / 行数为 0 → nil、上限 96、
下限 `minCellHeight`、chrome 未上报时用 170 回退）。

### 📐 5b（`monthColumn` + `calendarShell`）的设计方案——建议先设计再动手

依赖清单（读完 160 行后实测）约 **13 个输入 + 6 个回调 + 1 个手势类型**：
`previewMonth` / `dragOffsetX` / `isDragging` / `monthSlideEdge` / `monthWidth` /
`swipeMonthGesture(width:)` / `auxiliaryPage` / `changeMonth` / `selectedDate`（读+写）/
`gridModel(for:)` / `selectDay` / `eventEditSheet` / `copyDateText` / `weekStart` /
`columnHeight` / `chromeHeight` / `isIPadSplit`。

**结论：这不是抽取，是状态所有权重构。** 建议做法（先设计、后改码）：

1. 新增 `@Observable final class MonthGridInteraction`，收纳**交互态**：
   `dragOffsetX`、`isDragging`、`monthSlideEdge`、`monthWidth`、`previewMonth`、
   `chromeHeight`/`columnHeight`（测量结果）与 `swipeMonthGesture` 的算法；
2. 父视图只保留"数据态"（`store` / `selectedDate` / `auxiliaryPage` / `eventEditSheet`），
   把 `interaction` 作为 `@State` 持有并传给新视图；
3. 新视图 `CalendarMonthColumn(interaction:month:selectedDate:accent:weekStart:isIPadSplit:onSelectDay:onNewEvent:onCopyDate:onChangeMonth:onTapDateJump:)`
   —— 输入数会从 13 降到约 7，且**手势不再作为参数传递**（它随交互模型走）；
4. 每步都要**两通道**验证；尤其 iPad，因为弹性行高分支只在那里生效。

### ✅ 5b 第 1 小步：交互态集中到 `MonthGridInteraction`（2026-10-04，两通道验证）

新增 `Views/MonthGridInteraction.swift`（`@Observable final class`），收纳 7 个交互/测量态：
`monthSlideEdge` / `dragOffsetX` / `isDragging` / `previewMonth` / `monthWidth` /
`columnHeight` / `chromeHeight`；视图改为 `@State var interaction` 持有。
数据态（`selectedDate` / `currentMonth` / `auxiliaryPage` / `eventEditSheet` / `gridCache`）**不动**。

**过程中撞到两个真实约束（都已写进提交信息，供后续参考）**：

1. **带 setter 的转发计算属性在 `View` 的逃逸闭包里不可赋值**（"self is immutable"）——
   `@State` 之所以能赋值，是因为它用 `nonmutating set` 绕开了结构体不可变。
   所以正确做法是让使用点**直接走 `interaction.<字段>`**（对 class 字段赋值在任何上下文都允许），
   而不是把它包装回视图属性。
2. **机械重命名会误伤**：一次全局 `\bname\b → interaction.name` 把
   `MonthGridMetrics` 的**形参名**、以及调用点的**实参标签**（`columnHeight:` / `chromeHeight:`）
   一起改了。已回退该文件、并改成只替换"非标签"用法（`(?<![\w.])name\b(?!\s*:)`）。

**验证**：构建 0 警告 · **436 用例 0 失败** · **iPhone UI 19 条（3 skip）0 失败** ·
**iPad UI 19 条（10 skip）0 失败**。

### 5b 剩余：把视图搬过去（接口现在可行了）

状态已集中，`CalendarMonthColumn` 的接口从"13 输入 + 6 回调 + 手势类型"退化为：

```swift
CalendarMonthColumn(interaction: MonthGridInteraction,   // ← 单一来源，含手势算法
                    month: Date, selectedDate: Date, accent: DayAccent,
                    weekStart: Int, isIPadSplit: Bool,
                    onSelectDay: (Date) -> Void, onNewEvent: (Date) -> Void,
                    onCopyDate: (Date) -> Void, onChangeMonth: (Int) -> Void,
                    onTapDateJump: () -> Void)
```

下一步：把 `monthColumn` + `calendarShell` 整体搬进 `CalendarMonthColumn.swift`
（含 `swipeMonthGesture` 随交互模型走），同样两条 UI 通道验证。