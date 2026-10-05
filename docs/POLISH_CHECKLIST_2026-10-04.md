# 打磨清单（2026-10-04）

> 配套文档：`RETROSPECTIVE_2026-10-04.md`（改动清单）、`EXECUTION_PLAN_2026-09-30.md`（执行计划）、
> `REFACTOR_ASSESSMENT_2026-10-04.md`（P4 评估与施工图）。
> **用法**：自上而下做；每条都给了「做法」与「验收」，做完在 `[ ]` 打勾并补上日期与提交号。
> **原则（本次会话验证有效）**：先量后动 · 只搬不改行为 · 每步跑两条 UI 通道 · 判定看总计行。

## P0 · 时间敏感（有外部依赖）

- [ ] **补 2027 年放假安排数据**
  - 现象：三份数据里放假安排的可信边界是 **2027-01-01**；**2026-12-02 起** `swift test` 会开始打印「⚠️ 数据到期预警」，到点后转硬失败。
  - 依赖：国务院办公厅通常在 **11 月底**公布下一年安排。
  - 做法：按 `docs/DATA_UPDATE_RUNBOOK.md` 的「放假安排」流程补 `holidayData`，并同步 `HolidayProviderTests`（2027 那条已是自更新写法）。
  - 验收：`swift test` 4 时区无预警；`DataExpiryTests` 绿；`HolidayProviderTests` 覆盖 2027。
  - 预估：数据到手后 ≤1 小时。**这条红是闹钟，不是 bug。**

## P1 · 未定论（先查证，再决定修不修）

- [x] **未复现的偶发单测失败** —— **2026-10-04 结案（未复现）**
  - 复查：按验收标准跑了 **10 次**（时区轮换 UTC / Asia-Shanghai / America-New_York / Pacific-Auckland，
    UTC 各 3 次），**10/10 全绿（436 用例/次）**，未复现。
  - 结论：按预设标准记为**环境抖动并结案**。⚠️ 但如实说明：这 10 次都在**非跨日时段**（12:04）跑，
    所以清单里"疑似 00:50 跨日"那条假设**没有被测到**——若将来在午夜前后再出现同类失败，
    先看是否与"今天"有关。
  - 若再复现：保留**全量输出**（本次教训：不要只留尾行，否则拿不到用例名）。

- [ ] ~~**未复现的偶发单测失败**（原条目，已按上面结案）~~
  - 现象：某次四时区跑里**单条**失败；随后连跑 5 次（UTC 5 次 + 其余时区各 1 次）未复现；**没抓到用例名**（当时过滤输出只留了尾行）。
  - 怀疑方向（**均未证实**）：① `measure` 型微基准的相对标准差容差；② 依赖「今天」的用例在 00:50 附近跨日。
  - 做法：保留**全量输出**重跑 ≥10 次（或 `swift test --filter` 分批跑定位）；若再出现，先存原始输出再判断。
  - 验收：定位到具体用例（→ 按类型修）或 10 次全绿（→ 记录为环境抖动并结案）。


- [x] **iPad 上的年视图入口** —— **已结案（2026-10-05）：iPad 上不存在该入口，不是缺陷** —— **2026-10-04 已缩小范围（查到一半，未定论）**
  - 现象：iPad 上点月历标题（`选择月份或年份`）后，`全年视图` 按钮查不到；iPhone 正常。
    Flow 14 的「年视图」屏**仍限定 iPhone**（未定论前不留假绿）。
  - **本轮排除的假设**：① "popover 里靠下、List 懒渲染需滚动" —— **已证伪**：
    加 `scrollUntilVisible(maxSwipes: 6)` 后仍找不到（6 次 swipe 后该按钮始终不存在）；
    ② "iPad 上本就不该有这个入口" —— **不成立**：工具栏菜单里另有独立入口
    `CalendarMonthView.swift:201 Button { auxiliaryPage = .dateJump } Label("跳转到日期" …)`，
    且 `CalendarMonthSheets` 里**没有** `isIPadSplit` 门控，面板是 `auxiliaryPage` 驱动的 `.sheet(item:)`。
  - **剩余假设（未验证）**：iPad 上 `title.tap()` 虽然成功，但面板**没有被呈现**
    （或呈现后被 popover/form-sheet 的容器尺寸截断到按钮之外）。
  - 下一步做法：在 iPad 上点标题后**打印无障碍树**（`app.debugDescription` 或断言失败时自动附带），
    看面板到底有没有出现、出现了哪些元素——再决定是修入口还是补测试。
  - 验收：Flow 14 的年视图屏恢复两形态覆盖。

## P2 · 重构剩余（施工图已备）

