# iPad 版 UI 改进优化设计文案（2026-09-27）

> 范围：仅 iPad / iPadOS（iPhone 适配不动）。基线：代码 HEAD 2026-09-27。
> 依据：`LunisolarCalendarApp.swift`（`iPadRootView` / `PhoneTabRootView`）、
> `CalendarMonthView.swift`（`isIPadSplit` 分支）、`YearOverviewView.swift`、
> `CountdownDetailView.swift`、`DayDetailView.swift`。
> 优先级：**P0 = 功能/布局硬伤，P1 = 体验打磨，P2 = 细节**。
> 配套总评审见 `UI_DESIGN_REVIEW_2026-09-27.md`（本文不重复通用项）。
> **施工进度**：批次 0（P1-3）、批次 1（P2-1）、批次 2（P0-4 第 2 条）与
> **批次 3（P0-1 / P0-2 / P0-3 / P0-4 第 1 条 / P1-1）已完成 2026-09-27**，其余未动；
> P0-1 已裁决并落地走方案 C，实施记录见文末。

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

### ~~P0-2 iPad 中栏月卡下方大片空白，格子不随屏幕高度拉伸~~ **已完成（2026-09-27，批次 3）**

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

**落地（2026-09-27，批次 3）**：`CalendarMonthView` 新增 `elasticCellHeight(rows:)`——
用背景 `GeometryReader` 量出中栏可视高度（`columnHeight`，与既有的 `monthWidth` 同一手法），
扣掉「月份标题 + 节气条 + 星期表头 + 内边距」的估算值后按行均分，夹在 **56~96pt**。
iPhone 上它返回 `nil`，走的还是原来的 `minHeight: 56`，**一行都没动**。

- 原方案说的 `frame(maxHeight: .infinity)` 在这里行不通：月卡在 `ScrollView` 里，
  高度不受限，拿不到「剩余高度」的提案，所以改成「量高度 + 算行高」。
- ⚠️ **本文的两条验收互相矛盾（原文没注意到）**：「月卡底边贴近可视区底部、无大空白」
  与「行高 ≤96pt」不可能同时成立——13" 屏可视高度约 1000pt，6 行 × 96 = 576pt，
  月卡下方**必然仍有留白**。要真正填满只能往下方放内容（例如「今日安排」列表），
  那是产品决策，不在本批。
- ⚠️ **截图验收未做**（11" 竖屏 / 13" 横屏），**横滑翻月手势也未肉眼回归**——
  本条改了每个格子的高度，手势阈值是按宽度算的（`monthWidth`），理论上不受影响，
  但这是本批风险最高的一处改动。

### ~~P0-3 AI 助手在 iPad 没有主入口~~ **已完成（2026-09-27，批次 3）**

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

**落地（2026-09-27，批次 3）**：侧栏新增「AI 助手」节（`sparkles`，锚点
`AccessibilityID.iPadSidebarAI = "ipad.sidebar.ai"`），中栏直接放
`AIAssistantView().environment(store)`。侧栏顺序落地为 **日历 / AI 助手 / 全部日程 /
倒数日 / 设置**（年视图已按 P0-1 移出，故没有「日历 / 年视图 / AI 助手 / …」这一版）。
设置页头部卡的 AI 入口按本文要求保留为快捷方式。

- **本文担心的「套娃」在实现时是反向处理**：`AIAssistantView` 自身已经包了
  `NavigationStack`，所以这里**不**再包一层（其余节之所以要包，是那些视图自身不带导航栈）。
  已在代码注释里写明，避免以后有人「照抄其他节」补一层。
- AI 节与全部日程 / 设置一样收起右栏——这条逻辑在落地时**修掉了一个真 bug**，见 P1-1。
- 新增 **Flow 9** 断言 `ipad.sidebar.ai` 存在；`iPadSection` 无持久化，旧数据不受影响（已确认）。

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

**进度（2026-09-27）**：第 **1**、**2** 条**已完成**，第 3 条未做。

- 第 2 条（「更多黄历」改 2 列网格）随通用评审 P1-1 一并落地，改法见
  `UI_DESIGN_REVIEW_2026-09-27.md` 的 P1-1 落地记录；
- 第 1 条（右栏 `min: 320`（不变）/ `ideal: 380 → 480` / `max: 460 → 560`）已在批次 3
  落地，改的是 `iPadRootView.detailColumn` 里的两处（日历节与倒数日节）。
  ⚠️ **本文要求的三档设备截图未做**：12.9" 横屏（1024pt）下「侧栏 + 中栏 340~480 +
  右栏 320~560」的总宽已接近甚至超过屏宽，实际会不会被系统压缩、压到多少，
  只能看截图——本文原稿对此也只是推算。
  另外注意：右栏加宽后，「无 Inspector 的节是否会多出一列空白右栏」这个问题
  影响面也更大（见 P1-1 的落地记录）。
