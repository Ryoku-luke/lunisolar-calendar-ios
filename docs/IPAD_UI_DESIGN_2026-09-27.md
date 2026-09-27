# iPad 版 UI 改进优化设计文案（2026-09-27）

> 范围：仅 iPad / iPadOS（iPhone 适配不动）。基线：代码 HEAD 2026-09-27。
> 依据：`LunisolarCalendarApp.swift`（`iPadRootView` / `PhoneTabRootView`）、
> `CalendarMonthView.swift`（`isIPadSplit` 分支）、`YearOverviewView.swift`、
> `CountdownDetailView.swift`、`DayDetailView.swift`。
> 优先级：**P0 = 功能/布局硬伤，P1 = 体验打磨，P2 = 细节**。
> 配套总评审见 `UI_DESIGN_REVIEW_2026-09-27.md`（本文不重复通用项）。
> **施工进度**：批次 0（P1-3）、批次 1（P2-1）与批次 2（P0-4 第 2 条）
> **已完成 2026-09-27**，其余未动；
> **P0-1 已裁决走方案 C**，实施清单见文末。

## 0. 现状盘点

iPad 采用 `NavigationSplitView` 三栏：

- **侧栏**：5 节（日历 / 年视图 / 全部日程 / 倒数日 / 设置），宽度系统默认；
- **中栏**：随节切换，月历节限宽 340–480（ideal 390）；
- **右栏**：上下文 Inspector——日历/年视图节 = 选中日的 `DayDetailView`，
  倒数日节 = `CountdownDetailView`，全部日程/设置节隐藏（`columnVisibility = .doubleColumn`）。
- 尺寸为 compact 时（分屏、Slide Over）整体回退 iPhone 的 `PhoneTabRootView` TabBar。

**好的底子**：三栏上下文 Inspector 的裁决方向正确（对齐 Apple 系统设置）；
月历节在中栏正确隐藏了选中卡（避免与右栏重复）；限宽数值合理。

**iPad 版的核心矛盾**：大量视图是"为 iPhone 或 sheet 设计的"，直接塞进栏里，
出现套娃导航、死按钮、网格过挤、入口缺失四类硬伤。

---

## P0：功能 / 布局硬伤（4 项）

### P0-1 年视图在 iPad 是"sheet 视图塞进中栏"：套娃导航 + 死按钮 + 网格过挤

**问题**（三合一，同一根因）：

1. `YearOverviewView` 内部自带 `NavigationStack` + `.presentationDetents([.large])`
   + 右上角「完成」按钮调 `dismiss()`——它是**为 sheet 场景设计的**；
   而 `iPadRootView` 又在外面包了一层 `NavigationStack` 放进中栏
   （`NavigationStack { YearOverviewView(...) }`）→ **双层 NavigationStack 套娃**。
2. 在非 sheet 的栏上下文里 `dismiss()` 无 presentation 可解散 →
   **「完成」按钮在 iPad 上是死按钮**。
3. 网格是**写死 3 列**（`LazyVGrid(columns: ×3)`），在 390pt 中栏里每张迷你月卡
   只有 ~113pt 宽，单格 ~15pt，**远低于 44pt 触控标准**；而 12.9"/13" 寸屏幕的
   富余宽度完全没用上。

**建议方案**（推荐 A）：

- **A. iPad 改回 sheet 呈现**：`iPadRootView` 年视图节不再占中栏，
  改为侧栏选中「年视图」时在中栏保持月历、以 sheet 弹出年视图（复用现有
  presentationDetents，零改动视图本体）；中栏月历不中断上下文。
  这与「日期跳转」的模态心智一致。
- B. 视图参数化：加 `embedsInNavigationStack` / `isEmbedded` 参数
  （与 `DayDetailView` 同模式），嵌入时去掉内层 NavigationStack、
  隐藏「完成」、网格改 **按宽度自适应列数**（`GridItem(.adaptive(minimum: 220))`，
  iPad 中栏自然 1~2 列、若日后全宽布局则 3~4 列）。

**验收**：iPad 上年视图可正常关闭；双层 NavigationStack 消除（视图层级调试确认）；
迷你月格 ≥ 44pt（或确认走 `adaptive` 后实际宽度）；Flow 4 补年视图节断言。