- [~] **P4-2 ② 拆 `AIAssistantView.body`** —— **第 1 块已落地（2026-10-04）**
  - ✅ **内联提示条 → `AIInlineNotice`**：整条 `if/else-if` 链（24 行）抽出，
    接口是**小枚举** `AIInlineNoticeState`（error / success(message, offDay) / none），
    父视图用一个计算属性把 `inlineError` / `completedMessage` / `completedOffDay`
    映射成一个 state（子视图不持有状态）。
  - 过程教训（两次尝试）：**`body` 里相邻的 `if let` 可能是同一条链**——第一次只取
    起始分支，抽出的文件语法即坏；第二次把"链结束"判定写成
    「深度回到 0 **且**该行恰为 `}` **且**下一非空行缩进 ≤ 16」才抓对。
  - `AIAssistantView` **513 → 496 行**；验证：构建 0 警告 · 436 用例 0 失败 ·
    iPhone 19 条(3 skip) 与 iPad 19 条(10 skip) 均 0 失败（AI 流程断言了成功/失败提示）。
  - ✅ **「解析并预览」按钮 → `AIParseButton`**（第 2 块）：7 行、**不读不写任何状态**、只调 `parse()`
    → 纯搬运。刻意**不抽外面那层 `Section`**：SwiftUI 对 `Section` 有"必须是 List 内容构建器
    直接子节点"的特殊处理，包进自定义视图有丢失分组语义的风险（那会改行为）。
    `AIAssistantView` 496 → 491 行；构建 0 警告 · 436 用例 0 失败 · iPhone 19(3 skip) 与
    iPad 19(10 skip) 均 0 失败。
  - ✅ **「查询结果」Section 的内容行 → `AIQueryResultRows`**（第 3 块）：18 行（`if results.isEmpty`
    + `ForEach`），只依赖入参 `[CalendarEvent]`、不持有状态。按"不搬 Section 本身"的规矩，
    带 `header:` 的 Section 与 header 用的 `queryDate` 都留在父视图。
    `AIAssistantView` 491 → 474 行；构建 0 警告 · 436 用例 0 失败 · iPhone 19(3 skip) 与
    iPad 19(10 skip) 均 0 失败。
  - ⏭ **剩余块**（按"最小自包含"顺序，抽前先量引用哪些 `@State`，碰状态的用窄接口 + 回调）：
    预览卡（`if let d = draft` 分支）· 破坏性确认区（`if let target = destructiveTarget …`）。
    ⚠️ **两次踩过的坑**：①相邻 `if let` 可能是同一条链（先看有没有 `else if`）；
    ②`Section` 不要包进自定义视图（分组语义有风险）——只搬它里面的内容。
  - 📌 **选块方法（脚本化，已验证两次）**：按缩进取 `body` 的内容块 → 按行数升序 →
    对最小块统计"读/写哪些 `@State`" → 无写入才动手（有写入就转窄接口设计）。

- [ ] ~~**P4-2 ② 拆 `AIAssistantView.body`（253 行）**（原条目）~~
  - 现状：顶层块地图已取（16 个候选边界，见评估文档），最大一块是第 40 行的 `List {`。
  - 做法：每块抽成一个子视图；能整块搬就整块搬；碰状态的用**窄接口 + 回调**；抽前先量该块引用哪些 `@State`。
  - ⚠️ 注意：第 265–276 行那段「为什么不做整页收键盘手势」的注释是**活文档**（记录了三种失败写法与实测报错），搬迁时必须跟着对应代码走，不要丢。
  - 验收：抽出的子视图各自成文件 + 两条 UI 通道绿。

- [ ] **P4-2 ③ 逻辑方法移入模型**
  - 现状：**11 个 `@State` 全部被 body 与逻辑段同时触碰**（已实测），不是"抽几个方法"能解决的，属**状态所有权重构**。
  - 做法：先设计 `@Observable` 模型（契约面 = 两面都要用的那些 state），照 P4-1 5b 的顺序：先集中状态、再搬视图。
  - 验收：模型持有状态、视图只渲染 + 回调；两条 UI 通道绿。
  - 依赖：建议**先做完 ②**——引用点分散到子视图后，"谁碰哪个 state" 才看得清。

- [ ] **`swipeMonthGesture` 搬入 `MonthGridInteraction`**
  - 理由：按 5b 的设计，手势算法属于交互模型（当前仍在 `CalendarMonthSwipeGesture.swift` 的视图扩展里，父视图只是挂载）。
  - 验收：模型自己提供手势、父视图不再需要该扩展；两条 UI 通道绿。

- [ ] **`gridCache` 的去处**
  - 现状：网格缓存仍由 `CalendarMonthView` 持有（抽取时**刻意**没搬，避免一次动两样）。
  - 做法：独立成缓存类型，或随交互模型。
  - 验收：视图不再持缓存；两条 UI 通道绿。

## P3 · 覆盖缺口（不是 bug，但"没人守"）

- [ ] **长按上下文菜单的两个回调加断言**
  - 现状：`onNewEvent` / `onCopyDate` 只在长按日期格的菜单里触发，UI 用例不覆盖，目前只有"编译期 + 接线正确"。
  - 做法：Flow 新增「长按日期格 → 断言菜单项存在 → 触发后断言结果」。
  - 验收：两条断言进 iPhone 通道套件。

- [ ] **iPad 深层界面的审计扩展**
  - 现状：Flow 13 覆盖 iPad 5 个侧栏节的主屏；Flow 14 的深层界面里「年视图」暂限 iPhone。
  - 做法：随 P1 第 2 条一起处理；顺带补 iPad 侧栏到各子页的路径。

## P4 · 工程习惯固化（本次会话已用，但还没全部自动化）

- [ ] **把「编译警告即失败」扩到 xcodebuild 两条 UI 通道**
  - 现状：`Tools/run_tests.sh` 的 `CHANNEL_FORBID` 只挂在三条本地通道（swift test / iOS SDK 构建 / UI target 类型检查）；两条 UI 通道未启用。
  - 做法：给 `ui_channel` 也加 forbid 模式（注意 xcodebuild 输出里混有工具链自身的警告，需要像 SwiftPM 缓存那样加白名单）。
  - 验收：真实通道上验证（伪造一条警告确认会红）。

- [ ] **性能基线补真机抽样**
  - 现状：单测基线是合成数据；真机只做过**一次抽样**（211 条真实格式事件：渲染正确、无性能悬崖）。
  - 做法：把这套注入 + 观感检查写进 `DEVICE_TEST_CHECKLIST.md`，或做成可重复的脚本。

## 已知不动（附理由，避免反复讨论）

