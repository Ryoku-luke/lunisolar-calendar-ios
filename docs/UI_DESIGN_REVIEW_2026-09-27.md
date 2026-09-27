# UI 设计评审与打磨施工图纸（2026-09-27）

> 评审视角：资深 iOS UI/UX 设计师；范围：全应用视觉、信息架构、交互、无障碍。
> 基线：代码 HEAD 2026-09-27。评审依据：通读 `Sources/LunisolarCalendarApp/` 全部
> 视图文件 + `Support/AppTheme.swift` / `ColorExtensions.swift` + 对照 `UI_POLISH_REVIEW_2026-09-25.md`。
> 每条给出：问题 → 依据（文件）→ 建议方案 → 验收标准。
> 优先级：**P0 = 影响核心体验，先做；P1 = 体验打磨；P2 = 视觉细节**。
> **施工进度**：批次 0（P1-2 / P1-3 / P1-4）、批次 1（P0-2 / P0-3 / P1-5）与
> 批次 2（P1-1 / P2-1 / P2-2）**已完成 2026-09-27**，其余未动；
> 逐条状态见各条目下的「落地」记录与文末「整体验收清单」。

## 0. 总体结论

| 维度 | 评分（10 分制） | 一句话 |
|---|---|---|
| 设计系统 | 8.5 | Token 化程度高，Dynamic Type / 无障碍实现方式是正确的那种 |
| 信息架构 | 6.0 | 三套并行入口重复，Alert 滥用打断用户 |
| 首屏效率 | 5.5 | 月网格首屏看不全，信息堆叠竞争 |

**主要失分不在"好不好看"，而在入口重复、首屏信息竞争、Alert 滥用三件结构性的事。**

### 值得保留的资产（打磨时不要破坏）

1. `AppTheme` 设计 Token 体系（间距/圆角/阴影/字体/动效单点收敛，阴影 2 档、单层材质原则）。
2. Dynamic Type：UIFontMetrics 缩放 + 计算属性不缓存，字号调整即时生效。
3. 无障碍三件套：Reduce Motion 根视图集中降级、Reduce Transparency 材质替换、Increase Contrast 描边上浮。
4. `EventEditView` 原生 Form + insetGrouped 形态（对齐系统日历/提醒事项）。
5. 节日自适应强调色 + 春节限定图标切换（差异化记忆点）。

---

## P0：影响核心体验（4 项）

### P0-1 月视图首屏信息竞争：完整月网格看不全

- **问题**：首屏自上而下 = 导航栏 + 月份标题（hero 38pt）+ 节气条 + 月卡
  （42 格 × 最小行高 56pt ≈ 340pt+）+ 选中卡。iPhone 上必须滚动才能看全一个月。
  日历类 App 的硬指标是"打开即见整月"。
- **依据**：`CalendarMonthView.swift`（`AppTheme.Font.hero` 38pt、`minCellHeight` 56、
  `monthColumn` 纵向堆叠 `SelectedDayCardView`）。
- **建议方案（二选一，推荐 A）**：
  - **A. 选中卡改底部抽屉/可折叠面板**：月卡固定一屏完整可见；选中卡默认露头部摘要
    （日期 + 农历 + 2 条宜忌），上滑展开完整内容。对齐系统日历的"月 + 日程列表"模式。
  - B. 压缩静态布局：hero 38→28~30、节气条并入选中卡、格子行高 56→48~52。
- **验收**：iPhone SE（375×667）与 iPhone Pro Max 模拟器截图，月网格 42 格完整可见，
  无需滚动；横滑翻月手势不被抽屉冲突。

### ~~P0-2 信息架构收敛：消除重复入口~~ **已完成（2026-09-27，批次 1）**

- **问题**：同一功能存在多套并行路径——
  - 「回到今天」：工具栏"今天"按钮 与 菜单项各一份，功能完全相同；
  - 「倒数日」：iPhone 菜单入口 + iPad 侧栏入口 + 深链入口；
  - 「全部日程 / 设置」：iPhone 菜单入口与 Tab「我的」内容重叠。
- **依据**：`CalendarMonthView.swift` toolbar（leading 今天按钮 + 菜单内"回到今天"）、
  `LunisolarCalendarApp.swift`（`PhoneTabRootView` 4 Tab vs `iPadRootView` 5 节）。