### P0-2 iPad 中栏月卡下方大片空白，格子不随屏幕高度拉伸

**问题**：`CalendarMonthView` 在 `!isIPadSplit` 时才渲染 `SelectedDayCardView`
——iPad 中栏月卡以下**完全空白**。iPad 屏幕高度 800~1000+pt，月卡只占上半部，
下半屏浪费；同时格子行高固定 56pt，触控目标没有利用大屏红利。

**建议方案**：

1. 月历 42 格行高改**弹性**（`LazyVGrid` 的格子用 `frame(maxHeight: .infinity)`
   或外层 `GeometryReader` 分配剩余高度），让月卡垂直铺满中栏可视区——
   大屏 = 大格子 = 大触控目标，这正是 iPad 日历（系统日历/Fantastical）的做法；
2. 行高设上下限（如 56~96pt），防止极端分屏下过高。

**验收**：11" 竖屏 / 13" 横屏截图，月卡底边贴近可视区底部、无大空白；
格子行高在限幅内；横滑翻月手势仍 1:1 跟手。

### P0-3 AI 助手在 iPad 没有主入口

**问题**：`iPadRootView` 侧栏 5 节**没有 AI 助手**；iPad 上唯一入口是
设置页头部卡的 AI 按钮（sheet）——入口埋两层深，且与 iPhone 的独立 Tab
信息架构不一致。

**建议方案**：

- 侧栏增加「AI 助手」节（systemImage `sparkles`），中栏放 `AIAssistantView`
  （其内部已自带 `NavigationStack`，注意与 P0-1 同款套娃问题，需参数化）；
- 侧栏顺序：日历 / 年视图 / **AI 助手** / 全部日程 / 倒数日 / 设置；
- 保留设置头部卡入口作为快捷方式。

**验收**：侧栏可见且可点；Flow 4 加 `ipad.sidebar.ai` 锚点与切换断言；
`NavigationCoordinator.iPadSection` 增加 case 不影响旧数据（enum 无持久化，确认即可）。

### P0-4 右栏 Inspector 宽度（320–460）与 `DayDetailView` 内容设计宽度（760）不匹配

**问题**：`DayDetailView` 按 `isWide` 设计 760pt 版式，但右栏 ideal 仅 380pt——
头部大数字 + 农历 + 干支 + 节日 + 休假 + 天气挤在 380pt 里，
「更多黄历」5 列小格在右栏**比在 iPhone 上截断更严重**；纵向三张卡 = 右栏长滚动，
Inspector 的"扫一眼"价值被削弱。

**建议方案**（组合）：

1. 右栏 ideal 380 → **480**，max 460 → 560（`navigationSplitViewColumnWidth`）；
   三栏总宽 12.9"（1024pt）仍容得下（280+480+560 超了，依赖系统压缩 min——
   故 min 保持 320，ideal 480 仅在大屏生效）；
2. 「更多黄历」5 列 HStack 改 **2 列网格**（通用项 P1-1，iPad 右栏是重灾区，
   一并验收）；
3. 远期（不阻塞）：右栏改"摘要式 Inspector"——只保留日期/农历/宜忌前 3 条/
   事件数，完整内容留在「黄历」路径（对齐 macOS 的 Inspector 心智）。

**验收**：右栏 480pt 下头部卡各元素不截断；三档设备（iPad mini 8.3" / 11" / 13"）
横竖屏截图走查；Flow 4 右栏断言保持绿。

**进度（2026-09-27）**：第 **2** 条（「更多黄历」改 2 列网格）**已完成**，
随通用评审 P1-1 一并落地——右栏是这处截断的重灾区，改法见
`UI_DESIGN_REVIEW_2026-09-27.md` 的 P1-1 落地记录。
第 **1** 条（右栏 380 → 480 / max 560）与第 **3** 条（摘要式 Inspector）**未做**，
随 iPad 线批次执行；注意第 1 条要实测「12.9" 下 min 320 + ideal 480 + 右栏 560
是否会触发系统压缩」，本文原稿对此只是推算。

---

## P1：体验打磨（4 项）

### P1-1 竖屏选中侧栏节后自动收起侧栏