| 对象 | 为什么不 |
|---|---|
| `EventStore.swift`（1122 行）| 数据层、测试最重（613 行测试）、**变更频率不在前十**——风险 > 收益 |
| `LunisolarWidgetViews`（894）/ `RealCloudKitProvider`（685）/ `DataPortability`（661）| 变更频率低、职责已单一 |
| D6 导出格式 | 三种（ics/json/csv）已覆盖互换、备份、表格三种用途；无新需求不加 |
| D8 的 `appTint` 本体 | 只压了「选中日填充」到刚好达标；品牌色本身不动 |

## 已完成（对照用，避免重复劳动）

- ✅ **P2 全部**：存储迁移 / 导入覆盖语义 / 校时与前置校验 / 到期防线（含警报自检）/ 导出入口
- ✅ **P3 全部**：对比度 / 横屏 / 漏译（含本地化完整性检查）/ 辅助字号 / 无障碍审计 / 性能（含 211 条真机复核）
- ✅ **D5–D8 四决策**
- ✅ **P4 评估** + **P4-1 七步**（`CalendarMonthView` 592 → 358 行，每步两通道）
- ✅ **P4-2 第一步**（`AIAssistantView` 657 → 513 行）
- ✅ **五通道**：本会话由 Agent 自跑多次，含 iPhone 与 iPad

## 附：P4-2 ② 的第一块尝试（2026-10-04，**未落地，但拿到了正确的设计**）

按"最小自包含"原则先挑 `body` 第 42 行那块动手（内联提示区，24 行）。**结果抓错了单元**：

- 它不是单个 `if let X`，而是一条链：
  `if let inlineError { … } else if let completedMessage { … }`，
  而且链内还引用 `completedOffDay`——**三个状态共同构成一个单元**；
- 花括号配对只取到第一支，抽出来的文件语法就坏了。

**处理**：立即回退（连新文件一起删掉），构建恢复绿树，**不留半成品**。

**这次尝试换来的设计信息（下轮直接用）**：
1. 该块的抽取单元是**整条 if/else-if 链**，不是单个分支；
2. 三条分支都由"上一次操作的结果"驱动（错误 / 成功+休息日 / 无）→
   干净的接口是**传一个小枚举**而不是三个可选值：
   `enum AIInlineNoticeState { case error(String), success(String, offDay: Date?), none }`
   （父视图把三个 `@State` 映射成一个 state，子视图只做渲染）；
3. **教训**：`body` 里相邻的 `if let` 可能是同一条链——动手前先看有没有 `else if`
   （只看块起始行会漏掉）。

## P0' · 真机回归（2026-10-04 新增，最高优先级）

- [x] **主页上下无法滑动** —— **已修（628123c），待真机确认**
  - 根因：P4-1 抽取时把横滑 `DragGesture` 从"月列内部的网格 ZStack"**上移到整列**，
    而这一列正是 `ScrollView` 的直接子视图 → 手势抢走纵向拖动。
    （手势内的方向判定 `abs(dx) > 1.5*abs(dy)` 只决定是否进入跟手态，不阻止手势仲裁。）
  - 修法：手势移回列内部的网格区；并顺带把 `swipeMonthGesture` 归属到 `CalendarMonthColumn`
    （翻页写月份/选中日属父视图数据态 → 走 `onCommitMonth` 回调，列仍不持有状态）。
  - 连带发现：第一版替换把旧挂载点删掉却没挂回去 → **"横滑翻月"一度完全失效**，
    构建与单测都发现不了 ✗。

- [ ] **补两条回归守卫（本次回归之所以溜过去的直接原因）**
  - **① 主页可纵向滑动**：要"种子 N 条日程"让内容超过一屏，再 `swipeUp()` 并断言
    某个锚点（如月历标题 `选择月份或年份`）的 `frame.minY` **明显上移**。
  - [x] **② 横滑可翻月** —— **已补并已证伪**（`testFlow17_monthGridSwipeTurnsTheMonth`，532bc6e）
    - 断言：用 `^[0-9]+月$` 精确定位月份标题（排除"10月1日"与农历"八月"），`swipeLeft()` 后必须变化；
    - **证伪过程抓到一条"假守卫"**：第一版比较"整页文案"→ 把手势摘掉后**依然通过** ✗
      （任何无关变化都满足它）；收窄到月份标题后 → 手势在：通过 ✓；手势摘掉：失败 ✓
      （报 `["10月"] == ["10月"]`）。**没有这一步，我会交付一条给假信心的测试。**
  - ⚠️ **为什么现有用例抓不到**：UI 用例统一带 `-uitest-empty-store` 启动（`launchApp` 第 78 行），
    主页**没有日程** → 内容不足一屏 → 纵向压根不需要滚动；而横滑翻月**从来没有用例**。
  - 🔍 **先取"便宜信号"（一次诊断运行，89 秒）——结论被推翻，拿到硬数据**：

    ```
    屏幕 = 402 × 874
    scrollViews = 1，frame = (0,0,402,874)      ← ScrollView 存在且铺满屏幕
    文字最低点(before) = 2432.7pt               ← 内容高度 ≫ 视口高度 ✗
    文字最低点(after)  = 2432.7pt               ← 拖动后纹丝不动 ✗
    title.minY: 124.0 → 124.0
    ```

  - **修正结论**：**不是"内容不过一屏"**（我此前两次这样判断，都错 ✗）。
    真实情况是：**内容高约 2432pt、远超 874pt 视口，却完全不滚**。
    三种起滑点（全屏 `swipeUp()` / 日卡片区 / 屏幕下半部空白区）全部无效；
    而**同一个 ScrollView 上"横滑翻月"有效**（Flow17 两形态通过）→ 拖动**能被送达** ✓，
    只是没能让它纵向滚动。
  - ⚠️ **尚未定论的是原因**：沿途手势（网格的横滑 `DragGesture`、日卡片的
    `pressableFeedback()`）是否消费了纵向拖动，还是该 ScrollView 在此布局下本就不可滚。
    这需要**产品层面的确认**（真机/模拟器手工拖一次），**不是靠继续换拖法能定的**。
  - ✅ **元教训（比守卫本身值钱）**：**先用一次诊断拿硬数据，不要连续盲试**。
    五次盲试 ≈30 分钟运行时（其中两次撞上 600s 诊断超时）；
    一次诊断 **89 秒** 就推翻了其中的推断。诊断写到**断言消息**里，失败信息必然出现在工具解析的输出中。
  - 真机缺陷本身**已修复并经用户确认**（`628123c`），故本条在此之前不再投入。
  - 已撤回 `-uitest-seed-events`（无消费者即为死代码，不留）。