- **建议方案**：
  1. 「回到今天」只留工具栏按钮，菜单里删除；
  2. iPhone 月视图菜单只保留 Tab 没有的「全部日程」「跳转到日期」；
  3. iPad 侧栏已是唯一权威入口，月视图菜单在 iPad 不再重复列出倒数日/设置（现状已
     按 isIPadSplit 分支，复核菜单项与侧栏节一一对应、无遗漏无重复）。
- **验收**：列出全应用功能→入口对照表，每个功能恰好一条主路径（深链除外）；
  UI 测试断言菜单项数量与文案。
- **落地（2026-09-27）**：`Views/CalendarMonthView.swift` 工具栏菜单收口，并新增
  **Flow 8**（iPhone）锁定菜单内容。

  | 入口 | 改前 | 改后 |
  |---|---|---|
  | 回到今天 | 工具栏「今天」按钮 + 菜单项（重复） | 只留工具栏按钮 |
  | 设置（iPhone） | 底部「我的」Tab + 菜单项（重复） | 只留 Tab |
  | 倒数日 / 设置（iPad） | 侧栏 + 菜单项（重复） | 只留侧栏 |
  | 全部日程 / 倒数日（iPhone） | 菜单 | **保留**（见下方偏离说明） |

  ⚠️ **一处对本文原建议的偏离（已按代码事实收窄）**：第 2 条写「只保留 Tab 没有的
  『全部日程』『跳转到日期』」，按字面执行会把**「倒数日」一并删掉**——而 iPhone 上
  `CountdownView` **只有这一个入口**（改动前 `grep -rn 'CountdownView()' Sources/`
  只命中菜单这一处；底部四个 Tab 是 日历/黄历/AI 助手/我的），删掉等于让该功能消失，
  Flow 7 也会随之失败。故 iPhone 菜单**只删「设置」，保留「倒数日」**。

  **功能 → 入口对照表**（每个功能恰好一条主路径，深链作为程序化入口单列）：

  | 功能 | iPhone 主入口 | iPad 主入口 | 程序化入口 |
  |---|---|---|---|
  | 月历 | Tab「日历」 | 侧栏「日历」 | `qinghe://calendar` |
  | 跳到任意日期 | 月历菜单「跳转到日期」（点月标题同效） | 同左 | `qinghe://calendar/date/<yyyy-MM-dd>` |
  | 年视图 | 跳转日期页 →「全年视图」 | 侧栏「年视图」 | — |
  | 黄历（当日详情） | Tab「黄历」 | 侧栏「日历」+ 右栏 Inspector | — |
  | 全部日程 | 月历菜单「全部日程」 | 侧栏「全部日程」 | — |
  | 倒数日 | 月历菜单「倒数日」 | 侧栏「倒数日」（右栏详情列） | `qinghe://countdown/<UUID>` |
  | 事件编辑 | 日期格长按 / 当日安排行 / 工具栏「+」 | 同左 | `qinghe://event/<UUID>` |
  | 新建倒数日 | 倒数日页「+」 / 空态行动按钮 | 同左 | — |
  | 设置 | Tab「我的」 | 侧栏「设置」 | — |
  | 外观 / 图标 / 日历显示 | 设置 → 外观 | 同左 | — |
  | 导入（系统日历 / 联系人 / 文件） | 设置 → 数据与同步 | 同左 | — |
  | iCloud 同步 | 设置 → iCloud | 同左 | — |
  | 帮助等文档 | 设置 → 文档入口 | 同左 | — |
  | AI 助手 | Tab「AI 助手」 | 设置头部卡（**待 P0-3 补侧栏节**） | `qinghe://ai` |
  | 时间胶囊上岛 / 下岛 | 倒数日行内按钮 | 同左 | — |

  > 「回到今天」：工具栏按钮是唯一入口（跳转日期页另有一枚，属该页的快捷操作，不是重复导航）。
  > **iPad 月历菜单改后只剩「跳转到日期」一项**——若 P0-1 裁决走方案 C（年视图移出侧栏），
  > 这里会再添一项「年视图」，故刻意保留 Menu 容器而不是退回单个按钮。

  顺带清掉的**死代码**：`MonthAuxiliaryPage.settings`。它唯一的赋值点就是被删掉的 iPad 菜单项
  （深链路由里没有设置），留着就是一个永远不可达的枚举分支；
  已连同 `MonthSheetsModifier` 里的 `.settings` 分支一并删除
  （与当年删除 `showAIAssistant` 死 sheet 同一处理方式）。