**问题**：iPad 竖屏（820pt 宽）三栏同显，中栏+右栏被压到接近 min，
内容区局促；系统类 App 的惯例是**竖屏选中节后自动收起侧栏**（`columnVisibility`），
横屏再展开。

**建议方案**：`onChange(of: nav.iPadSection)` 里，
竖屏（`horizontalSizeClass == .regular && verticalSizeClass == .regular` 且
宽度 < 1000pt 时）置 `.doubleColumn`；横屏或手动拖出时 `.all`。
注意与「全部日程/设置节隐藏右栏」的现有逻辑合并，避免两个 onChange 打架。

**验收**：竖屏点节 → 侧栏收起、中栏扩大；横屏旋转 → 三栏恢复；
手势拖出侧栏后不被 onChange 立刻收回（加 user-initiated 标记）。

### P1-2 指针与键盘支持（iPad 专业用户预期）

**问题**：全程无 pointer/键盘适配——鼠标悬停日历格无高亮、无悬停光标，
无键盘快捷键；对" iPad 当电脑用"的用户是明显短板。

**建议方案**（低成本批次）：

- 日历格 / 列表行加 `.hoverEffect(.highlight)`（iPad pointer 系统组件）；
- 可点格加 `.onHover { NSCursor.pointingHand.set() }`（或 SwiftUI 光标 API）；
- 键盘快捷键（`.keyboardShortcut`）：⌘N 新建日程、⌘T 回到今天、
  ⌘[ / ⌘] 翻月、← / → 选中日移动；`@FocusState` 配合侧栏；
- 与 Reduce Motion 已有集中降级天然兼容（无新动画）。

**验收**：接妙控板/鼠标悬停日历格有系统高亮；快捷键在月历节生效；
不影响 iPhone 构建（全部 API iOS 17 可用，`#if canImport(UIKit)` 不需要）。

### ~~P1-3 `CountdownDetailView` 硬编码中文 locale~~ **已完成（2026-09-27，批次 0）**

**问题**：右栏日期格式化写死 `Locale(identifier: "zh_Hans_CN")`，
英文/日文界面右栏日期仍显示中文——与 `EventEditView` 的 DatePicker locale 问题
同族，但这里在 iPad 专属右栏，容易被通用排查漏掉。

**建议方案**：去掉硬编码，跟随系统 locale（`event.date.formatted(.dateTime
.year().month(.wide).day())` 或 `Date.FormatStyle(date: .long)` 默认行为）。

**验收**：系统语言切英文/日文，右栏倒数日日期格式与界面语言一致。

**落地（2026-09-27）**：`CountdownDetailView.swift` 已改为
`Date.FormatStyle(date: .long, time: .omitted)`（默认 locale = `.autoupdatingCurrent`）。
同类问题在通用评审 P1-3 里一并清完——**全仓实为 9 处**，本文只点到 iPad 这一处，
通用评审当时也漏了 `CountdownView.swift`、`AllEventsView.swift`、`CalendarMonthGridBuilder.swift`
与 `AICommandValidator.swift`（详见 `UI_DESIGN_REVIEW_2026-09-27.md` 的 P1-3 落地记录）。
⚠️ **英/日界面截图验收未做**，并入截图批次。

### P1-4 分屏 / Slide Over 回退路径回归

**问题**：compact 尺寸回退 `PhoneTabRootView`（4 Tab），此路径**无 UI 测试覆盖**；
分屏 50/50 下 TabBar + 月视图 + 选中卡的 96pt 底部留白在矮高度下表现未知。

**建议方案**：

1. XCTest 增加 iPad 分屏用例（或至少手动清单项进 `DEVICE_TEST_CHECKLIST.md`）：
   50/50 分屏、Slide Over、竖屏三栏；
2. 检查 `PhoneTabRootView` 在 iPad compact 下的「黄历」Tab 与月历并存是否合理
   （信息重复在窄屏可接受，但确认无布局崩溃）；
3. 中栏 min 340 在分屏 compact 时是否生效过宽——确认无。

**验收**：`DEVICE_TEST_CHECKLIST.md` 新增 iPad 窗口形态小节；
50/50 分屏截图无重叠/裁切。

---

## P2：细节（3 项）

