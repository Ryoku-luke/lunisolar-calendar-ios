# 项目进度与剩余改进分析（对照四份规划文档）

> 基线：代码 HEAD `1a9f917`（2026-09-25），309 条 SPM 单元测试全绿；对照文档：
> 《VibeCoding 总方案 2026-09-22》《UI 整体界面打磨总报告 2026-09-22》《开发路线图》
> 《项目进度清单 2026-09-23》。
>
> 这份文档与那四份的区别：**每一条都回到代码里核对过**，并给出证据（文件 / 行数 / grep 结果）。
> 文档里标注为「未完成」的项目，有些其实已经做完；有些文档假设存在的东西，实际并不存在。

## 0. 三条最重要的结论

1. **架构 P0 基本完成，产品级验收一条都还没做。** 五个协调器全部落地、View 不再直接碰
   ActivityKit/CloudKit/通知；但两份文档的验收标准（总方案 §72 的 23 项勾选表、
   UI 报告 §61 的四组完成定义、§55 的五条真实用户路径）**全部是人工检查，且从未执行过**。
2. **没有任何自动化手段能验证界面行为。** Xcode 工程只有 2 个 target（App + Widget）——
   **连单元测试 target 都没有**（单测走 SPM），更没有 UI 测试 target。
   `UITests/LunisolarCalendarUITests.swift` 是**孤儿文件，从未被编译过**，
   而总方案 §48 却写着「现存 3 条冒烟测试」。这是当前最大的结构性缺口。
3. **两份文档之间有一处直接冲突，代码已经选了其中一边**，需要你裁决（见 §4-A）。

## 1. 逐项核对：架构层（总方案 P0 / 路线图 PR1–3）

| 条目 | 状态 | 证据 |
|---|---|---|
| AppLifecycleCoordinator | 已完成 | `Sources/LunisolarCalendarApp/App/AppLifecycleCoordinator.swift` |
| NavigationCoordinator（统一导航状态） | 已完成 | `App/NavigationCoordinator.swift`：selectedDate / phoneTab / iPadSection / pendingOpenEventID / pendingOpenCountdownID |
| DeepLinkRouter（统一 `qinghe://`） | 已完成 | `App/DeepLinkRouter.swift`：calendar、calendar/date、event、countdown、ai 五条路由齐全；scheme 已注册 |
| View→Store 写入收口 | 已完成 | 收口到 `Services/EventService.swift`；SettingsView / CountdownView 的 delete、flush 已改走 Service |
| TimeCapsuleCoordinator | 已完成 | `Services/TimeCapsuleCoordinator.swift` |
| Package resource warning | 已完成 | 已清理；本轮改全天事件时新增的 `Models/CalendarDayKey.swift` 也补了 LunarCore 的 exclude |
| AppRootView 不再知道 ActivityKit/CloudKit/通知重排 | 已完成 | `App/LunisolarCalendarApp.swift:14-17` 明文声明，且该文件确已无 `import ActivityKit` |
| 统一 App State 含 `selectedEventID` / `presentedRoute` | 部分 | 有等价物 `pendingOpenEventID` / `pendingOpenCountdownID`；但没有统一的 `presentedRoute`（路由仍是若干布尔 + sheet 组合） |
| `CalendarDaySummary` + `CurrentDateContext`（§5-P0） | 未做 | **全仓不存在此类型**。各页仍自行调用 `HuangliGenerator.generate` / `SolarTermProvider` / 天气等派生数据（如 `SelectedDayCardView.swift:14`、`DayDetailView.swift:78,187`、`CalendarMonthView.swift:582`） |

> 这条是唯一「文档标 P0、实际未做」的条目。它被路线图排进了 PR3，而 PR1/PR2 已做，所以它只是被跳过了。

## 2. 逐项核对：UI 层（UI 报告 P0 / 路线图 P1）