- [ ] **顺手排查同类风险**：本次是"手势/修饰符被上移一层"导致的回归。
  其余抽取（`CalendarMonthGridShell` / `CalendarMonthHeader` / `CalendarSolarTermBar` 等）
  是否有**同样被改变了作用域**的修饰符（如 `.padding` / `.contentShape` / `keyboardShortcut`）？
  做法：对这几次抽取逐个 `git show` 对比"修饰符挂在哪一层"。

## P5 · 文本规范化（2026-10-05）

审计范围：4 个语言文件各 484 条 + 全部调用点。

**结构类（真 bug）——零**：0 缺译、0 占位符数量不匹配（P3-3 的成果）；
仅有的 2 处「半角逗号」是 CSV 表头（故意用逗号分隔，保留）。

**已修**：
- ✅ **术语统一：「事件」→「日程」**（8 条 + 1 处措辞不严谨处，`e0acd05`）
- ✅ 一处表述不严谨：`这一天没有匹配到%@相关的日程。` → `这一天没有与 %@ 相关的日程。`（4 语言同步）

**刻意不改（附理由，避免以后反复讨论）**：
- 「通知」vs「提醒」：系统权限/通知通道 vs reminder，是两个概念；
- 「确定要删除…吗？」vs「确认创建」：疑问句 vs 动作，都对；
- 人称用「你」不用「您」：与苹果中文习惯一致，且全文已一致（您 0 / 你 2）；
- 标签/状态串不加句末句号：符合中文 UI 惯例（不是漏句号）；
- 「规划一下明天的安排」保留口语化：它是**输入示例**，就该像用户会说的话。

**新发现（未处理，需一次 zh-Hant 专项）**：
- zh-Hant 同时出现**「行程」与「日程」**（`grep -c` 见下方输出）。台湾习惯用「行程」
  （苹果 zh-Hant 日历即用「行程」），所以我上一轮把 zh-Hant 的「事件」改成「日程」，
  严格说应改成「行程」——需要一次**只针对 zh-Hant 的用词统一**，别顺手改日文/英文。

## P6 · 设置页专项（2026-10-05）

审计范围：设置相关 7 个文件（SettingsView / SettingsDataSections / SettingsAppearanceSections /
SettingsSyncSections / SettingsViewComponents / CalendarDisplaySettingsView / AboutSectionView），
130 余条可见文案。

### ✅ 已修（文案，4 语言同步，`423d639`）

| 类别 | 问题 | 修法 |
|---|---|---|
| **实现细节泄漏**（最严重，4 语言都漏）| `按 updatedAt 谁更新就用谁` / `同 id 的外部数据一律跳过` / `同 id 一律用导入版本覆盖` | 改成用户能读懂的说法：`比较最后修改时间，以较新者为准` / `导入文件中的同一条日程一律跳过（保留手机上的版本）` / `导入文件中的同一条日程覆盖手机上的版本` |
| **中文界面夹英文且未本地化** | 关于页 `Version \(appVersionString)` | → `版本 \(…)`，新增 key `版本 %@`（en=Version %@、ja=バージョン %@）|
| **英文 App 名未本地化** | `选完策略后会打开 Files 选择文件。` | → 打开「文件」App（zh-Hant 用「檔案」）|
| **术语漏网** | `确认清空全部事件？` | → `确认清空全部日程？`（上一轮统一时漏掉的一条）|
| **机器用词** | `重新调度所有提醒` | → `重新安排所有提醒` |

### 布局/排版审计结论（未发现问题，因此没有为"有改动"而改）

- 分区结构一致：`Section { } header: { } footer: { }` 普遍使用（外观分区无 footer 属合理——开关自明）；
- **两个危险操作**（清空全部日程 / 删除所有数据）均标 `role: .destructive` ✓；
- 导入 / 导出走 `confirmationDialog` ✓（含格式选择与说明），没有静默的危险操作。

### ✅ 行图标完整性：审计后确认**无需改动**（2026-10-05）

用多行感知的方式逐行核对行动行（`NavigationLink` / `Button` / `Toggle` / `Label`）是否带图标，
**40 处带图标、14 处不带**，逐一解释后结论是**本来就一致**：

- 带图标的是**列表行动行**（导入 / 导出 / 通知 / 时间胶囊 / 删除所有数据 / 关于 4 项…）✓
- 不带图标的是两类，都**符合 iOS 惯例**：
  1. **对话框 / 菜单里的按钮**（导出格式、冲突策略、清空确认的「取消」等）——系统对话框按钮不带列表图标 ✓
  2. **键值信息行**（同步状态 / 最近同步 / 版本 / 统计数字）——iOS 设置里这类行本就不带图标 ✓

