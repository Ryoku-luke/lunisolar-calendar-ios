# UI 打磨进度审查（对照《UI 整体界面打磨总报告 2026-09-22》）

> 基线：代码 HEAD `07a3178`（2026-09-25）。审查方式：把该报告的每条 UI 条目拿回代码里核对，
> 能数的地方给数字，不能数的说明原因。**数字均为本次实测**，不是沿用报告里的旧值。

## 0. 一句话结论

**设计系统纪律是做得最好的部分，结构性重构是最大的欠账。**

- 报告 §3 的设计 Token 纪律（圆角/间距/颜色/字体）已经基本落实，违规项是个位数；
- 但报告点名的两处「必须优先整改」的大文件**一件都没拆**，首页还堆着 6 个 sheet；
- 「三态（Loading/Empty/Error）+ 统一状态组件」**基本空白**（统一组件 0 个、骨架屏 0 处），
  而报告 §54 要求 9 个 Feature × 7 种状态全部有表现。

另需注意一处**术语歧义**：路线图的 P0（架构收口）已完成，而 UI 报告的 P0（拆 View、收敛卡片、
减少首页竞争）不是同一件事——下文的 P0 一律指 **UI 报告的 P0**。

## 1. UI 报告 P0（§51「必须优先整改」）——2/5 完成

| 条目 | 状态 | 证据（本次实测） |
|---|---|---|
| P0-1 `CalendarMonthView` 过大，必须拆 | **未做** | 现 **725 行**（报告基线 877 行——瘦了 152 行，来自此前抽走 `SelectedDayCardView` 等，但仍是最大 View 之一；报告要求的 7 个子块一个都还没独立成文件） |
| P0-2 iPad Detail 需 context-aware | **未做，且方向相反** | `LunisolarCalendarApp.swift:181-183` 明确让右栏**在所有节下常驻** `DayDetailView`（当初为消除留白）。与报告 §33/§36 冲突，也与我上一轮列出的裁决项 A 是同一件事 |
| P0-3 主日历移除 AI Banner | **已完成** | 全仓 grep `aiAssistantBanner` / `QinghePhoneAIChip` 均为 0 处 |
| P0-4 Card primitive 收敛到 2~3 个 | **基本完成** | `AppTheme.swift` 里 `modernCard` 0 处、`liquidCard` 0 处、`pageBackground` 0 处；剩 `glassCard` 1 处、`softChipBackground` 2 处 |
| P0-5 `SettingsView` Feature 化 | **未做** | 现 **790 行**（报告基线 759 行——**反而胖了 31 行**）。报告要求的 8 个子页一个都没拆 |

## 2. UI 报告 P1（§52 交互精修 10 条）——6/10 完成

| 条目 | 状态 | 证据 |
|---|---|---|
| 日期长按菜单 | **已完成** | `CalendarMonthView` 日期格挂 `.contextMenu`（长按快捷操作） |
| 日程快速新增 | **已完成** | 工具栏「+」（`calendar.month.new`）+ 今日安排卡的「新建日程」入口 |
| 事件列表快速完成 | **已完成** | `EventRow.showsCompleteToggle`；全部日程另有批量「完成 N 项」（幂等，见提交 `1158ed0`） |
| 日程详情 Deep Link | **已完成** | `qinghe://event/<UUID>` → 跳月 + 打开编辑页（`CalendarMonthView` 消费 `pendingOpenEventID`） |
| AI 创建确认 | **已完成** | 解析 → 预览（标题/类型/时间）→ 确认创建；删除/修改走二次确认 |
| iPad Inspector | **阻塞** | 依赖 P0-2 的裁决，见 §1 |
| Widget 点击路径 | **已完成** | `qinghe://calendar` / `event/<UUID>` / `countdown/<UUID>` 三路皆已接 |
| Live Activity 点击路径 | **已完成** | 锁屏与灵动岛各区域的 `widgetURL` 均带 eventID / countdownID |
| 设置变化即时反馈 | **基本完成** | 7 个 `@AppStorage` 直接驱动 UI：外观、周起始日、三个日历显示开关、时间胶囊开关、联系人生日按农历 |
| 空状态 / 错误状态 | **部分** | 空态 `ContentUnavailableView` 仅 **2 处**、加载态 `ProgressView` **4 处**、错误态多为就地重试（天气卡）。没有统一组件 |