| 条目 | 状态 | 证据 |
|---|---|---|
| UI-P0-3 主日历移除 AI Banner | 已完成 | 全仓已无 `aiAssistantBanner` / `QinghePhoneAIChip` |
| UI-P0-4 收敛 Card primitive | 已完成（基本） | `AppTheme.swift` 里 modernCard / liquidCard / pageBackground 已为 0 处；仅剩 glassCard×1、softChipBackground×2 |
| UI-P0-1 拆分 CalendarMonthView | 未做 | `Views/CalendarMonthView.swift` 仍有 **725 行 / 36.6 KB** |
| UI-P0-5 拆分 SettingsView | 未做 | `Views/SettingsView.swift` **786 行**（文档记录的是 759 行——它变长了） |
| P1 统一 CalendarDaySummary | 未做 | 同 §1 末条 |
| P1 设计系统 Token 固定 | 部分 | `Support/AppTheme.swift` 存在；但文档要求「禁止 14/18/22/26/28/30 圆角随意出现」，未逐处核对 |
| P1 iPad responsive layout | 部分 | `AdaptiveRootView` 按 sizeClass 分流；列宽用 `navigationSplitViewColumnWidth(min:ideal:max:)`，但**未按 11 英寸 / 13 英寸 分别设定**（UI 报告 §37 要求 220/520/320 与 240/640/380） |
| P1 UI Test 补 7 条路径 | 未做 | 见 §3 —— 连 target 都没有 |
| 统一状态组件（UI 报告 §37/§50） | 未做 | `QingheLoadingView` / `QingheEmptyView` / `QingheErrorView` / `QingheToast` / `QingheConfirmation` **五个类型一个都不存在**。现状是各页直接用 `ProgressView` / `ContentUnavailableView` / `.alert`：功能有，但不统一 |
| 单一日期源（UI 报告 §45） | 已完成 | 黄历 Tab 与日历 Tab 共用 `NavigationCoordinator.selectedDate`；「月历选 20 日、黄历仍显示 19 日」这类问题已不存在 |
| iPhone 四 Tab（总方案 §63） | 已完成 | calendar / huangli / ai / me |
| iPad Sidebar 分组（总方案 §15「主要/生活/工具/系统」） | 部分 | 现状是 5 项平铺（日历、年视图、全部日程、倒数日、设置），没有分组 |
| Reduce Motion 支持（UI 报告 §44 / 总方案 §47） | 未做 | 全仓 **0 处** `reduceMotion` / `accessibilityReduceMotion` 处理 |

## 3. 验证能力的真实现状（最关键的一节）

| 手段 | 现状 |
|---|---|
| SPM 单元测试 | 已完成 309 条，全绿。但**全部是逻辑层**：模型、协调器、解析器、同步 Mock。没有一条覆盖「界面呈现」 |
| Xcode 工程 target | **只有 `LunisolarCalendar` 与 `LunisolarWidget` 两个**（`xcodebuild -list` 实测）。没有单元测试 target，没有 UI 测试 target |
| UI 测试 | `UITests/LunisolarCalendarUITests.swift`（3 条）**不在任何 target 里，从未编译、从未运行**。README 里写的「新建 UI Testing Bundle target 并加入该文件」这一步从未执行 |
| CI | 无（`.github/workflows` 不存在）。推送不会触发任何构建 |
| 现有「验证」= | `swift build` + `swift test` + 两次编译（iOS 模拟器 / xcodebuild）。**都是编译级，零行为级** |

后果：两份文档里的验收标准——总方案 §72（23 项 UX 勾选表，全空）、§22（开关一致性）、
UI 报告 §54（9 Feature × 7 状态的成品矩阵）、§55（5 条真实用户路径）、§61（四组完成定义）——
**目前只能靠人工在真机上走**。这也解释了为什么本项目反复出现「代码全绿但真机行为和预期不符」。

## 4. 需要你裁决的三处

### A. iPad 右栏到底该显示什么（**两份文档互相矛盾**）

- 总方案 §18：竖屏优先 Sidebar+Content，**详情用 sheet**；
- UI 报告 §33/§36：右栏应是**上下文 Inspector**，随选中日期/事件/设置/倒数切换。
- 当前代码选的是**第三条路**：右栏在所有节下常驻 `DayDetailView`，
  理由写在 `App/LunisolarCalendarApp.swift:181-183` 的注释里（当初是为消除右栏大面积留白）。

三者不同，代码只实现了其中一种。文档里的 UI-P0-2、P1-3、§33–§38 全部悬在这上面，
**不定这个，「iPad 适配」这条线没法继续做。**

### B. 测试数量是否继续写死在 README

总方案 §49 明确要求「统一 README / CI / 测试统计，**此后不再手工写死测试数量**」。
现状是 README 写死「309 条」，而我在本次会话里因为新增测试已经手工改过 3 次
（294 → 298 → 308 → 309）。这正是文档要禁止的做法。

建议：README 里去掉具体数字，改成「见 `swift test` 输出」，或加一个统计脚本。
（我记得你更在意「数字要准」，所以这条需要你点头，我不擅自删。）