- 第 3 条（摘要式 Inspector：只留日期/农历/宜忌前 3 条/事件数）**未做**。

---

## P1：体验打磨（4 项）

### ~~P1-1 竖屏选中侧栏节后自动收起侧栏~~ **已完成（2026-09-27，批次 3）——顺带修掉一个真 bug**

**问题**：iPad 竖屏（820pt 宽）三栏同显，中栏+右栏被压到接近 min，
内容区局促；系统类 App 的惯例是**竖屏选中节后自动收起侧栏**（`columnVisibility`），
横屏再展开。

**建议方案**：`onChange(of: nav.iPadSection)` 里，
竖屏（`horizontalSizeClass == .regular && verticalSizeClass == .regular` 且
宽度 < 1000pt 时）置 `.doubleColumn`；横屏或手动拖出时 `.all`。
注意与「全部日程/设置节隐藏右栏」的现有逻辑合并，避免两个 onChange 打架。

**验收**：竖屏点节 → 侧栏收起、中栏扩大；横屏旋转 → 三栏恢复；
手势拖出侧栏后不被 onChange 立刻收回（加 user-initiated 标记）。

**落地（2026-09-27，批次 3）**：判断依据改为**窗口宽度**（不用 sizeClass：iPad 横竖屏
都是 `.regular`，区分不了）。`iPadRootView` 用背景 `GeometryReader` 读窗口宽度，
`applyColumnVisibility()` 统一决策——窄于 1000pt 置 `.doubleColumn`，否则 `.all`。

#### 落地时抓到的一个真 bug（本批最有价值的产出）

**`.doubleColumn` 在三栏布局里的语义是「内容列 + 详情列、隐藏侧栏」，不是「隐藏右栏」。**
旧代码正是用 `.doubleColumn` 表达「全部日程 / 设置节不出右栏」（注释也这么写），
于是**切到这两节后侧栏会一起消失，用户失去导航入口**。这个 bug 一直没被发现：
Flow 4 只走「日历 ↔ 倒数日」，两者都是 `.all`，从未覆盖无 Inspector 的节。

发现方式：新写的 **Flow 9** 直接断言「切到『全部日程』后侧栏必须仍在」
（把注释与实现的分歧做成可执行的断言），**首次运行即红**，事实于是被钉住。
修法：无 Inspector 的节不再改 `columnVisibility`，统一 `.all`；右栏因为 `detailColumn`
返回 `EmptyView()` 而没有内容可占。

- ⚠️ **仍需截图确认**：`.all` 下无 Inspector 的节会不会多出一列**空白右栏**？
  若会，可选（a）给右栏放一个有用的占位（如「选中一条日程查看详情」），
  （b）接受空白列。本文没料到这一层。
- ⚠️ **窄屏分支同样要确认**：`.doubleColumn` 会**同时**收起右栏，所以竖屏更可能是
  「中栏占满」而不是先前的实测记录「中栏 + 右栏两列」——这两句必有一句要改，
  以真机/模拟器截图为准（与 P1-4 的分屏回归一起看）。
- 本文建议的「user-initiated 标记」**没有实现，也确实不需要**：拖动侧栏不会改变
  `nav.iPadSection`，而 `onChange` 只监听该字段，所以手势拖出后不会被立刻收回。
  但有一个已知取舍：**宽屏下手动收起侧栏后，切换节会把三栏恢复**（本方法无条件重算）——
  要保留手动态就得引入「这个值是不是我写的」标记，收益不大，本批未做，已写进代码注释。

### ~~P1-2 指针与键盘支持~~ **已完成（2026-09-27）**

**问题**：全程无 pointer/键盘适配——鼠标悬停日历格无高亮、无悬停光标，
无键盘快捷键；对" iPad 当电脑用"的用户是明显短板。

**落地（2026-09-27）**：
- 悬停高亮：日期格（`DayCellView`）/ 事件行（`EventRow`）/ 倒数日行（`CountdownRow`）
  加 `.hoverEffect(.highlight)`（`#if canImport(UIKit)` 守卫，macOS 宿主构建不受影响）。
- 键盘快捷键：⌘T 回到今天、⌘N 新建日程（挂在既有工具栏按钮上）；
  ⌘[ / ⌘] 翻月（挂在月份 Chevron 按钮上）；← / → 移动选中日期
  （`onKeyPress` 挂在月历 ScrollView 上，`selectDay` 自带跨月联动）。