### ~~P0-3 Alert 滥用收口：结果反馈全部走 Toast~~ **已完成（2026-09-27，批次 1）**

- **问题**：全仓 10 处 `.alert`，其中倒数日行内两个 Alert（灵动岛未开启 / 上岛失败），
  点一下行内小按钮就被模态打断两次。项目自己的规范（Toast/Alert 分工）只迁了一半。
- **依据**：`CountdownView.swift`（`showLADeniedAlert` / `showLAFailedAlert`）、
  `UI_POLISH_REVIEW_2026-09-25.md` §5（Toast/Alert 分工"部分统一"）。
- **建议方案**：
  - 结果性反馈（成功 / 失败 / 警告）→ `QingheToast` 或行内状态；
  - `.alert` 只保留真正的不可逆二次确认：删除事件、删除倒数日、清空全部数据、导入冲突策略。
- **验收**：`grep -rn "\.alert(" Sources/` 剩余处逐条核对属于"二次确认"白名单；
  倒数日行的两种失败各有一条 UI 测试断言 Toast 出现。
- **落地（2026-09-27）**：`grep -rn '\.alert(' Sources/` 现为 **4 处，正好是白名单**：
  `SettingsView`（导入冲突策略 / 清空全部）、`AllEventsView`（批量删除）、`EventEditView`（删除事件）。

  **新增的共用基建**（`Views/SettingsViewComponents.swift`）：
  `ToastMessage` 加可选 `actionTitle` / `action`（成员含闭包，故手写 `Equatable`：闭包身份不参与）；
  `ToastBannerView` 渲染行动按钮并挂统一锚点 `state.toast`；把原先内联在 `SettingsView` 里的
  浮层 + 计时抽成 `QingheToastHost` + `.qingheToast(_:)` 供多页共用
  （复制多份必然得到几份不同的计时与动画）。新增锚点 `AccessibilityID.toastAction = "state.toast.action"`。

  **6 处转换**：

  | 位置 | 改法 |
  |---|---|
  | `SettingsView` 导入结果 | 走既有 toast。**顺带修掉一处重复播报**：`handleImportResult` 原先每条分支同时置 `showImportResult = true`（弹模态）与 `toast = ...`，同一件事报两遍——正是报告 §42 禁止的。同时把摘要换成完整的 `importSummaryText`（含「保留本地 N / 无效 N」与冲突提示），删掉模态后这里是用户唯一能看到导入细节的地方。随之删除 `importedResult` / `showImportResult` 与 `importResultAlertMessage` |
  | `AIAssistantView` 无法解析 | 行内 toast，与成功提示同区（新增 `inlineError`，成功/新一轮解析时清空） |
  | `CountdownView` 灵动岛未开启 | 行内 toast，**保留「去设置」行动**（见下方说明） |
  | `CountdownView` 上岛失败 | 行内 toast（错误色），空消息回落为「暂时无法启动实时活动」 |
  | `CountdownEditor` 日期超出支持范围 | 行内 Section 提示（本就是程序级兜底，为它弹模态不划算） |
  | `DateJumpView` 暂不支持该年份 | 行内提示。原 alert 的「回到今天」按钮本页「快捷跳转」区就有一个，删弹窗不损失能力 |

  ⚠️ **一处必须保住的行动**：本文的建议方案只说「→ Toast 或行内状态」，
  若照字面把倒数日那两条做成纯文案 toast，就会**丢掉「去设置」按钮**，而那正是
  `docs/DEVICE_TEST_CHECKLIST.md` §1.2 明确要求的行为（「弹『灵动岛未开启』并给出去设置按钮，
  **不是静默失败**」）。因此：
  1. `ToastMessage` 支持可选行动按钮，带行动的 toast 停留 6 秒（纯文案 2.2 秒）；
  2. 上岛失败的状态从 `CountdownRow` **提升到 `CountdownView`** —— 行本身是
     `.accessibilityElement(children: .combine)`，把按钮塞进行里会点不到；新增
     `IslandProblem` 枚举（`.denied` / `.failed`）+ 回调上报。

  ⚠️ **一条验收项没能做到（如实记录）**：本文写的「倒数日行的两种失败各有一条 UI 测试断言
  Toast 出现」**未实现** —— 触发这两条需要关掉系统「实时活动」总开关或让 ActivityKit 启动失败，
  UI 测试（XCUITest）没有权限改系统开关、也无法稳定制造启动失败。已在
  `DEVICE_TEST_CHECKLIST.md` §1.1 / §1.2 里覆盖（人工），此处不虚报自动化。
  能自动化的部分补在别处：AI 助手的行内错误由 **Flow 3b** 断言（见该用例注释）。

