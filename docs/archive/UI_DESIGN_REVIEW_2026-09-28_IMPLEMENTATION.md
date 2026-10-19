# UI 设计评审（2026-09-28）N 批次实施文档

> 对应评审文档：`UI_DESIGN_REVIEW_2026-09-28.md`（N-1 ~ N-10）
> 实施日期：2026-09-28
> 基线 commit：`336ce75`（完整检查修复轮，已 push GitHub）
> 本批次状态：代码改动已完成，未 commit / 未 push / 未真机验证（详见文末清单）

---

## 一、改动总览

本批次按评审文档施工顺序逐条落地，共改动 **20 个文件**：

| 文件 | 涉及条目 | 改动摘要 |
|---|---|---|
| `App/NavigationCoordinator.swift` | N-1 | AI 助手深链补 iPad 分区切换 |
| `App/LunisolarCalendarApp.swift` | N-5 / N-9 | 侧栏删导航标题；品牌字号收编 token |
| `Support/AppTheme.swift` | N-9 | 新增 9 个字号 token |
| `Views/CalendarMonthView.swift` | N-3 / N-4 / N-9 / N-10 | chrome 高度测量、缓存、紧凑摘要、字号 token |
| `Views/CalendarMonthSheets.swift` | N-8 | 事件编辑 sheet detents 适配 |
| `Views/QingheUIComponents.swift` | N-8 / N-9 | eventEditorDetents 扩展；字号 token |
| `Views/CountdownView.swift` | N-9 | 字号 token |
| `Views/CountdownDetailView.swift` | N-9 | 字号 token |
| `Views/YearOverviewView.swift` | N-9 | 4 处迷你月卡豁免注释 |
| `Views/SelectedDayCardView.swift` | N-10 / N-9 | 紧凑摘要模式；图标豁免 |
| `Views/AllEventsView.swift` | N-6 / N-9 | ⌘F 聚焦搜索；图标豁免 |
| `Views/DateJumpView.swift` | N-7 | 年视图 sheet → popover |
| `Views/AIAssistantView.swift` | N-6 / N-9 | ⌘Return 提交；图标豁免 |
| `Views/DayDetailView.swift` | N-9 | 字号 token |
| `Views/EventRow.swift` | N-9 | 复选框字号 token |
| `Views/QingheStateViews.swift` | N-9 | 空态大数字 token |
| `Views/SettingsViewComponents.swift` | N-9 | 字号 token |
| `Views/WeatherIconView.swift` | N-9 | 天气图标字号 token |
| `Views/CalendarComponents.swift` | N-9 | 「休/班」徽章豁免注释 |
| `.github/workflows/ci.yml` | N-9 | 新增硬编码字号红线 job |

---

## 二、逐条实施明细

### N-1（P0 · 深链）：AI 助手入口 iPad 分区切换

**问题**：`qinghe://ai` 深链在 iPad 上打开 AI 助手时，若当前侧栏分区不是 `.ai`，会打开但侧栏选中态错位。

**修复**（`NavigationCoordinator.swift`）：
- `openAIAssistant()` 中补 `self.iPadSection = .ai`，保证深链同时切换侧栏高亮分区；
- 同步更新过时注释（说明 AI 助手在 iPad 侧栏独立分区）。

**验证**：`DeepLinkRouter.swift` 核实 ai 路由本就调用 `openAIAssistant()`，无遗漏。双端用例（iPhone 独立 Tab / iPad 侧栏分区）待真机。

---

### N-2：iPad 细节列占位视图

**问题**：iPad 分栏下 detailColumn 无选中内容时空白。

**修复**（`LunisolarCalendarApp.swift`）：
- detailColumn 的空视图改用新增 helper `rightColumnPlaceholder(for:)`；
- 三种占位（sparkles / list.bullet.rectangle / gearshape）各有图标 + 标题 + 副标题，文案全部 `NSLocalizedString`，四语言同步。

---

### N-3（P0 · Chrome 魔数消除）：月历滚动弹性高度