## 3. UI 报告 P2（§53 视觉精修 9 条）——报告自己写明「P2 不得早于 P0/P1」

按报告定的规则，P2 本来就不该先做；这里只给现状，不作为欠账：
字体/阴影/圆角/颜色/材质/节日 accent/**dark mode**/seasonal icon/动画。
其中 dark mode 与 seasonal icon 已可用（9 套图标 + 浅深色适配），其余属于「没有系统性返工」的状态。

## 4. 设计系统纪律（报告 §3.1–§3.4）——**最好的部分**，附实测数字

| 纪律 | 要求 | 实测 |
|---|---|---|
| §3.2 圆角 | 只用 8/12/16/20/24/999 | **违规仅 2 处**（`cornerRadius: 14` ×1、`cornerRadius: 22` ×1）。⚠️ 但**Token 本身与这条纪律矛盾**：`AppTheme.Radius.xl = 22`、`xxl = 28`，都在这条允许清单之外——也就是说「用 Token」并不等于「合规」 |
| §3.3 Spacing | 只用 4/8/12/16/20/24/32 | **违规 8 处**（6 ×4、10 ×2、14 ×2）；18/22/28 已清零 |
| §3.4 字体 | 正文用系统字体，仅数字/标题保留圆体 | `.rounded` 共 25 处，`AppTheme.Font` 内 2 处定义；抽查多为数字与标题，符合意图 |
| 颜色 | 收敛到 Token | 硬编码 `Color(red:…)` **11 处**（多为 Live Activity 的 keyline 品牌色，属合理例外） |
| Dynamic Type | 大字号不裁切 | **已实现且实现得对**：`AppTheme.Font` 走 `UIFontMetrics(forTextStyle:).scaledFont(for:)`（`AppTheme.swift:69`），且自 `5283a5f` 起改为计算属性，切换字号即时生效 |

一句话：**报告当初担心的「散落颜色/圆角/padding/字体」并没有成为事实**，这块几乎不需要返工。

## 5. 三态与组件化（§41 / §42 / §50 / §54）——本轮已动工

> **2026-09-25 第二批更新**：新增统一状态组件 `Views/QingheStateViews.swift`
> （`QingheSkeletonBlock` / `QingheEmptyView` / `QingheErrorView` / `QingheToast`），
> 并接进 4 处真实界面。下表是**更新后**的状态。

| 要求 | 现状 |
|---|---|
| §37 统一状态组件 | **已建立**：`QingheEmptyView`（四要素）/ `QingheErrorView`（三问 + 重试，另提供 `.compact` 紧凑排版）/ `QingheToast` / `QingheSkeletonBlock`。**刻意没有做「页面级骨架屏」**——本 App 数据是同步的，全仓三处 `ProgressView` 都是「按钮旁正在执行」的行内指示，套骨架屏是错的；没有消费者的组合件只会变死代码（理由写在文件注释里） |
| §41 Empty 四要素 | **已落地**：倒数日空态（加「新建倒数日」按钮）、全部日程空态（加「清除筛选」按钮）。此前两处都是 `ContentUnavailableView`，缺第四项 |
| §41 Loading 用骨架屏 | **部分落地**：天气卡的加载态从 `ProgressView` 改成骨架块，且骨架呼吸动画在「减弱动态效果」开启时关闭（顺带补上 §44 的一个缺口）。页面级 Loading 对本 App 基本 N/A |
| §41 Error 三问 + 重试 | **已落地**：天气卡的「定位未开启」（去设置）与「加载失败」（重试）改用 `QingheErrorView(.compact)`；原先的 `compactStatusRow` 私有实现已删除 |
| §42 Toast/Alert 分工 | **部分统一**：AI 助手的行内成功提示改用 `QingheToast`。其余页仍混用 `.alert(`（10 处） |
| §50 `UI/` 目录六组组件 | 仍未建目录；组件放在 `Views/` 下（`QingheStateViews` / `QingheUIComponents` / `SettingsViewComponents` / `CalendarComponents` / `EventRow`） |
| §54 成品级状态矩阵（9 Feature × 7 状态） | 仍**无法逐格评估**；但空态/错误态现在有了统一断言锚点（`state.empty` / `state.error` / `state.toast`），可以逐页补齐 |
| §74 禁止「大量 .sheet 堆叠导航」 | **仍触犯**：`CalendarMonthView` 单文件 **6 个 `.sheet(`**；全仓 14 个 `.sheet` vs 11 个 `NavigationLink/navigationDestination` |