### P0-4 节日 accent 对比度校验：控件色与装饰色分层

- **问题**：`tint(accent)` 把节日 hex 色染到所有按钮/链接/选中态。金色系节日
  （中秋 gold 0.88/0.72/0.35）浅色底上白字主按钮可能不达 WCAG AA（4.5:1）。
- **依据**：`ColorExtensions.swift`（`festiveGold` / `appTint` 定义）、
  `DayDetailView.swift` / `SelectedDayCardView.swift`（accent 直接进
  `PrimaryActionButtonStyle`）。
- **建议方案**：
  1. accent 分两级：**装饰层**（描边、渐变、节日标签、壁纸染色）用节日色；
     **控件层**（主按钮填充、tint）固定 `appTint`，或经对比度校验的节日色变体
     （亮度低于阈值时自动回落 appTint）；
  2. 写一个 `accentForControls(hex:)` 工具集中裁决，替换各页 `tint(accent)` 调用点。
- **验收**：对全部节日 accentHex 跑对比度脚本（浅色/深色各一遍），控件白字 ≥ 4.5:1；
  不达标节日提供截图对比。

---

## P1：体验打磨（5 项）

### ~~P1-1 日详情头部卡超载 → 「更多黄历」改网格/列表~~ **已完成（2026-09-27，批次 2）**

- **问题**：头部卡 = 大数字 + 农历 + 干支生肖 + 节日标签 + 休假标记 + 天气 + 折叠区，
  太重；「更多黄历」展开是 5 列 caption 小格（冲煞/五行/纳音/喜神/财神），
  375pt 屏宽下值文本 `lineLimit(1)` 必然截断。
- **依据**：`DayDetailView.swift` `headerCard` 的 `DisclosureGroup` 5 列 `HStack`。
- **建议方案**：展开区改 **2 列网格**（`LazyVGrid` columns=2）或纵向列表行
  （Label 左 + 值右）；五行纳音等长文本换行显示。
- **验收**：375pt 宽度截图，五个值全部完整可读、无截断；AX5 大字下卡片增高不裁切。
- **落地（2026-09-27）**：`DayDetailView.swift` 的 5 项 `HStack` 换成 **2 列 `LazyVGrid`**
  （列间距与行间距都用 `AppTheme.Spacing.xs`）；去掉 `.lineLimit(1)`——它就是截断的成因——
  改为 `.fixedSize(horizontal: false, vertical: true)` 自然换行 + 文字左对齐。
  375pt 下每项宽度从约 60pt 变成约 165pt，五个值不再被截断；AX5 大字号下靠自然换行
  自动增高、**不裁切**（已无行数上限）。
  ⚠️ **截图验收未做**（375pt 与 iPad 右栏各一张），并入截图批次。

### ~~P1-2 文案 bug：非今天也显示"今天很空闲"~~ **已完成（2026-09-27，批次 0）**

- **问题**：`DayDetailView` 空态写死"今天很空闲"，但该页可被年视图/深链以任意日期打开。
  （选中卡 `SelectedDayCardView` 已改为"这一天很空闲"，日详情漏改。）
- **依据**：`DayDetailView.swift` 空态 `Text("今天很空闲")`。
- **建议方案**：改为"这一天很空闲"（与选中卡同文案）；顺手检查两卡其余文案是否同源。
- **验收**：深链打开非今日日期，空态文案正确；4 语言 .strings 均补齐。
- **落地（2026-09-27）**：`Views/DayDetailView.swift:252` 改用
  `String(localized: "这一天很空闲")`（写法也与选中卡统一）。4 语言 .strings 早已存在该 key，
  **无需新增文案**；两卡其余文案已核对同源。
  ⚠️ **肉眼验收未做**（需深链打开非今日日期看一眼），并入截图批次。