**问题**：月历滚动时「月标题 + 节气条 + 星期表头」高度曾是魔数常量（未测量），设备尺寸变化时弹性间距失真。

**修复**（`CalendarMonthView.swift`）：
- 新增文件级 `MonthChromeHeightKey: PreferenceKey`（defaultValue 0，reduce 累加）；
- monthColumn 中 monthHeader + solarTermBar 合包 VStack，用 `.background(GeometryReader)` 上报高度；`WeekHeaderView` 同步上报；
- ScrollView 挂 `.onPreferenceChange(MonthChromeHeightKey.self)` 写入 `chromeHeight`；
- `elasticCellHeight` 重构：移除 `isIPadSplit` guard（iPhone 也启用）；chrome = 实测 chromeHeight + 卡片边距 + 网格行距，未测量时回退 170。

---

### N-4（P0 · 性能）：横滑翻月零重算

**问题**：月历视图在每次渲染时重新计算「今天」的 DayAccent（农历/节气/节日），横滑翻月时选中日期不变也会全量重算。

**修复**（`CalendarMonthView.swift`）：
- 新增 `@State cachedDayAccent: DayAccent = DayAccent(date: Date())`；
- `dayAccentForToday` / `accentColorForToday` 改读缓存；
- `.onChange(of: selectedDate, initial: true)` 同步外部 binding，并仅在选中日变化时重建缓存（横滑翻月选中日不变 → 零重算）。

---

### N-5：侧栏品牌区顶到顶

**修复**（`LunisolarCalendarApp.swift`）：sidebar 删除 `.navigationTitle("清和日历")`，品牌 Section 直接顶到侧栏顶部，视觉更利落。

---

### N-6：iPad 外接键盘快捷键 + hover 补全

**修复**：
- **侧栏直达**（`LunisolarCalendarApp.swift`）：侧栏 5 行加 `.keyboardShortcut("1"..."5", modifiers: .command)` → 日历 / AI / 全部日程 / 倒数日 / 设置；
- **AI 助手 ⌘Return 提交**（`AIAssistantView.swift`）：List 挂 `.onKeyPress`，`⌘+Return` = parse()（与键盘「解析」等价；普通 Return 已由 AutoFocusTextView 提交）；
- **全部日程 ⌘F 聚焦搜索**（`AllEventsView.swift`）：加 `@FocusState searchFocused`，`.searchable(text:isPresented:)` 绑定，`.onKeyPress` 检测 `⌘+F` 聚焦搜索框；
- **事件行 hover**：`EventRow.swift:79` 已有 `.hoverEffect(.highlight)`，全部日程行复用 EventRow，无需重复添加。

### N-6 编译修复（2026-09-29，用户 Xcode 截图驱动）

**问题**：`AllEventsView.swift:133` 编译失败——`$searchFocused` 类型是 `FocusState<Bool>.Binding`，而 `.searchable(text:isPresented:)` 的 `isPresented` 参数要求 `Binding<Bool>`，两者不兼容（iOS / macOS 两分支各报 1 条，共 2 issues）。

**修复**：移除 `@FocusState searchFocused`，改用 `@State private var isSearchPresented = false` 作为呈现绑定（定义 + 2 处 `.searchable` + ⌘F 回调全部切换）。iOS 17+ 呈现搜索框后系统自动聚焦输入框，⌘F 只需置 `isSearchPresented = true` 即「显示并聚焦」。全仓确认无其他 `FocusState` 使用点。

---

### N-7：iPad sheet 叠 sheet → popover

**问题**：DateJumpView（sheet A）内又弹 YearOverviewView（sheet B），iPad 上形成两级模态堆叠。

**修复**（`DateJumpView.swift`）：
- 「全年视图」由 `.sheet` 改为 `.popover(isPresented:arrowEdge: .top)`；
- iPad 上为悬浮窗（不叠模态）；iPhone / 紧凑宽度下系统自动退化为全屏 sheet；
- `YearOverviewView` 内部无 sheet，只保留 `.presentationDetents([.large])`。

---

### N-8（三小条）：