⚠️ **过程记录（两次假阳性）**：第一次用**行内检测**，把 `} icon: { Image(systemName:) }`
写在后续行的 `NavigationLink`/`Label` 判成"无图标" ✗；第二次把窗口放到 8 行仍不够 ✗；
第三次用 20 行窗口 + 区分对话框上下文才得出可信结论。
**教训**：判断"有没有图标"必须按语句块而不是按行，且要先排除对话框/菜单上下文。
**结论：这一项不需要改动**——不为"有改动"而改。

### 🚩 待办（前述）

- [x] **zh-Hant 用词专项** —— **已完成（2026-10-05）**
  - 实测：值含「行程」**29** 处 vs 值含「日程」**15** 处（其中多数是本会话早前把「事件」改成「日程」时引入的）；
  - 台湾习惯（苹果 zh-Hant 日历即用「行程」）→ 15 处值统一为「行程」；
  - ⚠️ **只改值、绝不动 key**：key 必须恒为 zh-Hans 源文案（本次键含「日程」的 **39** 条保持不变，
    脚本里专门断言了这一点 —— 否则 key 一改，四个语言的表就对不上了）；
  - 验证：结构校验（键未被改动、剩余值含「日程」= 0）+ 本地化守卫 **436 用例 0 失败**。
  - 📌 **未做**：zh-Hant 的 UI 渲染复跑。UI 套件固定跑 zh-Hans（`SHOTS_LANG` 只被截图巡游用），
    而 `xcode_build` 工具无法传环境变量；如需真跑，用 `SHOTS_LANG=zh-Hant` 手工调 xcodebuild。

### ✅ testFlow17 的 iPad 版：已用「网格内锚点」解决（2026-10-05）

**问题**：iPad 是分栏布局，`app.swipeLeft()` 按**全屏坐标**横滑，落点在侧栏/中列边界 →
月份不变（不是功能坏，是**测试落点不对**）。

**解法**（不猜坐标）：滑动**起点**取自**网格内的日期数字元素**（`^([1-9]|[12][0-9]|3[01])$`
的 staticText），用 `element.coordinate(withNormalizedOffset:)` 把起点钉在网格里；
**终点**再 `withOffset(dx: -260)` 越出格子，凑出足够长的横拖（翻页阈值 = 列宽 22%）。
这样 iPhone 全屏与 iPad 中列**同一套代码都成立**，`XCTSkipUnless(phone)` 已移除。

**两形态实测**：iPad ✓（锚点命中日期格 `"5"`）、iPhone ✓（锚点命中 `"6"`）——
锚点随当月日期变化，但都落在网格内，这正是"不猜坐标"的好处。

**证伪仍然有效**：断言（月份标题必须变化）未变，此前已用"摘掉手势挂载 → 失败"证伪过；
本次只改了**滑动方式**、未改断言，因此不需要重新证伪。

#### P1-2 结案证据（诊断式回传，两形态对照）

用 `XCTSkip` 消息回传"点击标题前后的按钮集合差"（跳过不会触发失败后的 600s 诊断收集超时，
一次 40 秒；此前用 `XCTFail` 每次要 ~11 分钟）：

| 形态 | 点击后新增按钮 |
|---|---|
| **iPhone** | 表单控制柄 · 取消 · 跳转 · 年/月/日轮盘 · 回到今天 · 半年后 · 一年后 · **全年视图** · 重试 |
| **iPad** | 表单控制柄 · 取消 · 跳转 · 6日 廿八 · 7日 廿九 · 年/月/日轮盘 · 回到今天 · 半年后 · 一年后 · 重试 |

**结论**：①「跳转到日期」面板在 **iPad 上本来就会打开**（新增 13–20 个元素）——
此前"面板未被呈现"的猜测被证伪；②「全年视图」是 **iPhone 专属入口**，iPad 上不存在。
已转为永久用例 `testFlow19_dateJumpPanelOpensAndYearEntryIsIPhoneOnly`：
两形态都断言"面板打开 + 出现「跳转」"，iPhone 额外断言「全年视图」，
iPad 则**断言其不存在**（若将来补上会红，提醒改断言而不是当成 bug 悄悄放过）。

剩余可选追问：`全年视图` 这个 key 只在 4 个 `.strings` 与两处注释里出现，**Swift 视图代码里没有**
——说明 iPhone 侧那个入口的标题来自别的构造方式（或该 key 已成孤儿）。这不影响结论，
若要清理孤儿 key，可先 grep「半年后」定位快捷跳转列表。

#### 元技巧：诊断用 `XCTSkip` 消息回传，不要用 `XCTFail`

失败的用例会触发 Xcode 的**诊断收集**，本项目两次实测都撞上 **600 秒超时**（单次 11 分钟 ✗）；
而**跳过的用例不会**，消息照样出现在工具解析的输出里（40–50 秒 ✓）。
诊断期一律用 `throw XCTSkip(诊断内容)`。

## P7 · 日历选择框与长按弹出（2026-10-05）

### ✅ 已做：选中框过渡动画（`CalendarComponents.dayCellBackground`）

**问题**：选中日切换时，实心填充／白描边／阴影是**硬切**（无过渡），选中态切换显得生硬。

**改法**（作用域严格限定在背景层，不动文字与布局）：
- 填充层加 `.animation(.snappy(duration: 0.22, extraBounce: 0.06), value: fillTint)`；
- 今日红色描边用**同一节奏**（`.animation(…, value: isToday)`），避免"选中 ↔ 今日"两态切换时节奏不一致。