### ~~P1-3 DatePicker 强制中文 locale~~ **已完成（2026-09-27，批次 0）**

- **问题**：`EventEditView` 三处 DatePicker 写死 `Locale(identifier: "zh_Hans_CN")`，
  英文/日文界面冒出中文月份，多语言产品明显破绽。
- **依据**：`EventEditView.swift` `.environment(\.locale, ...)`。
- **建议方案**：去掉硬编码 locale，跟随系统（默认行为即可）；如必须为公历
  固定 `gregorian` calendar，locale 仍应取 `.current`。
- **验收**：系统语言切英文/日文，编辑页日期选择器月份与界面语言一致。
- **落地（2026-09-27）**：**范围比本文更大——全仓实为 9 处，不是 3 处**，已一次清完：
  `EventEditView.swift`（本文所列 3 处）、`CalendarMonthGridBuilder.swift`（复制日期的长格式）、
  `CountdownView.swift`（倒数日行 + 倒数日编辑器的 DatePicker）、`AllEventsView.swift`（全部日程组头）、
  `CountdownDetailView.swift`（iPad 右栏，即 iPad 文档的同族项），以及排查中发现的第 9 处
  `Services/AICommandValidator.swift:127`（AI 助手「已经过去了」报错里嵌的日期，**用户可见**，
  两份文档都漏了）。一律改为跟随界面语言（默认 `.autoupdatingCurrent`）。
  保留 3 处**解析用**硬编码，有意不动：`DataPortability.swift`、`YearOverviewView.swift`
  （`en_US_POSIX`）、`CalendarEvent.swift`（`zh_CN_POSIX` + 显式 `dateFormat = "yyyy/M/d"`，
  格式与语言无关）。
  ⚠️ **4 语言截图抽查未做**——这是本批唯一的必做回归，并入截图批次。

### ~~P1-4 翻月箭头颜色与主题色脱节~~ **已完成（2026-09-27，批次 0）**

- **问题**：`chevronButton` 硬编码 `Color.systemBlue`，春节期间全 App 染红、
  唯独翻月按钮蓝色。