① **Color.appTint 清零**：emoji 选中底色、`YearOverviewView` 两处今天圆点 / 事件点 `Color.accentColor` → `Color.appTint`（评审要求全仓统一品牌色）；
② **节气条视觉**（`CalendarMonthView.swift` solarTermBar）：节气名 `accent` + `.bold` + `Capsule().fill(accent.opacity(0.14))` 淡底衬，与日历格内节气显示呼应；
③ **事件编辑 sheet detents**：新增 `eventEditorDetents()` view extension（`QingheUIComponents.swift`，`#if os(iOS)` + pad → `[.large]`，否则 `[.medium, .large]`），两处事件编辑器 sheet 已换用。

---

### N-9（硬编码字号收编 + CI 红线）：

**原则**：动态字号是 iOS 无障碍基础。三类显式豁免（沿用 AppTheme.swift 既有清单）：
- ① SF Symbol 字形字号（图标固定方框）；
- ② 固定方框内 emoji 字号；
- ③ 固定密度迷你网格（年视图迷你月卡、「休/班」徽章）。

**AppTheme.swift 新增 9 个字号 token**（全部走 `scaled()` UIFontMetrics 动态缩放）：

| Token | 字号 | 用途 |
|---|---|---|
| `countdownNumber` | 30 semibold | 倒数日大数字 |
| `countdownLarge` | 40 semibold rounded | 倒数日详情大数字 |
| `brandWordmark` | 40 light | 品牌字标 |
| `emptyStateNumber` | 36 regular | 空态大数字 |
| `weatherIcon` | 32 medium | 天气图标 |
| `eventBadgeNumber` | 24 semibold | 事件徽章数字 |
| `compactNumber` | 28 semibold | 紧凑数字 |
| `chipTiny` | 10 medium | 微型胶囊标签 |
| `checkboxSymbol` | 18 semibold | 复选图标 |

**视图层收编 11 处**：LunisolarCalendarApp.swift（brandWordmark）、CountdownDetailView / CountdownView×2 / DayDetailView / EventRow / QingheStateViews×2 / QingheUIComponents / WeatherIconView×2。

**豁免注释 8 处**（同行 `N-9-exempt:`）：YearOverviewView×4（迷你月卡）、CalendarComponents（休/班徽章）、AIAssistantView / AllEventsView / SelectedDayCardView（SF Symbol 图标）。

**CI 红线**（`.github/workflows/ci.yml` 新增 `hardcoded-font-gate` job，ubuntu-latest）：
- 扫描 `Sources/` 下所有 `.swift` 的 `\.system(size:`；
- 排除 `Support/AppTheme.swift`（token 唯一合法出处）与 `Widgets/`（画布像素固定）；
- 剔除含 `N-9-exempt:` 的行；
- 命中即 `::error::` 标注 + exit 1。
- 本地复扫结果：**0 处未豁免命中**，红线当前通过。

---

### N-10（iPhone 首屏一屏看全）：

**修复**（`CalendarMonthView.swift` + `SelectedDayCardView.swift`）：
- `columnHeight` 测量去掉 `if isIPadSplit` 限制（iPhone 也实测）；
- 选中卡区改为 `SelectedDayCardView(..., compactSummaryOnly: !isPanelExpanded)`；
- 收起态：`.padding(.bottom, 12)` + `.frame(height: 64)` + `.contentShape(Rectangle())` + `.onTapGesture` 点按展开（展开态：padding 96、高度自适应）；
- `SelectedDayCardView` 新增 `var compactSummaryOnly: Bool = false`：
  - 紧凑态 = 一行摘要（公历日大数字 + 星期 + 农历月日 + 首个节日 capsule + 天气图标 + 天气文字 + chevron.up），glassCard(radius: 20)；
  - 展开态 = 原完整 VStack。
- 说明：此为首屏压缩的**可选施工方案**（评审标注「需立项决策」），默认收起 + 点按展开，是否保持需真机验收。

### N-10 修正（2026-09-29 用户裁决：取消收起折叠）