**验证**：构建 ✓（4 条警告全为 SwiftPM 缓存环境噪声，代码零警告）+ 436 用例 0 失败 +
iPhone UI **22 条（4 skip）0 失败**。

### ❌ 试过并回退：按住"按下反馈"用 `Button` + `ButtonStyle` —— **与网格横滑不共存**

**做法**：把日期格的 `.onTapGesture` 换成 `Button { onSelectDay(d) } label: { <格子> }`
+ 自定义 `DayCellPressStyle`（`isPressed` 时缩放 0.96 / 透明度 0.88）——
这是"不叠自定义手势"的标准写法，理论上能兼顾按下反馈与 `contextMenu`。

**结果：横滑翻月被彻底破坏** ✗✗。iPhone UI 全套里
`testFlow17_monthGridSwipeTurnsTheMonth` **立刻变红**（"10月" → "10月"，月份不再变化）：
`Button` 会**吞掉横向拖动**，于是拖动再也到不了网格上的
`.simultaneousGesture(swipeMonthGesture(...))`。

**处理**：回退格子结构与那个 `ButtonStyle`（无消费者即为死代码，一并删除），
只保留选中框过渡动画。回退后 Flow17 复跑 **12 秒通过** ✓。

**结论（写下来避免重复试）**：**日期格不能是 `Button`，也不能叠任何会消费拖动的控件/手势** ——
这是"格子上要能横滑翻月"的先决条件。若要给按住加反馈，只剩两条路，都有代价：
1. **UIKit 长按识别器**（`cancelsTouchesInView = false`，像本仓 `TapOutsideKeyboardDismisser` 那样），
   可与拖动共存，但属重量级改动，且必须在真机上验证手感；
2. **不做** —— 系统长按本身已有高亮 + 菜单弹出动画，收益有限。

**建议**：除非明确要求，**不做**。本轮已交付的选中框过渡动画是这部分里收益/风险比最好的一项。

> 🛡️ 顺带记一功：这次功能性回归**是几小时前刚建好的 Flow17 守卫当场拦下的**。
> 它建好后第一次真正发挥作用，拦下的正是"改了别处、把横滑悄悄弄坏"这类最难自查的问题。

### ✅ 已交付：按压曲线调校（`AppTheme.Motion.pressInOut`）

用户反馈"按住弹跳不够丝滑"，查因发现曲线本身就不适合"按下"：

```swift
// 旧：response 0.22（对按下偏慢）+ dampingFraction 0.72（明显过冲）→ 手感"先慢后晃"
.spring(response: 0.22, dampingFraction: 0.72, blendDuration: 0.15)
// 新：按下立刻跟手、松开干脆、几乎无可见过冲（iOS 17+ 原生控件即此节奏）
.snappy(duration: 0.15, extraBounce: 0.02)
```

影响面：所有用 `pressableFeedback()` 的控件（月历工具栏、菜单、设置页按钮等）**统一变脆**。
验证：构建 ✓ 436 用例 ✓ Flow1（点按选中）11s 通过 ✓ Flow17（横滑翻月）12s 通过 ✓。

### ❌ 日期格本身的"按下反馈"：两条路都被实测否掉（重要约束）

要让**日期格自己**在按下时给反馈，试了两条标准路，各破坏一个功能：

| 试法 | 结果 |
|---|---|
| `Button { } label: { 格子 }` + `ButtonStyle` | ❌ **吞掉横向拖动** → 横滑翻月失效（Flow17 红）|
| `.pressableFeedback()`（内部 `DragGesture(minimumDistance: 0)`）| ❌ **吞掉 tap** → 点击不再选中（Flow1 红）|

**结论**：日期格必须同时容纳「点按选中」与「网格横滑翻月」，两者都依赖触摸直通 →
**这一格是手势真空区**：既不能是 `Button`，也不能叠任何手势。已把这条约束**写进代码注释**
（`CalendarMonthGridShell.swift` 的格子处），避免后来者再踩。

**唯一剩下的路**（未做，需要单独一轮 + 真机验证手感）：
**UIKit 长按识别器**（`cancelsTouchesInView = false`）——本仓 `TapOutsideKeyboardDismisser`
已是这个模式，可以与拖动/点按共存。

**给用户的实话**：日期格上"按住"看到的弹跳，**来自系统上下文菜单自身的抬升动画**（App 无法直接调）✗；
本次能调的是 App 内所有 `pressableFeedback()` 控件的按压手感 ✓（已调脆）。
若仍希望日期格按下时有下沉反馈，需走上面那条 UIKit 路线。

### ✅ 已修：长按抬起时"圆角跳一下"（2026-10-05）

**成因**：格子自身的选中框圆角是 `isRegular ? 14 : 10`，而长按抬起时**系统按自己的圆角**
裁切预览 ✗ → 抬起瞬间圆角变化，看起来"跳一下"。

**修法**（不动任何手势，因此没有前两轮那种破坏风险）：
1. 圆角抽成**单一来源** `DayCellView.selectionRadius(regular:)`，格子背景与抬起预览**同一处取值**
   —— 这从根上保证两者不会再各自漂移；
2. 用 `.contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: …))` 让抬起预览按格子圆角裁切。
   该 kind **只影响抬起预览的形状**，不参与命中测试、不注册手势。

**macOS 坑**：`.contextMenuPreview` **在 macOS 不可用**（本包同时为 macOS 宿主构建）✗ ——
故封装为平台自适应 `ViewModifier`（`ContextMenuPreviewShape`），非 UIKit 平台空操作。