- **与原建议的两点偏差**：① 自定义光标形状（`NSCursor`）**没做**——它是 AppKit API、
  iPadOS 无公开替代，系统指针 + `.hoverEffect` 已是标准做法；② 上/下方向键没做
  （文档只点到 ← →；±7 天可用翻月替代，需要时再加）。

**验收口径**：妙控板悬停日历格有系统高亮；快捷键在月历节生效；
不影响 iPhone 与 macOS 构建（四通道验证绿）。

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

### ~~P1-4 分屏 / Slide Over 回退路径回归~~ **清单已落地（2026-09-27）；分屏本体只能真机**

**问题**：compact 尺寸回退 `PhoneTabRootView`（4 Tab），此路径**无 UI 测试覆盖**；
分屏 50/50 下 TabBar + 月视图 + 选中卡的 96pt 底部留白在矮高度下表现未知。

**落地（2026-09-27）**：
1. `docs/DEVICE_TEST_CHECKLIST.md` 新增 **§11.1 iPad 窗口形态**（50/50 分屏、Slide Over、
   底部留白、指针悬停与快捷键一并入清单）；§11 主清单按上下文 Inspector 新语义重述；
2. compact 回退路径代码核对：`AdaptiveRootView` 按 `horizontalSizeClass` 分流，
   分屏下走 `PhoneTabRootView` 属**既有设计**（黄历 Tab 与月历并存 = 可接受的信息重复），
   无需改动；中栏 min 340 只在 regular 生效，compact 走整宽，无过宽问题。
3. **不能自动化的部分**：XCUITest 造不出分屏/Slide Over 窗口形态（需多 App 编排），
   回归只能靠真机清单 §11.1。

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

### ~~P2-2 编辑器在 iPad 的呈现形态~~ **已完成（2026-09-27）**

`CountdownEditor` 的两处 sheet（倒数日列表页 `CountdownView`、iPad 右栏
`CountdownDetailView`）补 `.presentationDetents([.medium, .large])` + 拖拽指示器，
与事件编辑器（`MonthSheets` 的 P1-8a 口径）一致——iPad 不再默认从底缘升起全屏大 sheet。
未采用 `.popover`：popOver 在 iPhone 降级为 sheet 虽一套代码，但表单高度不固定时
popover 自动避让行为不如 detent 可控，detents 两平台一致更稳。

### ~~P2-3 侧栏视觉微调~~ **已完成（2026-09-27）**

侧栏 List 顶部插入品牌区（App 图标 40×40 + 名称 + 版本号，元素与设置页 Hero 卡同源），
纯装饰、不参与 List 选择；节选中态沿用系统默认（appTint）。
「清和日历」导航大标题保留，与品牌区形成「标题 + 徽标」的常规 iPad 侧栏形态。

---

## 施工顺序与工作量

| 序 | 事项 | 预估 | 说明 |
|---|---|---|---|
| ~~1~~ | ~~P0-1 年视图 iPad 路径~~ → **已完成（批次 3，走方案 C）** | 0.5 天 | 见文末的裁决与落地记录；顺带消掉一处重复入口 |
| ~~2~~ | ~~P0-3 AI 助手侧栏节~~ → **已完成（批次 3）** | 0.5 天 | 「套娃」是反向处理：`AIAssistantView` 自带导航栈，**不要**再包 |
| ~~3~~ | ~~P1-3 / P2-1 小修复~~ → **全部完成（P1-3 批次 0，P2-1 批次 1）** | 0.5 天 | locale 9 处已清；iPad 菜单收口后只剩「跳转到日期」 |
| ~~4~~ | ~~P0-2 月卡弹性行高~~ → **已完成（批次 3）** | 1 天 | 已实现 56~96pt；但**横滑手势需肉眼回归**（本批风险最高） |
| ~~5~~ | ~~P0-4 右栏加宽 + 更多黄历 2 列~~ → **已完成（批次 3）** | 1 天 | 右栏 380→480 / 460→560；**三档设备截图未做** |
| ~~6~~ | ~~P1-1 竖屏自动收侧栏~~ → **已完成（批次 3）** | 0.5 天 | 改按窗口宽度判断；**顺带修掉一个真 bug**（见该节） |
| ~~7~~ | ~~P1-2 指针/键盘批次~~ → **已完成（2026-09-27）** | 1 天 | 悬停高亮 3 处 + 快捷键 ⌘T/⌘N/⌘[]/←→；自定义光标因 iPadOS 无公开 API 未做（记录在案） |
| ~~8~~ | ~~P1-4 分屏回归 + P2-2/3~~ → **已完成（2026-09-27）** | 1 天 | 清单 §11.1 + P2-2 detents + P2-3 品牌区；分屏本体只能真机（XCUITest 造不出窗口形态） |