- **依据**：`CalendarMonthView.swift` `chevronButton`。
- **建议方案**：改 `foregroundStyle(accent)`，由调用处透传（`monthHeader` 已持有 accent）。
- **验收**：春节前后截图对比，翻月箭头与工具栏 tint 同色。
- **落地（2026-09-27）**：`monthHeader(accent:)` / `chevronButton(_:accent:)` 增加 `accent` 参数，
  颜色改 `foregroundStyle(accent)`。箭头与工具栏 tint 现在**同源**（都由 `accentColorForToday`
  透传），"同色"由构造保证。
  **副作用（本批唯一一处视觉变更）**：普通日不再是 `systemBlue`(#007AFF) 而是
  `appTint`(#3D63DE，深色模式自动提亮)，蓝色略深；且 `appTint` 是固定色值，
  **不随「增强对比度」自动加深**（`systemBlue` 会）。按 WCAG 相对亮度粗算 appTint 对白底约 5:1，
  仍过 AA 4.5:1——**该数字未用工具核验**，建议并入 P0-4 的对比度脚本一起跑。
  ⚠️ **春节前后截图对比未做**，并入截图批次。

### ~~P1-5 倒数日页双 sheet 并存 → 枚举收口~~ **已完成（2026-09-27，批次 1）**

- **问题**：`.sheet(isPresented: $showingEditor)` 与 `.sheet(item: $editingEvent)` 弹同一
  编辑器，状态不同步时可能互相顶掉。月视图已用 `MonthEventEditSheet` 枚举解决过同类
  问题，这里漏了。
- **依据**：`CountdownView.swift` 两个 `.sheet`。
- **建议方案**：合并为单一枚举（`.new` / `.existing(event)`）+ 一个 `.sheet(item:)`。
- **验收**：连续快速点"新建"→ 取消 → 点行，编辑器行为正确无残留；
  UI 测试锚点不变。
- **落地（2026-09-27）**：新增 `CountdownEditorTarget` 枚举（`.new` / `.existing(CountdownEvent)`，
  `event` 计算属性给出 `CountdownEvent?`），两个 `.sheet` 合并为一个 `.sheet(item:)`；
  `showingEditor` / `editingEvent` 两个并行状态删除，4 处赋值点
  （空态行动按钮、行点击、工具栏「+」）统一改为写 `editorTarget`。
  「同一时刻至多一类目标」现在由结构保证，不再依赖状态同步。
  ⚠️ **手测未做**：「连续快速点新建→取消→点行」这条人工回归没跑（UI 测试只覆盖到
  「空态行动按钮能打开编辑器」，Flow 7），已记入下方验收清单。

---

## P2：视觉细节（3 项）

### ~~P2-1 Token 收编不彻底~~ **已完成（2026-09-27，批次 2，按「收编或记录豁免」结案）**

- 现状：23 处 `font(.system(size:`、15 处非 Token 圆角、散点 padding
  （如倒数日行 `padding(.horizontal, 7)`）；`CountdownRow` 注释声称用 Token
  实际仍硬编码 30pt。
- **建议**：自定义 SwiftLint 规则（或 grep 清单）把 `AppTheme` 之外的
  字号/圆角/padding 全部标出，逐条收编或记录例外理由；Widget 目标内 ≤14pt 紧凑值
  可作为白名单。
- **验收**：grep 清单清零或全部有注释豁免。
- **落地（2026-09-27）**：三类逐条给结论，且**「豁免的理由」写进了代码注释**
  （`AppTheme.Font` / `AppTheme.Spacing`），不只躺在文档里。

  **① 圆角：15 处收编 12 处。** 字面值恰好等于阶梯值的直接换 Token（**零视觉变化**）：
  `QingheUIComponents` 12×2→`Radius.md`、20×2→`Radius.xl`；`CountdownView` 8→`Radius.sm`；
  `CalendarMonthView` 24×2→`Radius.xxl`；`QingheLiveActivity` 12→`md`、8→`sm`；
  `CountdownActivity` 12→`md`、8→`sm`。`TagCloudView` 6→`Radius.sm`(8) 是本批
  **唯一的 +2pt 真实变化**。剩 3 处列白名单（`QingheLiveActivity` 7、
  `CountdownActivity` 7、`LunisolarWidgetViews` 6）——小组件刻意紧凑。
  验证：`grep -rn 'cornerRadius: [0-9]' Sources/ | grep -v AppTheme.Radius` 只剩这 3 处。

  **② 字号：23 处里只有 2 处是真正的文字排版。** 已收编：
  `QingheUIComponents` 品牌名 19/bold/rounded → `AppTheme.Font.title3`（18 semibold）、
  区块标题 13/semibold/rounded → `AppTheme.Font.subheadline`（13 medium）。
  其余 **21 处是逐条分类后的豁免**（不是遗漏）：

  | 类别 | 处数 | 代表位置 | 为什么不走阶梯 |
  |---|---|---|---|
  | SF Symbol 字形字号 | 12 | 工具栏 `+` 17、sparkles 22/24、天气字形 32、toast 图标 16、复选框 18/24 | 图标是在固定方框内定尺寸的**字形**，不是排版；`Font` 阶梯是给文字的 |
  | 固定方框内的 emoji | 3 | 倒数日 emoji 30、emoji 选择器 28、右栏 emoji 40 | 同上；且 `numeralXL` 是 56，塞进 48×48 方框会溢出 |
  | 固定密度迷你网格 | 6 | 年视图迷你月标题 13 / 星期头 8 / 日期数字 9.5·8.5 / 标记 6.5；月历星期头 9·8 | 字号由格子宽度定，跟随 Dynamic Type 会撑破网格 |

  **③ padding：28 处字面值，按清单记豁免。** 其中约 16 处是「值本来合法、只是写成了字面量」
  （8/12/16/24），属纯清洁、零视觉收益，**未在本批一并扫**；其余为三类真豁免：
  固定密度迷你网格的 6/4pt 档、与 UIKit 逐点对齐的偏移（AI 输入框 `.padding(.top, 12)`
  对齐 `UITextView.textContainerInset`，换 Token 会错位）、结构性留白
  （月历底部 96pt 留给悬浮工具条、标题基线 6pt）。

  **④ 顺手修掉一处「Token 自身违规」**：`AppTheme.Spacing.xxl` **28 → 32**。
  28 不在设计纪律的允许清单（4/8/12/16/20/24/32）内——与批次 0 修的
  `Radius.xl` 22→20 是**同一类问题**：「用了 Token」不等于「合规」。
  影响 4 处调用点（空态内边距 ×2、日详情宽版横向内边距、一处撑高占位），均为 +4pt。

  ⚠️ 本批共 **4 类真实视觉微调需肉眼过目**：`TagCloudView` 圆角 6→8、品牌名 19→18 semibold、
  区块标题 semibold→medium、`Spacing.xxl` 28→32 的 4 处。
  📌 **可选的后续**：若希望图标字号也纳入 Token，可给 `AppTheme` 加一条 `Icon` 阶梯
  （如 16/20/24/32）——那是设计系统的扩展，不在本批范围。

### ~~P2-2 月历红色层级过多~~ **已完成（2026-09-27，批次 2）**

- 现状：周末红（0.65 透明度）+ 今日红 + 节日红 + 休/班徽章红橙，旺季整月一片红，
  "红"的语义被稀释。
- **建议**：周末降为 `Color.secondaryLabel.opacity(0.8)`，把红色语义只保留给
  「今天」和「节日」；休/班徽章维持绿/橙不变。
- **验收**：含春节的月份截图，周末格与其他格明显拉开层级。
- **落地（2026-09-27）**：**改的是两处，不是本文只写的那一处。**
  1. `CalendarComponents.swift` `WeekHeaderView` 星期表头：0.65 红 → `secondaryLabel.opacity(0.8)`；
  2. `CalendarComponents.swift` `DayCellView.foregroundForDay`：周末 0.78 红 →
     `secondaryLabel.opacity(0.8)`。**本文没提到这一处，但它才是「整月一片红」的主因**
     —— 42 个格子的日期数字，而表头只有 7 个字符。发现经过：本批只按本文改了第 1 处后，
     排查确认格子另有独立的一套周末红（`:250`），已一并处理。
  红色语义现只保留给「今天」（`foregroundForDay` 的 `isToday`、今日描边）与「节日」
  （`festivalTint`）；休 / 班徽章的绿 / 橙未动。

  ⚠️ **一个需要你拍板的副作用**：星期表头的周末与工作日现在是 `0.8` vs `0.85` ——
  **肉眼基本看不出差别**，等于把「周末」这个提示从表头拿掉了（这是本文方案的字面结果）。
  周内提示现在只靠日期格「周末比工作日略淡」。两个可选方向：
  （a）表头周末再淡一点（如 0.6）做出可见差异；（b）表头不再区分周末，提示完全交给格子。
  ⚠️ 截图验收未做（含春节的月份），并入截图批次。

### P2-3 「黄历」Tab 与选中卡内容分工

- 现状：两边都展示农历、宜忌、当日安排，大面积重复，用户不知道哪边是权威。
- **建议**：明确分工——选中卡做"摘要 + 入口"（日期/农历/前几条宜忌/事件数），
  「黄历」Tab 做完整版（冲煞/五行/纳音/神位/全部宜忌只放这里）；
  远期可考虑 AI 助手降为入口按钮（黄历升至 Tab），减少一个 Tab。
- **验收**：两张截图对照，选中卡不再有完整宜忌列表，信息不重复。

---

## 施工顺序建议

| 序 | 事项 | 预估 | 依赖 |
|---|---|---|---|
| ~~1~~ | ~~P0-3 Alert→Toast 收口~~ → **已完成（批次 1）** | 0.5 天 | 保留 4 处白名单；倒数日两处保住了「去设置」行动 |
| ~~2~~ | ~~P1-2 / P1-4 / P1-5 三个小修复~~ → **全部完成（P1-2/P1-4 批次 0；P1-5 批次 1）** | 0.5 天 | 无 |
| ~~3~~ | ~~P0-2 入口收敛~~ → **已完成（批次 1）** | 0.5 天 | 无 |
| ~~4~~ | ~~P1-3 DatePicker locale~~ → **已完成（批次 0，实际清了 9 处）** | 0.5 天 | ⚠️ 4 语言截图回归仍待做 |
| 5 | P0-4 accent 对比度分层 | 1 天 | 需逐节日核对色值；批次 0 新引入的 `appTint` 一并核 |
| 6 | P0-1 选中卡抽屉化 | 2~3 天 | 手势冲突处理，工作量最大 |
| ~~7~~ | ~~P1-1 / P2-1~3 视觉细节批~~ → **P1-1 / P2-1 / P2-2 已完成（批次 2）；P2-3 待你决策** | 1~2 天 | P2-3 =「黄历 Tab 与选中卡分工」，属产品决策 |

## 整体验收清单

> **批次 0（2026-09-27）**：P1-2 / P1-3 / P1-4（8 个文件）。
> **批次 1（2026-09-27）**：P0-2 / P0-3 / P1-5 —— 新增 **Flow 8**（菜单入口收敛），
> **Flow 3 / 3b** 的「必须有反应」断言放宽为「预览 / 行内 toast / 旧 alert」三选一
> （Flow 3 在首次全量回归时**确实红了一次**，成因就是只改了 3b、漏改 3；已修并复验）。
> **批次 2（2026-09-27）**：P1-1 / P2-1 / P2-2 —— 「更多黄历」2 列网格、Token 收编
> （圆角 12 处 + 字号 2 处 + `Spacing.xxl` 28→32）、周末红改中性色（**两处**，其中一处
> 是本文漏写的日期格）。
> 三批验证均为：`swift test` 310 条全绿、iOS SDK 构建通过、iPhone 17 Pro 与
> iPad Pro 11" 双端 UI 测试 0 失败。

**已达标**（详情见各条目的「落地」记录）：

- `grep` 清单的 **alert** → 4 处白名单（批次 1）
- `grep` 清单的**非 Token cornerRadius** → 只剩 3 处 Widgets 白名单（批次 2）
- `grep` 清单的 **`font(.system(size:`** → 21 处为分类豁免（批次 2，理由见 P2-1 的对照表）
- **功能→入口对照表** → 已产出（P0-2 落地节）。
  （遗留一问：iPad 菜单只剩「跳转到日期」而月标题点击同效——是否整个菜单都该删，
  待 P0-1 落地时一并定，已记在 P2-1 落地与 iPad 文档的 P0-1 裁决节。）

**仍未做**：

- [ ] iPhone SE / Pro Max / iPad 三档截图走查（浅色 + 深色 + AX5 大字各一遍）
- [ ] 全部节日 accent 对比度报告（浅色/深色，≥4.5:1）——批次 0 新引入的 `appTint` 一并核
- [ ] 4 语言（简/繁/日/英）界面截图抽查一轮 ← **批次 0 的必做回归**
- [ ] 真机过一遍 `DEVICE_TEST_CHECKLIST.md` 中的视觉项
- [ ] **批次 0 / 2 的视觉微调**（都只有肉眼能验，建议与真机项一次过完）：
      ① 翻月箭头普通日配色（`systemBlue` → `appTint`：略深，且不随「增强对比度」自动加深）；
      ② `TagCloudView` 圆角 6→8；③ 品牌名 19→18 semibold；④ 区块标题 semibold→medium；
      ⑤ `Spacing.xxl` 28→32 的 4 处；
      ⑥ 「更多黄历」2 列网格在 375pt 与 iPad 右栏下五个值完整可读、AX5 不裁切
- [ ] **批次 1 的人工项**：
      ① 导入结果**只播报一次**（行内 toast；摘要含「保留本地 N / 无效 N」与冲突提示）；
      ② 倒数日「灵动岛未开启」的 toast 上**「去设置」可点且能跳到系统设置**，
      「上岛失败」原样显示错误原文；
      ③ 倒数日编辑器「快速点新建 → 取消 → 点行」无残留；
      ④ 跳转日期越界 → 行内提示出现，点「快捷跳转」里的「回到今天」能返回
- [ ] **批次 2 的一个待拍板项**：星期表头的周末与工作日现在是 `0.8` vs `0.85`，
      **肉眼基本看不出差别**（等于把「周末」提示从表头拿掉，这是本文方案的字面结果）。
      看含春节的月份截图时请一并定：（a）表头周末再淡一点做出可见差异，
      （b）表头不再区分周末、提示完全交给日期格
