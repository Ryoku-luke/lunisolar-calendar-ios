# UI 设计评审与打磨施工图纸（2026-09-27）

> 评审视角：资深 iOS UI/UX 设计师；范围：全应用视觉、信息架构、交互、无障碍。
> 基线：代码 HEAD 2026-09-27。评审依据：通读 `Sources/LunisolarCalendarApp/` 全部
> 视图文件 + `Support/AppTheme.swift` / `ColorExtensions.swift` + 对照 `UI_POLISH_REVIEW_2026-09-25.md`。
> 每条给出：问题 → 依据（文件）→ 建议方案 → 验收标准。
> 优先级：**P0 = 影响核心体验，先做；P1 = 体验打磨；P2 = 视觉细节**。
> **施工进度**：批次 0（P1-2 / P1-3 / P1-4）**已完成 2026-09-27**，其余未动；
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

### P0-2 信息架构收敛：消除重复入口

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

### P0-3 Alert 滥用收口：结果反馈全部走 Toast

- **问题**：全仓 10 处 `.alert`，其中倒数日行内两个 Alert（灵动岛未开启 / 上岛失败），
  点一下行内小按钮就被模态打断两次。项目自己的规范（Toast/Alert 分工）只迁了一半。
- **依据**：`CountdownView.swift`（`showLADeniedAlert` / `showLAFailedAlert`）、
  `UI_POLISH_REVIEW_2026-09-25.md` §5（Toast/Alert 分工"部分统一"）。
- **建议方案**：
  - 结果性反馈（成功 / 失败 / 警告）→ `QingheToast` 或行内状态；
  - `.alert` 只保留真正的不可逆二次确认：删除事件、删除倒数日、清空全部数据、导入冲突策略。
- **验收**：`grep -rn "\.alert(" Sources/` 剩余处逐条核对属于"二次确认"白名单；
  倒数日行的两种失败各有一条 UI 测试断言 Toast 出现。

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

### P1-1 日详情头部卡超载 → 「更多黄历」改网格/列表

- **问题**：头部卡 = 大数字 + 农历 + 干支生肖 + 节日标签 + 休假标记 + 天气 + 折叠区，
  太重；「更多黄历」展开是 5 列 caption 小格（冲煞/五行/纳音/喜神/财神），
  375pt 屏宽下值文本 `lineLimit(1)` 必然截断。
- **依据**：`DayDetailView.swift` `headerCard` 的 `DisclosureGroup` 5 列 `HStack`。
- **建议方案**：展开区改 **2 列网格**（`LazyVGrid` columns=2）或纵向列表行
  （Label 左 + 值右）；五行纳音等长文本换行显示。
- **验收**：375pt 宽度截图，五个值全部完整可读、无截断；AX5 大字下卡片增高不裁切。

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

### P1-5 倒数日页双 sheet 并存 → 枚举收口

- **问题**：`.sheet(isPresented: $showingEditor)` 与 `.sheet(item: $editingEvent)` 弹同一
  编辑器，状态不同步时可能互相顶掉。月视图已用 `MonthEventEditSheet` 枚举解决过同类
  问题，这里漏了。
- **依据**：`CountdownView.swift` 两个 `.sheet`。
- **建议方案**：合并为单一枚举（`.new` / `.existing(event)`）+ 一个 `.sheet(item:)`。
- **验收**：连续快速点"新建"→ 取消 → 点行，编辑器行为正确无残留；
  UI 测试锚点不变。

---

## P2：视觉细节（3 项）

### P2-1 Token 收编不彻底

- 现状：23 处 `font(.system(size:`、15 处非 Token 圆角、散点 padding
  （如倒数日行 `padding(.horizontal, 7)`）；`CountdownRow` 注释声称用 Token
  实际仍硬编码 30pt。
- **建议**：自定义 SwiftLint 规则（或 grep 清单）把 `AppTheme` 之外的
  字号/圆角/padding 全部标出，逐条收编或记录例外理由；Widget 目标内 ≤14pt 紧凑值
  可作为白名单。
- **验收**：grep 清单清零或全部有注释豁免。

### P2-2 月历红色层级过多

- 现状：周末红（0.65 透明度）+ 今日红 + 节日红 + 休/班徽章红橙，旺季整月一片红，
  "红"的语义被稀释。
- **建议**：周末降为 `Color.secondaryLabel.opacity(0.8)`，把红色语义只保留给
  「今天」和「节日」；休/班徽章维持绿/橙不变。
- **验收**：含春节的月份截图，周末格与其他格明显拉开层级。

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
| 1 | P0-3 Alert→Toast 收口 | 0.5 天 | 无（组件已存在） |
| ~~2~~ | ~~P1-2 / P1-4 / P1-5 三个小修复~~ → **P1-2、P1-4 已完成（批次 0）；P1-5 待做** | 0.5 天 | 无 |
| 3 | P0-2 入口收敛 | 0.5 天 | 无 |
| ~~4~~ | ~~P1-3 DatePicker locale~~ → **已完成（批次 0，实际清了 9 处）** | 0.5 天 | ⚠️ 4 语言截图回归仍待做 |
| 5 | P0-4 accent 对比度分层 | 1 天 | 需逐节日核对色值；批次 0 新引入的 `appTint` 一并核 |
| 6 | P0-1 选中卡抽屉化 | 2~3 天 | 手势冲突处理，工作量最大 |
| 7 | P1-1 / P2-1~3 视觉细节批 | 1~2 天 | 可在 6 之后顺手做 |

## 整体验收清单

> **批次 0 落地状态（2026-09-27）**：P1-2 / P1-3 / P1-4 三项**代码改动已完成**（8 个文件）；
> 验证为 `swift test` 310 条全绿、iOS SDK 构建通过、iPhone 17 Pro 7 过 1 跳、
> iPad Pro 11" 4 过 4 跳、**双端 UI 测试 0 失败**。
> **下列七条验收项一条都还没做**——包括本批唯一的必做回归（第 5 条的 4 语言截图抽查）。

- [ ] iPhone SE / Pro Max / iPad 三档截图走查（浅色 + 深色 + AX5 大字各一遍）
- [ ] `grep` 三项硬编码清单（alert / system(size / 非 Token cornerRadius）清零或有豁免
- [ ] 功能→入口对照表无重复路径
- [ ] 全部节日 accent 对比度报告（浅色/深色，≥4.5:1）
- [ ] 4 语言（简/繁/日/英）界面截图抽查一轮 ← **批次 0 的必做回归**
- [ ] UI 测试全绿（Flow 1–7 + 新增 Toast/入口断言）← Flow 1–7 已绿；新增断言待批次 1
- [ ] 真机过一遍 `DEVICE_TEST_CHECKLIST.md` 中的视觉项