### C. 是否按文档重排目录

文档要求 `Application/`、`Features/`、`Domain/`、`Infrastructure/`、`DesignSystem/`；
现状是 `App/ Services/ Models/ Stores/ Sync/ Support/ Views/ Widgets/`。
**功能上等价**（同一个 Swift module，改名不动任何 import），但会改几十个路径，
收益只是「和文档一致」。我倾向于**不改名**，只在这里记录这个偏离——除非你有别的理由。

## 5. 四份文档本身已经过时的地方

《项目进度清单 2026-09-23》里标注未完成、但实际已完成的：

- 「GitHub 同步：最新节日图标修复尚未 push」→ 已推送，本地与远端 SHA 一致（35 个提交）。
- 「灵动岛宽度问题 需真机确认」→ 2026-09-25 真机复测通过；且本会话修掉了「灵动岛完全没出现」。
- 「多语言字符串走查：9 个 uiLabel + P2 文案未走 4 语言」→ 已完成，字符串表 199 → 476 条 × 4 语言。
- 「隐私清单 PrivacyInfo.xcprivacy」→ 已进 App 与 Widget 两个 target 的 resources。

仍然成立、且值得单独点出来的**一条真 bug**：

- 「天气定位失败兜底：硬编码北京坐标」**仍是现状** —— `Support/WeatherService.swift:224`
  在定位失败时用北京坐标，第 240 行再把城市名显示为「北京」。
  不在北京的用户会被**明确告知自己在北京市** —— 这比「不显示天气」更误导。
  更值得留意的是：紧邻的注释写着「用北京坐标兜底，天气仍可显示（**不伪造城市名**）」，
  与实际行为相反 —— 这类「注释声称 A、代码做 B」的地方，排查时最费时间。
  这是清单里少数「描述准确、且仍未修」的项，修起来也很小（改文案 + 决定降级口径）。

## 6. 剩余改进的建议顺序

按「投入产出比 × 是否解锁后续工作」排，不含已经在做的：

| 序 | 事项 | 为什么排这里 | 谁做 |
|---|---|---|---|
| 1 | **建 UI 测试 target + 补 5 条真实用户路径**（UI 报告 §55） | 唯一能把验证能力从「零行为级」提到「可重复」的动作。前面所有未完成项的验收都卡在这。target 要在 Xcode 里建（我无法可靠手改 pbxproj） | 你建 target，我写测试 |
| 2 | **修「定位失败显示北京」** | 真 bug、用户可见、改动极小 | 我 |
| 3 | **裁决 iPad 右栏语义**（§4-A） | 不裁决，「iPad 适配」整条线停摆 | 你 |
| 4 | **`CalendarDaySummary` 统一派生数据** | 文档标 P0、唯一被跳过的 P0；也是拆分巨型 View 的前置 | 我 |
| 5 | **统一状态组件**（Loading/Empty/Error/Toast/确认） | 文档两处都要求；补 UI 测试时正好需要它们做断言锚点 | 我 |
| 6 | **Reduce Motion** | 无障碍硬缺口，全仓 0 处理，改动小 | 我 |
| 7 | 拆分 SettingsView / CalendarMonthView | churn 大、收益偏维护性，且应在 4/5 之后做 | 我 |
| 8 | README 测试数去写死（§4-B） | 小事，但每次新增测试都要手工维护 | 你点头即可 |
| 9 | iPad Sidebar 分组、11 英寸 / 13 英寸列宽、`presentedRoute` 统一 | 依赖第 3 项的裁决 | 我 |
| 10 | App Store 上架材料（截图 4 语言、描述、TestFlight、性能测试） | 与代码无关，但上架前必须做 | 你 |

## 7. 与两份文档执行顺序的差异说明

路线图的 PR 顺序是「架构 → 服务 → Domain → Calendar → Settings → iPad → DeepLink → AI」。
实际已完成的部分与它一致（PR1/2/3 的架构侧、PR7/8 的 DeepLink 与 AI 都提前做了），
但**跳过了 PR3 的 `CalendarDaySummary`**，并且**始终没做 PR11 的 UI Test**。

我现在建议的顺序（§6）把「验证能力」提到了最前，理由是：这个项目已经出现过多次
「本机四通道全绿、真机行为不符」的情况（灵动岛、全天事件、AI 助手交互都属此类），
在没有行为级测试之前，后面每一步改动都只能靠人工回测兜底——而人工回测到目前为止
只做过灵动岛一节。