### ~~P2-1 iPad 月视图菜单与侧栏重复收口~~ **已完成（2026-09-27，批次 1）**

中栏月历的「功能菜单」在 `isIPadSplit` 分支仍列出「倒数日 / 设置」（sheet 弹出），
与侧栏节重复。建议 iPad 下菜单只留「回到今天 / 跳转到日期 / 全部日程」——
倒数日、设置归侧栏独家。（与通用评审 P0-2 同批改，本文记 iPad 验收口径。）

**落地（2026-09-27）**：`CalendarMonthView.swift` 菜单按 `isIPadSplit` 收口，
**iPad 分支现在只剩「跳转到日期」一项**、iPhone 分支只剩「跳转到日期 / 全部日程 / 倒数日」。
与本文建议的两点差异，都是按代码事实收窄的：

1. **「回到今天」没保留**：通用评审 P0-2 第 1 条要求它只留工具栏按钮，菜单里删掉
   （工具栏那枚 `AccessibilityID.todayJump` 与菜单项的动作代码逐字相同）；
2. **「全部日程」没保留**：iPad 上它已是**侧栏的一个节**，再放进菜单就是新造一处重复——
   本文这句建议与「侧栏是唯一权威入口」的前提自相矛盾，故按前提执行。

> 顺带记录一个**待定的后续问题**：iPad 菜单现在只剩「跳转到日期」，而月历的**月份标题本身就是
> 跳转日期入口**（点击 → `showDateJump = true`），也就是说 iPad 上整个菜单可能已经没有存在必要。
> 但若 P0-1 的裁决选方案 C（年视图移出侧栏、入口落到菜单），这里会立刻多出一项。
> 因此**保留 Menu 容器**，不退回单个按钮；是否彻底删掉菜单，等 P0-1 定案后一并决定。

### P2-2 编辑器在 iPad 的呈现形态

`CountdownEditor`、`EventEditView`（sheet 场景）在 iPad 默认从屏幕底缘升起的大 sheet，
对短表单偏重。建议 iPad 改 `.popover`（居中气泡，自动避让）或
`.presentationDetents([.medium, .large])`；注意 popover 在 iPhone 自动降级为 sheet，
一套代码两平台。低优先级，表单本身已很原生。

### P2-3 侧栏视觉微调

侧栏标题「清和日历」+ 5 节纯文字 List 略素。建议：给侧栏节加 appTint 选中态
（系统默认已有），头部插入品牌区（图标 + 版本，复用 `AboutSectionView` 元素），
与设置页 Hero 卡同源。纯装饰项，最后做。

---

## 施工顺序与工作量

| 序 | 事项 | 预估 | 说明 |
|---|---|---|---|
| 1 | P0-1 年视图 iPad 路径（推荐方案 A：改 sheet） | 0.5 天 | ⚠️ **方案 A 自身有问题，待重新裁决**——见文末「待裁决」一节 |
| 2 | P0-3 AI 助手侧栏节 | 0.5 天 | 注意 `AIAssistantView` 自带 NavigationStack 的套娃 |
| ~~3~~ | ~~P1-3 / P2-1 小修复~~ → **全部完成（P1-3 批次 0，P2-1 批次 1）** | 0.5 天 | locale 9 处已清；iPad 菜单收口后只剩「跳转到日期」 |
| 4 | P0-2 月卡弹性行高 | 1 天 | 手势阈值随高度联动需回归横滑 |
| 5 | P0-4 右栏加宽 + 更多黄历 2 列 | 1 天 | 与通用评审 P1-1 合并验收 |
| 6 | P1-1 竖屏自动收侧栏 | 0.5 天 | 与现有 columnVisibility 逻辑合并 |
| 7 | P1-2 指针/键盘批次 | 1 天 | 纯增量，可拆分 |
| 8 | P1-4 分屏回归 + P2-2/3 | 1 天 | 清单与呈现形态 |

## iPad 专项验收清单