## 5.1 本轮新发现的两个真问题（都需要修）

| # | 问题 | 证据 | 严重度 |
|---|---|---|---|
| 1 | **「全部日程」搜不了**：`.searchable` 在 iOS 26 上不渲染任何搜索入口 | UI 测试实测：整棵无障碍树里**没有 SearchField**（日志里 24 次 `SearchField` 全是测试自身的查询），下拉列表也不出现；把 `.searchable` 与 `.navigationTitle` 调换顺序**同样无效**（已 A/B 验证，故顺序不是成因）。`AllEventsView.swift` 的 `.searchable` 处已写明该问题 | **高**（功能不可用，不只是打磨） |
| 2 | **`AppTheme.Radius` Token 与 §3.2 的圆角纪律矛盾**：`xl = 22`、`xxl = 28` 都在报告禁止的清单里（报告要求 8/12/16/20/24/999） | `Support/AppTheme.swift` 的 Radius 定义 | 中（改 Token 值会小幅改动全站圆角，属视觉变更，需单独一步） |

## 6. 无障碍（§44）——有对有缺

| 项 | 实测 |
|---|---|
| Dynamic Type | ✅ 已做且做对（见 §4） |
| 44pt 触点 | 部分：`touchTarget` **6 处** |
| VoiceOver 标签 | **13 处** `accessibilityLabel`，对 21 个 View 文件来说偏薄；日期格已合并朗读（好） |
| Reduce Motion / Reduce Transparency | ❌ **0 处**（`reduceMotion` 全仓无匹配）——动画（月翻页 Spring、选中回弹、卡片过渡）在开启「减弱动态效果」后不会降级 |
| 高对比度 / 深色模式 | 深色模式已适配；高对比度未处理 |

## 7. 验收能力（§54 / §55 / §61）——从 0 到「一小块」

报告要求「完成 UI 打磨后，不能只看截图」，必须测 §55 的五条真实用户路径。
本轮之前这件事**一条都没跑过**（连 UI 测试 target 都不存在）。现状：

| 路径 | 自动化 | 说明 |
|---|---|---|
| ①打开→今天→点日期→看农历/黄历/天气 | ✅ Flow 1 | 断言选中态唯一 + 选中日摘要卡出现 |
| ②点日期→新建日程→保存→回日历出现 | ✅ Flow 2 | 端到端 |
| ③AI 输入→解析→确认→创建→通知 | 部分 ✅ Flow 3/3b | 已覆盖解析与确认交互；**通知能否真的响**没覆盖 |
| ④iPad→日历→点日期→Detail 更新→Inspector | 部分 ✅ Flow 4 | 覆盖侧栏切节与日期格可点；**右栏语义未定，刻意不断言** |
| ⑤设置→iCloud→开启→同步→成功状态 | ✅ Flow 5 | 只断言「状态明确」，真同步需真机 + iCloud 账号 |
| ⑥全部日程空态是统一组件且可行动 | ✅ Flow 6 | 用类型筛选造空态，断言 `state.empty` + 「清除筛选」按钮生效。**但依赖环境**：容器里若提醒/记事都有数据，该用例会明确跳过（当前就是跳过状态） |

### 7.1 结构性缺口：UI 测试没有数据隔离（建议作为下一步）

Flow 6 的跳过暴露了一个通用问题：**UI 测试跑在用户的真实容器上**，
凡是「空数据才能成立」的断言都不稳定——本轮它跳过，就是因为容器里提醒与记事都有内容
（这些数据来自你我在模拟器上的历次操作）。

仓库里其实已经有注入点：`EventStore.init(storageBaseDir:)` 与 `CountdownStore.init(storageBaseDir:)`
都支持临时目录。但 UI 测试拿不到那个入口——`AppRootView` 固定用 `EventStore.shared` /
`CountdownStore.shared`。

建议的修法（**只动宿主，不动 EventStore / 同步逻辑**）：

1. `AppRootView` 增加可注入构造：`public init(store: EventStore = .shared, countdownStore: CountdownStore = .shared)`；
2. `LunisolarHostApp/HostApp.swift` 里判断启动参数：带 `-uitest-empty-store` 时用
   `FileManager.temporaryDirectory` 下的临时目录构造 store，否则维持现状；