**验证**：构建 ✓ 436 用例 ✓；**点按与横滑均未被影响**——Flow1（点按选中）10s ✓、
Flow17（横滑翻月）12s ✓。
⚠️ 圆角一致性是**视觉属性**，UI 用例断言不了，最终仍需真机/模拟器肉眼确认；
但"单一来源 + 预览形状显式指定"已消除两个常量各自漂移的可能。

### ✅ 已修：回弹时"字扭曲变形"（2026-10-05）——根因是低阻尼弹簧

**根因**：日期格上挂的是内联弹簧

```swift
.animation(.spring(response: 0.34, dampingFraction: 0.52, blendDuration: 0.12), value: isSelected)
//                                   ↑ 0.52 = 阻尼极低
```

`.scaleEffect(isSelected ? 1.05 : 1.0)` 作用于**整格（含文字）**，而 damping 0.52 会让它
**来回振荡多次** ✗；格子里的文字带 `.lineLimit(1).minimumScaleFactor(0.6)`，
每次振荡都要重新适配 → 视觉上就是"字扭曲变形"。

**修法**：新增单一来源 `AppTheme.Motion.selection = .spring(response: 0.28, dampingFraction: 0.82, …)`
——保留"一次轻微过冲"的物理感，但**不再来回抖** ✗→✓。格子改用该曲线。

**同类问题清扫**：repr 全仓 grep `dampingFraction: 0.[0-6]` → **已无其它低阻尼弹簧** ✓
（另一处是上一轮修的 `pressInOut` 0.72 → snappy ✓）。这两处是同一类病：**弹簧过冲**。

### ⚠️ 同时回退了我上一轮的"圆角对齐"改动（我认这个错）

上一轮为对齐长按抬起预览的圆角，加了 `.contentShape(.contextMenuPreview, …)` ——
但它会让系统**按遮罩位图化**预览，回弹时文字被重采样，正是"字扭曲变形"的另一个来源 ✗。
**我用一个更明显的视觉问题换掉了一个很小的圆角差异** ✗ → 已回退（含删除无消费者的
`ContextMenuPreviewShape`）。

**因此圆角差异又回来了** ✗（这是现状，如实说明）。建议**就此接受**：
抬起过程只有 ~0.3 秒，少量圆角差异远不如文字扭曲显眼；若确实要治，只剩
"自定义 `preview:` 真实视图"（跳过位图遮罩，但 API 已废弃、风险高）一条路。

---

# 方案 1 施工图：自绘长按菜单（长按"文字变形 + 圆角不一致"的彻底解）

> 状态：**设计完成、组件代码已验证可编译，尚未接线**。
> 2026-10-05 一次尝试中，组件本身编译通过（0 错误），但接线脚本出错把
> `CalendarMonthGridShell.swift` 截断，已立即恢复、未留半成品。
> ⚠️ **不要在余量不足一轮时动它**——这是一次功能级改动（多文件接线 + 两条 UI 通道 + 无障碍降级）。

## 一、结论（先看这条）

两个症状**同源**：系统 `.contextMenu` 会对格子做**位图快照**，回落时缩放这张位图。

| 症状 | 机制 |
|---|---|
| 回落一瞬间"字扭曲变形" | 快照是位图 → 回落弹簧缩放它 → 文字被重采样 |
| 格子圆角不一致很突兀 | 抬起预览/高亮盘的圆角**由系统决定**，与格子 `RoundedRectangle(10/14)` 无关 |

**因此：只要还用系统 `.contextMenu`，这两件事都消不掉** ✗ —— 自绘菜单是唯一彻底解。

**两条已实测否掉的死路**（有守卫证据，别再试）：
- 格子改 `Button` + `ButtonStyle` → **吞掉横向拖动** → 横滑翻月失效（`testFlow17` 当场变红）；
- 格子加 `.pressableFeedback()`（内部 `DragGesture`）→ **吞掉 tap** → 点击不再选中（`testFlow1` 变红）。
- 另：`.contentShape(.contextMenuPreview, …)` 能对齐圆角，但**强制位图遮罩** → 放大文字变形（已回退）。

## 二、组件（已编译验证 ✓，可直接落盘为 `DayCellLongPressCatcher.swift`）

```swift
import SwiftUI

#if canImport(UIKit)
import UIKit

/// 日期格上的 UIKit 长按识别器。
/// `cancelsTouchesInView = false` + 并行识别：点按（选中）与拖动（横滑翻月）都不受影响。
/// 这是两条 SwiftUI 路被实测否掉后唯一剩下的做法。
struct DayCellLongPressCatcher: UIViewRepresentable {
    var onLongPress: () -> Void
    var onRelease: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let press = UILongPressGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handle(_:)))
        press.minimumPressDuration = 0.32
        press.cancelsTouchesInView = false          // 关键
        press.delegate = context.coordinator
        view.addGestureRecognizer(press)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private let parent: DayCellLongPressCatcher
        init(_ parent: DayCellLongPressCatcher) { self.parent = parent }

        @objc func handle(_ gesture: UILongPressGestureRecognizer) {
            switch gesture.state {
            case .began: parent.onLongPress()
            case .ended, .cancelled, .failed: parent.onRelease()
            default: break
            }
        }

        func gestureRecognizer(_ gesture: UIGestureRecognizer,
                              shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
#endif
```

## 三、接线方式（本轮想清楚的关键点）

1. **命名坐标空间**：在 `CalendarMonthGridShell` 的 `LazyVGrid` 上加
   `.coordinateSpace(name: "monthGrid")`；