> **批次 0 / 1 / 2 落地状态（2026-09-27）**：P1-3（右栏 locale，批次 0）、
> P2-1（菜单收口，批次 1）、P0-4 第 2 条（「更多黄历」2 列网格，批次 2）已完成；
> 验证为 `swift test` 310 条全绿 + 双端 UI 测试 0 失败（iPad 上 Flow 4 通过）。
> **下列九条多数仍未做**——只有三处被部分满足（右栏日期本地化、更多黄历不再截断、
> Flow 4 保持绿），其余（截图走查、年视图套娃、月卡弹性行高、侧栏 AI 节、右栏 480pt、
> 竖屏收侧栏、指针键盘、分屏回归）**全部未动**。

- [ ] iPad mini 8.3" / 11" / 13" × 横竖屏 × 深浅色截图走查
- [ ] 年视图：无套娃 NavigationStack、「完成」可用
- [ ] ⚠️ ~~迷你月格 ≥ 44pt~~ **该判据已作废**：可点的是**整张迷你月卡**
      （`YearOverviewView.swift:76-77` `.contentShape(Rectangle())` + `onTapGesture`，宽约 113pt），
      远超 44pt，**不存在触控目标不足**。真实问题是卡内星期头只有 **8pt**（`:122`），
      属**可读性**问题 → 验收改为「放宽列数后卡内文字可读」。
- [ ] 月卡填满中栏可视区、行高在 56~96pt 限幅内
- [ ] 侧栏 6 节含 AI 助手；`ipad.sidebar.*` 锚点齐全
- [ ] 右栏 480pt：头部卡无截断；~~英/日界面右栏日期本地化~~ ← **本地化部分已完成（批次 0）**，480pt 加宽未做
- [ ] 竖屏选节后侧栏自动收起；横屏恢复；手势拖出不被收回
- [ ] 悬停高亮 + ⌘N/⌘T/⌘[/⌘]/←→ 快捷键可用
- [ ] 50/50 分屏与 Slide Over 无布局异常（截图入档）
- [ ] Flow 4（iPad）全绿 + 新增年视图/AI 节断言 ← Flow 4 已绿；新增断言待 P0-1 / P0-3 定案

---

## P0-1 年视图在 iPad 的路径（**2026-09-27 裁决：方案 C**）

本文推荐的**方案 A**（侧栏选中「年视图」→ 中栏保持月历、以 sheet 弹出年视图）
在动工前复核时发现两个本文未列出的问题：

1. **选中态与内容不一致**：侧栏项被选中、中栏却不切内容，侧栏的选中语义被破坏；
2. **连带面未列**：若因方案 A 而移除 `iPadSection.year`，会连带
   `Support/AccessibilityID.swift`（`iPadSidebarYear`）、中栏 `switch`
   （`LunisolarCalendarApp.swift:193`）与 Flow 4 的既有断言，三处都要改。

**提出的第三条路（C）**：年视图从侧栏移除，入口收敛到月历菜单——iPhone 现状就是
「功能菜单 → 跳转到日期 → 全年视图」（`DateJumpView.swift:74`、`:108` 已有），
走 C 可顺带消掉一处重复入口，且不产生选中态不一致。

**裁决与理由（2026-09-27）**：采用**方案 C**。①不产生「侧栏选中却弹 sheet」的选中态歧义；
②顺带消掉一处重复入口（与通用评审 P0-2 的收敛方向一致）；③iPad 与 iPhone 的入口心智统一。
且 iPad 上「跳转到日期 → 全年视图」这条路径**已经存在**，不需要新造入口。

**尚未落地**。实施清单（与 iPad 线批次一起做）：

- `LunisolarCalendarApp.swift`：侧栏 5 节 → 4 节（去掉 `.year`）；中栏 `switch` 去掉 year 分支；
  `NavigationCoordinator.iPadSection` 去掉 `.year` case；
- `Support/AccessibilityID.swift`：移除 `iPadSidebarYear`（注意它是 `all` 数组的成员，
  删了要同步数组，否则 `testAllIDsAreNonEmptyAndUnique` 仍会通过但留下悬空常量；
  而 `AccessibilityIDTests` 的命名规范测试会照常覆盖剩余项）；
- `LunisolarCalendarUITests`：Flow 4 若有年视图节的断言需同步调整；
- 顺带定：iPad 月历菜单届时是否彻底删除（现在只剩「跳转到日期」，而月标题点击同效——
  见 P2-1 落地记录里的待定问题）。