## iPad 专项验收清单

> **批次 0 / 1 / 2 / 3 落地状态（2026-09-27）**：本文的 P1-3（批次 0）、P2-1（批次 1）、
> P0-4 第 2 条（批次 2）、**P0-1 / P0-2 / P0-3 / P0-4 第 1 条 / P1-1（批次 3）**均已完成。
> 验证：`swift test` 310 条全绿、iOS SDK 构建通过、iPhone 17 Pro 10 跑 2 跳 0 失败、
> iPad Pro 11" 10 跑 5 跳 **0 失败**（含新增的 **Flow 9**）。
> 但**下列九条验收项一条都没做完**——批次 3 全是布局改动，恰恰最需要这一轮截图。

- [ ] iPad mini 8.3" / 11" / 13" × 横竖屏 × 深浅色截图走查 ← **批次 3 全部改动都压在这一条上**
- [ ] 年视图：无套娃 NavigationStack、「完成」可用（改从「跳转到日期 → 全年视图」进）
- [ ] ⚠️ ~~迷你月格 ≥ 44pt~~ **该判据已作废**：可点的是**整张迷你月卡**
      （`YearOverviewView.swift:76-77` `.contentShape(Rectangle())` + `onTapGesture`，宽约 113pt），
      远超 44pt，**不存在触控目标不足**。真实问题是卡内星期头只有 **8pt**（`:122`），
      属**可读性**问题 → 验收改为「放宽列数后卡内文字可读」。
- [ ] 月卡填满中栏可视区、行高在 56~96pt 限幅内 ← 行高已实现；**「填满」做不到**
      （96pt 上限与「无大空白」互斥，见 P0-2 落地）
- [ ] 侧栏 5 节含 AI 助手、**不含年视图**；`ipad.sidebar.*` 锚点齐全 ← Flow 9 已覆盖前两项
- [ ] 右栏 480pt：头部卡无截断；**无 Inspector 的节是否多出一列空白右栏**
- [ ] 竖屏选节后侧栏自动收起；横屏恢复；手势拖出不被收回 ← 已实现；**竖屏是「中栏占满」
      还是「中栏 + 右栏两列」需实测**（与上一版记录冲突）
- [ ] 悬停高亮 + ⌘N/⌘T/⌘[/⌘]/←→ 快捷键可用
- [ ] 50/50 分屏与 Slide Over 无布局异常（截图入档）
- [ ] Flow 4（iPad）全绿 + 新增 AI 节断言 ← **Flow 4、Flow 9 均已绿**

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

**已落地（2026-09-27 批次 3）**。实际实施与上面的清单有四处出入，逐条记下：

- `NavigationCoordinator.iPadSection`：`.year` 换成 `.ai`（一次改完 P0-1 与 P0-3 两件事），
  枚举现为 `calendar / ai / agenda / countdown / settings`；
- `LunisolarCalendarApp.swift`：侧栏与中栏都去掉了 year 分支。**三列内容被抽成了三个属性**
  （`sidebar` / `contentColumn` / `detailColumn`）——这不是风格偏好，而是硬要求：
  整个 `NavigationSplitView` 表达式内联三个闭包 + 两个 switch 时，Swift 编译器直接报
  `the compiler is unable to type-check this expression in reasonable time`（给侧栏加到
  第 5 个 case 时触发）。同理，`columnVisibility` 的三元表达式也改成了方法调用。
  这三处拆分是本批唯一「为编译器让路」的改动，已写进代码注释。
- `AccessibilityID`：`iPadSidebarYear` 已从常量与 `all` 数组**一并移除**（只删常量会在
  `all` 里留一个编译不过的引用），新增 `iPadSidebarAI`；
- **入口路径复核成立**：iPad 上「跳转到日期 → 全年视图」本来就在（`DateJumpView` 内），
  C 落地后**不需要新造入口**——这点在裁决时是推断，落地时已确认。
- 新增 **Flow 9**（iPad）断言侧栏结构与栏位语义；它顺带抓到一处真 bug，见 P1-1 的落地记录。

**顺带回答 P2-1 留下的待定问题**：iPad 月历菜单**保留**「跳转到日期」一项。虽然月标题点击
同效，但菜单项对不熟悉该手势的用户仍是有用的发现路径，删掉会让 iPad 上少一个可发现入口。