**裁决**：首页日期卡片与今日安排**不再收起折叠，始终完整展开**。N-10 的「整卡收起为一行摘要 + 点按展开」方案被否决。

**修改**：
- `SelectedDayCardView.swift`：删除 `compactSummaryOnly` 参数与紧凑分支、删除 `isPanelExpanded` binding；恢复 `huangli`/`todaysEvents` 局部定义（N-10 施工时被误删但完整分支仍引用——潜在编译错误，一并修复）；今日安排**始终完整列出当天全部事件**（删除 `prefix(3)` slice 与「查看全部 N 项 →/收起」按钮），EventRow 固定非紧凑模式；
- `CalendarMonthView.swift`：删除 `isPanelExpanded` 状态与 `.frame(height:64)`/`.contentShape(Rectangle())`/`.onTapGesture` 折叠修饰；底部恢复固定 `.padding(.bottom, 96)`（防 TabBar 遮挡）；
- N-10 保留项：`columnHeight` 测量去 `if isIPadSplit` 限制（iPhone 也实测，属高度适配，非折叠逻辑）。

### N-10 修正之二（2026-09-29 用户反馈：日期上下间距过宽）

**问题**：N-10 让 iPhone 也启用弹性行高（`elasticCellHeight` 去 `isIPadSplit` 守卫，行高上限 96pt）。大屏 iPhone 上 6 行均分被 clamp 到 96pt，格子变高，日期数字与农历/节气文字之间上下留白过大。

**修复**：恢复 `elasticCellHeight` 的 `isIPadSplit` 守卫——仅 iPad 分栏启用弹性行高；iPhone 恢复内容自适应高度（`.frame(height: nil)`），格子高度回到 N-10 前的紧凑值。取消折叠裁决后「选中卡收起填满首屏」的前提已不存在，此改动与当前交互一致。

---

## 三、验证情况

| 验证项 | 结果 |
|---|---|
| Swift 括号配平（10 个改动文件逐文件） | 全部 OK |
| AppTheme 新 token 定义 ↔ 视图层引用 | 9 定义 / 11 引用全部一致 |
| N-9 红线本地复扫（模拟 CI grep） | 0 处命中 |
| ci.yml YAML 语法（python yaml.safe_load） | OK |
| 编译验证（swift build / iOS SDK build） | **未执行**——Linux Cloud VM 无 Swift/Xcode，依赖用户 Mac / GitHub CI（macos-26 runner） |

### 编译警告修复（2026-09-28 21:14，用户 Xcode 截图驱动）

**问题**：`CalendarMonthView.swift:15` 的 `static var defaultValue: CGFloat = 0`（N-3 新增 PreferenceKey）在 Swift 6 严格并发下报「nonisolated global shared mutable state」警告（同一处报 2 条 issues），Build Failed。

**修复**：`static var` → `static let`。PreferenceKey 协议只要求 get-only，`static let` 满足协议且为 Sendable 不可变状态（Xcode 建议方案①，Swift 6 标准写法）。已补注释说明。全仓排查确认其余 `static var` 均为 get-only 计算属性，无同类隐患。

**需真机/模拟器验收项**（代码侧已做，截图待用户）：
1. `qinghe://ai` 深链双端用例（N-1）；
2. 13" 横屏三档节截图（N-2 占位视图）；
3. 四档设备月卡首屏一屏（N-10）；
4. 节日当天横滑性能复测（N-4 缓存）；
5. 快捷键（⌘1-5 / ⌘F / ⌘Return）与 hover 清单（N-6，已建议追加进 `DEVICE_TEST_CHECKLIST.md`）。

---

## 四、后续待办

- [ ] 本批次 20 个文件 commit（建议提交信息：`N-batch: UI design review 2026-09-28 (N-1~N-10)`）；
- [ ] push GitHub（**需用户显式确认**，PAT 验证 200 后原生 push）；
- [ ] 真机走查上述验收项并补截图；
- [ ] `DEVICE_TEST_CHECKLIST.md` 追加 N-6 快捷键/hover 清单。