3. UI 测试在 `launchArguments` 里带上该参数 → 每次跑都是干净空库。

收益：所有「空态 / 首次使用 / 无数据」类断言都变成确定性的，§54 的 9×7 矩阵才走得通。
风险：`AppRootView` 的构造签名是**加默认值的增量改动**，现有调用点（只有 HostApp）不受影响；
不碰 EventStore 的内部逻辑，也不碰 CloudKit。


§61 的四组完成定义（视觉 6 / 交互 7 / 应用层 5 / 成品体验 10）**仍然全空**，
且其中「Loading/Empty/Error」「Accessibility」「Reduce Motion」几条**代码里就没有实现**，
不是「没测」而是「没做」。

## 8. 报告里已过期或与代码不符的地方

1. §1 基线行数：`CalendarMonthView` 877 → 现 **725**；`SettingsView` 759 → 现 **790**（一瘦一胖）。
2. §51-P0-3「主日历仍有 AI Banner」——**已移除**。
3. §51-P0-4「四个 Card primitive 并存」——已收敛到剩 2 个。
4. §52 的 10 条交互精修里，6 条已完成（见 §2），报告把它们全部列为待做。
5. §44 说 Dynamic Type 需支持——已实现且实现方式是正确的那种（UIFontMetrics 缩放）。

## 9. 剩余项建议顺序（按投入产出 × 是否解锁后续）

| 序 | 事项 | 为什么排这里 | 谁做 |
|---|---|---|---|
| 0 | **修「全部日程搜不了」**（§5.1 问题 1） | **功能不可用**，优先级高于一切打磨项；`.searchable` 在 iOS 26 上不渲染入口，成因待定位 | 我 |
| 1 | **裁决 iPad 右栏语义**（= 我上一轮的裁决项 A） | 卡住 P0-2、§33–§38、P1「iPad Inspector」四条 | 你 |
| 2 | ~~**统一三态组件 + 骨架屏**（§37/§41/§50）~~ **已完成（2026-09-25）** | 组件已建立并接进 4 处界面，Flow 6 已自动化验证空态 + 行动按钮 | 已完成 |
| 3 | **拆 `CalendarMonthView` 的 6 个 sheet**（§74 禁止项） | 触犯明确禁止项；改成 `navigationDestination` 不如完全重做，但可先收口 | 我 |
| 4 | **Reduce Motion 降级**（§44） | 硬缺口、改动小（几处动画加 gate）；骨架屏那一处本轮已 gate | 我 |
| 4b | **对齐 `AppTheme.Radius` 与圆角纪律**（§5.1 问题 2） | Token 的 22/28 不在允许清单里；改值会小幅改动全站圆角，需单独一步并肉眼确认 | 我 |
| 5 | 拆 `SettingsView`（790 行）/ `CalendarMonthView`（725 行）为 Feature 子页 | churn 大、收益偏维护性；应在 2 之后做 | 我 |
| 6 | 补 VoiceOver 标签（现 13 处）与高对比度 | 上架前建议做；`docs/DEVICE_TEST_CHECKLIST.md` 已有检查项 | 我 |
| 7 | 用 §54 的 9×7 矩阵逐格走一遍，把「没实现」和「没测」分开记账 | 需要先有 2 的组件，否则走不通 | 我（部分需真机） |
| 8 | P2 视觉精修（字体/阴影/材质/动画） | 报告自己规定不得早于 P0/P1 | 待定 |

## 10. 本会话对 UI 打磨的实际贡献（便于对照）

- AI 助手交互：修掉「点输入框没反应」与「键盘关不掉」两处 bug，并把「点空白收键盘」
  用 UIKit 手势正确实现（SwiftUI 三种写法逐一验证失败，记录在注释里）；
- 动态字体字号固化修复（`5283a5f`，让 Dynamic Type 真正即时生效）；
- iPad 侧栏 5 行加无障碍标识与整行合并朗读（VoiceOver 更正确）；
- 为 UI 测试补 **14 个静态标识 + 1 个动态标识**（`AccessibilityID` 目录从 6 个增至 20 个，
  新增 `selectedSummary`/`editTitle`/`aiInput` 系列/`settingsSync*`/`ipad.sidebar.*` 与动态的 `monthDay`）；
- 建立 UI 测试基础设施并补 6 条真实路径用例——**这是 §54/§55/§61 第一次有了可重复的验收手段**。