2. **每格取锚点**（不要用屏幕坐标，分栏/横屏下会错）：
   ```swift
   .overlay {
       GeometryReader { geo in
           DayCellLongPressCatcher(
               onLongPress: { pressedCell = PressedCell(date: d,
                                                        frame: geo.frame(in: .named("monthGrid"))) },
               onRelease: { pressedCell = nil })
       }
   }
   ```
   （`PressedCell` = `{ let date: Date; let frame: CGRect }`，`@State private var pressedCell: PressedCell?`）
3. **浮层**挂在同一层：`.overlay(alignment: .topLeading) { if let c = pressedCell { menu(c) } }`，
   用 `.offset(x: c.frame.minX, y: c.frame.maxY + 6)` 定位；
4. **浮层内容**：圆角取 `DayCellView.selectionRadius(regular:)`（单一来源 ✓）、
   动画取 `AppTheme.Motion.selection`（单一来源 ✓）、三项操作 = 选中此日 / 新建日程 / 复制日期
   （与原系统菜单一致），背后放一层 `Color.clear.contentShape(Rectangle()).onTapGesture { pressedCell = nil }`
   点击外部关闭；切月/滚动时也置 nil；
5. **无障碍降级（已确认保留）**：`UIAccessibility.isVoiceOverRunning` 为真时**改挂系统 `.contextMenu`**
   （VoiceOver 用户仍可完整操作；视觉变形对他们无影响），普通用户走自绘 ✓。

## 四、验收清单

- 构建 0 警告 + 436 用例 0 失败；
- **`testFlow1`（点按选中）与 `testFlow17`（横滑翻月）必须仍通过** ← 这两条是本方案的"不许破坏"红线；
- **新增一条长按守卫**：XCUITest 用 `element.press(forDuration: 1.2)` 触发长按 → 断言自绘菜单的三个操作出现
  （`press(forDuration:)` 原生支持长按 ✓）；
- 真机确认：① 回落不再出现文字变形；② 浮层圆角与格子协调。

## 方案 1 施工图 · 补遗（2026-10-05 第二次尝试所得）

### A. 逐字锚点（上次卡住的地方，务必用这些原文替换）

`CalendarMonthGridShell.swift` 里日期格的真实片段（行号随改动浮动，内容逐字如下）：

```swift
                        .onTapGesture {
                            onSelectDay(d)
                        }
                        // ⚠️ 此处**不要**加 `Button` 或 `pressableFeedback()`（或任何手势）：
                        // 2026-10-05 两次实测——改 Button 会吞掉横向拖动（Flow17 红：横滑翻月失效）；
                        // 加 pressableFeedback（内部 DragGesture）会吞掉 tap（Flow1 红：点击不再选中）。
                        // 日期格必须同时容纳「点按选中」与「网格横滑翻月」，两者都靠触摸直通，
                        // 因此这一格是**手势真空区**。要加按下反馈只能走 UIKit 长按识别器
                        // （cancelsTouchesInView = false，像 TapOutsideKeyboardDismisser 那样）。
                        // 原生上下文菜单：长按日期格 → 快捷操作（原创，克制不加额外功能）
                        .contextMenu {
```

⚠️ 注意：`.contentShape(Rectangle())` 与 `.onTapGesture` 之间**还有一条注释**
（关于 `.contentShape(.contextMenuPreview, …)` 的那条），锚点别漏了它。

### B. 浮层与降级（已写好、本轮未落地，下一轮直接抄）

```swift
/// 自绘长按菜单：圆角与格子同源，动画走 AppTheme.Motion，
/// **不做位图快照** → 回落时文字不会被重采样（这正是方案 1 要解决的）。
private struct DayCellLongPressMenu: View {
    let radius: CGFloat
    let onSelect: () -> Void
    let onNew: () -> Void
    let onCopy: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            item("选中此日", "checkmark.circle", onSelect); Divider()
            item("新建日程", "plus.circle", onNew);        Divider()
            item("复制日期", "doc.on.doc", onCopy)
        }
        .frame(minWidth: 168)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: radius, style: .continuous)
            .stroke(Color.themeSeparator.opacity(0.25), lineWidth: AppTheme.Stroke.hair) }
        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
        .transition(.scale(scale: 0.92, anchor: .topLeading).combined(with: .opacity))
        .animation(AppTheme.Motion.selection, value: true)
    }
    // item(_:_:_:) 用 Button + .plain + .pressableFeedback()，行高 ≥ AppTheme.Touch.minTarget
}

/// 系统上下文菜单，**仅在 VoiceOver 运行时**挂载（无障碍降级）。
private struct SystemMenuForVoiceOver: ViewModifier {
    let onSelect: () -> Void; let onNew: () -> Void; let onCopy: () -> Void
    func body(content: Content) -> some View {
        #if canImport(UIKit)
        if UIAccessibility.isVoiceOverRunning {
            content.contextMenu {
                Button { onSelect() } label: { Label("选中此日", systemImage: "checkmark.circle") }
                Button { onNew() }    label: { Label("新建日程", systemImage: "plus.circle") }
                Button { onCopy() }   label: { Label("复制日期", systemImage: "doc.on.doc") }
            }
        } else { content }
        #else
        content
        #endif
    }
}
```

### C. 已知的**唯一剩余难点**（本轮就栽在这里）

给 `LazyVGrid` 挂 `.coordinateSpace(name: "monthGrid")` + `.overlay(alignment: .topLeading) { … }` 时，
**用花括号配对找 `LazyVGrid` 的结束位置会找错层**（本轮因此产出 `expected declaration` +
`extraneous '}'`，构建失败，已立即回退）。下一轮的做法：**先读那 15 行、人工确认插入点**，
不要用脚本配对；或者干脆把浮层挂到 `CalendarMonthColumn` 的根上（那里是明确的单层容器）。
