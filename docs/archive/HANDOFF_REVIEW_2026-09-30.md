# 接手审查报告（2026-09-30）

> 用途：新接手开发者进入本仓库时的**第一份读物**。内容是对当前工作区快照的逐条核对结果，
> 每条都回到代码里验证并附 `文件:行` 证据；无法在本环境验证的，明确标注「未验证」。
>
> **下一步**：读完后按 [`EXECUTION_PLAN_2026-09-30.md`](EXECUTION_PLAN_2026-09-30.md) 执行——
> 本文件回答「现状是什么、哪里有坑」，执行计划回答「按什么顺序做、如何验收」。
>
> **与仓库里既有文档的关系**：本文件**取代** `PROGRESS_ANALYSIS_2026-09-25.md` 与
> `UI_DESIGN_REVIEW_2026-09-28_IMPLEMENTATION.md` 里「当前状态」一类的结论——那两份文档
> 有多处与代码不符（见 §9），因为它们自述「编译验证未执行」却按已完成记录。
> 本文件以实跑为准：**本报告作者亲手跑通了三条验证通道，并修掉了四处阻断性缺陷。**
>
> 审查基线：工作区快照（**无 Git 仓库**）· Xcode 27.0 / Swift 6.4 · iOS 26.5 + 27.0 模拟器
> 代码规模：`Sources` 85 文件 18,899 行 · `Tests` 40 文件 6,167 行 / 328 用例 · UI 测试 825 行 / 12 方法

> **与远端仓库的对齐关系（2026-09-30 经 GitHub API + codeload tarball 逐文件核对）**
>
> 远端 `Ryoku-luke/lunisolar-calendar-ios` 默认分支 `main` = **`1cc0b7f`**（2026-09-29 08:47 UTC，
> "fix(ui): BUG 检查收尾三项打磨"）。本工作区内容与该提交**逐文件一致**，
> 差异仅为本报告与执行计划两份新文档，以及 §1 列出的四处修复（共 13 个文件改动）。
> **无任何来源不明的漂移。**
>
> ⚠️ 但本工作区**没有 `.git` 目录**——它是一份「远端 HEAD 的导出快照」，
> 不是克隆。要对齐远端历史必须重新 `git clone`（见 §2）。

---

## 0. 三句话结论

1. **接手时项目处于「不可编译、不可测试」状态**，而项目自己的 CI 第一关就是 `swift build`
   ——也就是说 CI **必然是红的**，且已红了一段时间无人发现。四处阻断缺陷已由本报告修复（§1）。
2. **没有版本控制**。整个目录没有 `.git`，没有提交历史、无法 diff、无法回滚（§2）。
   这是比任何代码缺陷都更紧急的事。
3. **架构底座是合格的**（真 iPad 三列、服务层收口、月网格缓存、跨时区单测纪律），
   但**云端同步的版本校验缺失**是唯一会静默毁坏用户数据的缺陷（§4），
   而**黄历「喜神/财神」用错了柱**是已上线、用户会照着用的错误信息（§6）。

---

## 1. 已修复：四处阻断性缺陷

接手时无法运行任何验证。以下四处均为**编译级/运行级阻断**，本报告作者已修复并实跑确认。

| # | 缺陷 | 影响面 | 状态 |
|---|---|---|---|
| 1 | `Support/AppTheme.swift` 的 macOS 兜底枚举 `TextStyle` 缺 `title1`，但第 118/122 行用了 `.title1` | macOS 编译失败 → `swift build`、`swift test`、CI 门禁全线不可用 | ✅ 已修 |
| 2 | 9 个视图文件裸调 `navigationBarTitleDisplayMode(.inline)`（仅 iOS 可用），而项目**早已有**跨平台助手 `View.inlineTitleBar()` | macOS 编译失败 | ✅ 已修 |
| 3 | `Tests/.../CalendarDaySummaryTests.swift:104,107` 调用不存在的 `CalendarDaySummary.isLunarUnsupported`（真实 API 是 `LunarDate.isUnsupported`） | **测试 target 整体编译失败，328 条用例一条都跑不了** | ✅ 已修 |
| 4 | `Support/WidgetSnapshotStore.swift` 的 `resolveURL` 把 `~/Documents` 当可写路径直接返回 | macOS `swift test` 下 20 条断言全 `nil`：`write()` 静默返回 `false`，永远走不到已有的临时目录兜底 | ✅ 已修（加可写性探测） |

**修改清单（12 个文件）**

- `Sources/LunisolarCalendarApp/Support/AppTheme.swift` —— 补 `title1` case
- `Sources/LunisolarCalendarApp/Support/WidgetSnapshotStore.swift` —— `resolveURL` 加可写性探测
- `Tests/LunisolarCalendarTests/CalendarDaySummaryTests.swift` —— 改用 `lunar.isUnsupported`
- 9 个视图文件：`navigationBarTitleDisplayMode(.inline)` → `.inlineTitleBar()`
  （`App/LunisolarCalendarApp.swift`、`Views/CalendarMonthView.swift`、`Views/DayDetailView.swift`、
  `Views/SettingsView.swift`、`Views/AIAssistantView.swift`、`Views/EventEditView.swift`、
  `Views/DocSheetView.swift`、`Views/YearOverviewView.swift`、`Views/CalendarDisplaySettingsView.swift`）

**修复后实跑证据（三通道全绿）**

```text
1. swift build（macOS 宿主）                                → Build complete!
2. swift build --triple arm64-apple-ios17.0-simulator       → Build complete!
   --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)"
3. TZ=<tz> swift test   × 4 个时区                           → Executed 328 tests, with 0 failures
   Asia/Shanghai · UTC · America/New_York · Pacific/Auckland
```

**成因说明（重要教训）**：`docs/UI_DESIGN_REVIEW_2026-09-28_IMPLEMENTATION.md:197` 自述该批次
「编译验证未执行——Linux Cloud VM 无 Swift/Xcode，依赖用户 Mac / GitHub CI」。
缺陷 1–3 就是在这次「没编译就记为完成」的批次里引入的。
**本仓库的文档会声称已完成，但当时并没有编译过；接手后一切以实跑为准。**

**未验证项（本会话环境限制，非代码问题）**

- `xcodebuild` 无法在本会话沙箱内完成 SwiftPM 解析（`Could not resolve package dependencies`；
  项目只有本地 package `XCLocalSwiftPackageReference "."`、**无远程依赖**，故非项目问题）。
- 因此 `Tools/run_tests.sh` 的两条 UI 测试通道（iPhone / iPad）**未跑**。
  **请务必在正常终端执行一次 `Tools/run_tests.sh` 补齐这两条通道。**

---

## 2. 无版本控制：接手的第一个动作

**整个项目没有 `.git`**（父目录也没有）。没有提交历史、无法 diff、无法回滚，
文档里提到的 `HEAD`、commit SHA（如 `336ce75`、`1a9f917`、`4a1330b`）全部**不可核验**。

> **在任何功能开发之前，先 `git init` 并建立基线提交。**
> 这个项目已有多次「本机四通道全绿、真机行为不符」的记录（灵动岛、全天事件、AI 助手交互），
> 没有版本控制意味着任何一步改动都不可回退。

`.gitignore` 现有规则有一处**已经造成实际损失**的缺陷，务必先修：

```gitignore
*.json                                   # ← 全局忽略
!Sources/LunisolarCalendarApp/Resources/*.json   # ← 只反选了资源 JSON
```

全局 `*.json` 把 **asset catalog 的 `Contents.json` 也吞掉了**。
后果：远端 `main` 的 `Assets/Assets.xcassets/AppIcon.appiconset/` 里**只有 `Icon-1024.png`，
没有 `Contents.json`**（已核对 `1cc0b7f`）。任何人克隆仓库后，Xcode 都没有可用的 AppIcon 资产目录，
上架/归档会受影响。

**修复建议**：把反选范围放宽到 asset catalog 与工程必需文件，例如

```gitignore
*.json
!Sources/LunisolarCalendarApp/Resources/*.json
!**/*.xcassets/**/Contents.json
!**/*.xcodeproj/**/*.json
```

或更稳的做法：改为**白名单式**忽略具体的数据文件名，而不是全局 `*.json`。


---

## 3. 接手后必读：五个「一碰就静默出错」的地方

这些是代码里真实存在、但既有文档没写清的陷阱。改动前请先读这一节。

1. **`EventStore` 的 `idToIndex` 不变量**（`Stores/EventStore.swift:62-80`）
   任何绕过 `shiftIndices` 的改动路径都会让后续 `update`/`delete` **静默变成 no-op**、
   同步静默跳过记录。另：文档称插入是 O(log N)，**实际是 O(N)**（`shiftIndices` 重写整个字典，
   `events.insert(at:)` 也是 O(N)），M 条 merge 是 O(M·N)。
2. **`consumeDirtyEvents()` 并不消费**（`Stores/EventStore.swift:94-103`），
   且 `skipSync: true` 也照样打脏标。**远端数据必须走 `applyRemote` / `applyRemoteDelete`**，
   用 `update()` 会重新弄脏并把 `updatedAt` 盖成当前时间。
3. **`save()` 是 0.5s 防抖异步**，要持久化必须 `saveNow()` / `flushPendingSave()`。
4. **`EventStore.shared` 无法重新指向**（`private init`）。只有 `EventService` 能被重绑，
   所以任何直接读 `EventStore.shared` 的视图都会**击穿 UI 测试的 `-uitest-empty-store` 隔离**
   （`LunisolarHostApp/HostApp.swift:23-31`）。现存泄漏点见 §5。
5. **LunarCore 模块边界**：`Models/LunarDate.swift` 同属 `LunarCore` 与 `LunisolarCalendarApp`
   两个 target，**不得引用 App 层符号**（`SolarTermProvider` 在 App target）。
   `Package.swift` 中 LunarCore 的 `sources`/`exclude` 是**手工维护**的，新增核心算法文件必须同步改。

---

## 4. 数据与同步：最严重的技术风险

### B1（严重）真实 CloudKit 推送没有版本校验

`Sync/RealCloudKitProvider.swift:181-198` 只为拿 change tag 而 fetch 现有记录，随后
**无条件覆盖所有字段**；`saveBatch` 用 `.ifServerRecordUnchanged`（`:431`），
而这个刚取到的 tag **恰好满足该策略**。

**后果**：持有陈旧 `versionMap` 的设备会用**更低版本**覆盖云端更新的记录；
其他设备再在 `Sync/EventSyncCoordinator.swift:248` 的
`if remoteRec.version > localVersion` 处丢弃它 → **永久分叉**。

`MockCloudKitProvider` 会正确拒绝这种推送（`:171-180`），而**所有同步测试只走 Mock**——
所以这个缺陷在现有测试下**永远测不出来**。

### B2（严重）等版本分叉永不收敛

严格 `>` 比较意味着同版本时远端被丢弃。败方随后会把自己的**陈旧副本以更高版本**重新推上去，
覆盖对方的编辑。`conflictsResolved` 因此几乎永不触发（需要 `>` 且 `localVersion > 0`）。

### B5（高）没有导出入口——用户能恢复备份，却造不出备份

`exportJSON` / `exportICS` / `exportCSV` 定义在 `Support/DataPortability.swift:60,117,196`，
但 `Sources/` 内**零调用点**（只有 import 侧接进了设置页）。
用户数据的唯一副本是一个**无版本号、无迁移机制**的 JSON 文件；
`Stores/EventStore.swift:721-737` 在整文件解码失败时**整体隔离清空**——
而 `CalendarEvent` 的 rawValue 是**中文枚举字符串**（`:36-43,59-63`），
任一未知 rawValue 或缺失 key 都会触发整库清空。

> **更正（2026-09-30，依据远端 `1cc0b7f` 提交信息）**：这三个函数**不是遗留死代码**。
> 该提交明确写道「删除 `DataPortability.writeToTempFile` 死代码（导出 UI 移除后无引用；
> `exportJSON/ICS/CSV` 保留——**单元测试用作导入解析的往返验证镜像**）」。
> 也就是说它们被**有意保留为测试镜像**，导出 UI 是被主动移除的产品决策。
> 因此本条的准确表述是：**产品层面缺少导出/备份入口**（这是一个待决策的产品问题），
> 而**不是**代码层面的死代码缺陷。修它需要先定「是否恢复导出功能」。

### B3（高）同步状态会永久卡在「同步中…」

`EventSyncCoordinator.swift:107` 设 `status = .inProgress(.push)`，
在**抛错**和 `!isEnabled` 提前返回时都**不复位**（`:110-123`），
错误又被 `EventStore.flushDirtyAndDeleted` 吞掉（`:502-505`）只记日志。
设置页的「立即同步」从此**永久禁用**。复现：离线 + 一次 CRUD 编辑。

### 其余已核实项（中危，按需展开）

- 导入会把 `updatedAt` 盖成当前时间（`Models/CalendarEvent.swift:247`），
  于是 `.keepLatest` 策略下**重复导入必然覆盖本地编辑**，而提示仍是「成功」。
- 首次安装会种入 4 条示例事件且**从不参与同步**（`Stores/EventStore.swift:717-719,915-991`），
  第二台设备上会与真实同步数据并存。
- 墓碑 30 天 TTL 用**设备时钟**计算（`EventSyncCoordinator.swift:362-369`）；
  离线超过 30 天的设备会「复活」已删除事件。
- `EventSyncCoordinator` 同时标了 `@unchecked Sendable` 与 `@MainActor`——前者**冗余且无依据**
  （`@MainActor` 类本就是 Sendable）。
- `RealCloudKitProvider` 的 `zoneEnsured` 是 check-then-act（`:342-357`），并发调用会重复建 zone。

### 测试覆盖

**已覆盖**：EventStore CRUD / 排序不变量 / merge 计数 / 压力 / 损坏隔离 / flush；
脏标规则；Mock 的 push/pull/墓碑/watermark；ICS + JSON 导入；系统导入映射；Widget 快照。

**未覆盖（关键）**：`RealCloudKitProvider` **全部路径**（测试无法构造它）、
Mock↔Real 契约一致性、等版本 LWW、双设备并发编辑、`SyncStatus` 任何状态迁移、
墓碑 TTL 清理、`versionMap` 跨实例持久化、部分损坏 vs 整文件损坏、
`idToIndex` 正确性（`assertInvariants` 看不见它）。

---

## 5. UI 层：三个高优先、用户可见的缺陷

### U1（高）节日选中日对比度不合规（首屏）

`Views/CalendarMonthView.swift:507-508` 把未经校验的 `festivalTint` 直接当格子填充色
（`cellAccent: cell.festivalTint ?? …`），而 `Views/CalendarComponents.swift:250` 在选中态
**强制白字**（`if isSelected { return .white }`）。

按项目自己的审计（`Support/DayAccent.swift:8`）：儿童节 `#FDD835` = **1.40:1**、
中秋节 `#F9A825` = **1.97:1**，白字几乎不可读。
`Tests/.../AccentContrastTests.swift` **只测了助手函数，没覆盖这条真实路径**。

### U2（高）Plus/Max iPhone 横屏会变成 iPad 三栏、TabBar 消失

`App/LunisolarCalendarApp.swift:93` 用 `horizontalSizeClass == .regular` 切换根视图，
而 `.regular` 在 Plus/Max iPhone 横屏下同样成立。
项目自己的 `docs/DEVICE_TEST_CHECKLIST.md:267` 标注此点**未验证**，也无自动化覆盖。

### U3（高）`EventStore.shared` 击穿 UI 测试隔离

| 位置 | 说明 |
|---|---|
| `Views/YearOverviewView.swift:222` | `EventStore.shared.events`——年视图会显示真实库的事件点，而全 App 其余部分在 `-uitest-empty-store` 下为空 |
| `Support/NotificationManager.swift:157` | `markNotified` 硬编码单例 |
| `Support/NotificationManager.swift:236` | 稍后提醒回调硬编码单例 |

（`App/LunisolarCalendarApp.swift:20` 的 `@State private var store = EventStore.shared` 是**正常**的
默认值，宿主会用注入实例覆盖；`#Preview` 里的引用也无害。）

### 其他已核实项

- **3 处本地化漏译**（key 在 4 张表里都不存在）：`Views/WeatherCardView.swift:101`、
  `Views/SelectedDayCardView.swift:46`、`Views/CalendarMonthView.swift:381`
  （`Text(verbatim: "\(month)月")` 会让英文界面显示「9月」）。
- **性能**：`Views/AllEventsView.swift` 每次 body 求值做约 10 轮 O(N) 全量扫描
  （`filteredEvents` 被 `pastEvents`/`pastCount`/`upcomingGroups`/`pastGroups`/`visibleEvents`/
  `summaryText` 各自重算，`:337-341` 起），搜索时**逐键触发**；
  `Views/YearOverviewView.swift:193-238` 的 `buildMarks()` 在 `onAppear` **主线程同步**算 365 天
  并为每个事件日新建 `DateFormatter`，返回约 440 个 `AnyView`。
- **设计系统**：token 层与「随系统字号即时生效」都真实有效
  （`Support/AppTheme.swift:76-126`，刻意用计算属性而非 `static let`）；
  但视图层仍有 41 处硬编码语义字体（默认 SF 设计，与 token 的 `.rounded` 是两套字型），
  且有 5 个 token 已成死代码（`Touch.chipHeight`、`Touch.checkboxSize`、`Radius.pill`、
  `Color.cardBorder`、`Shadow.elevated`）。
- **无障碍**：29 个视图文件中 23 个**零** `accessibilityLabel/Hint`；
  年视图约 440 个可点格无标签与 ID，且点击目标仅 16–20pt（低于 HIG 44pt）。

### 做得好的地方（不要推倒重来）

- iPad 是**真正的三列 `NavigationSplitView` + 上下文 Inspector**，不是放大版 iPhone
  （`App/LunisolarCalendarApp.swift:383-389`，右栏按分区切换日详情 / 倒数详情 / 占位）。
- 月网格有 `MonthGridModel` 缓存 + `.equatable()` 单元格，翻月不重算。
- AI 助手**纯本地规则解析、零网络**，且写入严格走 `EventService`
  （符合 `AI_DEVELOPMENT_CONTEXT.md:1034-1055` 的架构红线）。
- 深色模式用动态 provider 真实处理；`Reduce Motion` / `Reduce Transparency` /
  `Increase Contrast` 都有集中处理。

---

## 6. 历法数据层：两个更正 + 一条错误

### ⚠️ 喜神/财神用错了柱（影响全部日期，含所谓「验证库」）

`Models/Huangli.swift:207` 把**日支**索引传给了 `shenWeiDirection`：

```swift
let shenWei = shenWeiDirection(zhiIndex)   // zhiIndex = dayGanZhi.1，即「支」
```

而通行黄历规则以**日干**定喜神/财神（喜神：甲己艮、乙庚乾、丙辛坤、丁壬离、戊癸巽；
财神：甲乙东北、丙丁西南、戊己正北、庚辛正东、壬癸正南）。
实测自证——两天同为甲日却给出不同方位：

| 日期 | 日柱 | 库中输出 | 依日干规则应为 |
|---|---|---|---|
| 2024-01-11 | 甲戌 | 喜神:**西南** 财神:**正南** | 喜神东北 财神东北 |
| 2024-01-21 | 甲申 | 喜神:**东北** 财神:**正西** | 喜神东北 财神东北 |

同一天干必须同方位，这里却随日支变化；且 `shenWeiDirection`（`:298-303`）的映射数组
只是 4 元素循环，**并非任何传统口诀**。
`huangli_db.json` 由同一个生成器产出（`Tools/gen_huangli_db/main.swift:27` 调用的正是
`HuangliGenerator.algorithmGenerate`），所以 **1827 天全部继承该错误**。

#### 2026-09-30 复核：已从权威出处确证，并锁定影响面

**（a）数据侧铁证——库确实是「纯日支函数」**

对全部 1827 天逐一比对「纯日支公式」：

```
库中 1827 天 → 与「纯日支公式」不一致：0 条
每个日支 → 恰好 1 种方位（如 子日 恒为「喜神:东北 财神:西南」）
每个日干 → 6 种不同方位（甲日出现 6 种，乙日 6 种 … 癸日 6 种）
```

方位取值域也直接暴露了错误：库中**喜神只有 4 个取值**（东北/西北/西南/东南）、
**财神有 7 个**（多了正西/正东/东南），而日干规则要求**两者都恰好 5 个**。

**（b）正确规则——有古籍与现代权威库双重出处**

| 日干 | 喜神 | 财神 |
|---|---|---|
| 甲、己 / 甲、乙 | 东北 | 东北 |
| 乙、庚 / 丙、丁 | 西北 | 西南 |
| 丙、辛 / 戊、己 | 西南 | 正北 |
| 丁、壬 / 庚、辛 | 正南 | 正东 |
| 戊、癸 / 壬、癸 | 东南 | 正南 |

- **喜神**：《喜神方位歌》「甲己在艮乙庚乾，丙辛坤位喜神安。丁壬只在离宫坐，戊癸原在巽间」，
  见 [万年历·喜神方位查询口诀](https://m.wannianli.tianqi.com/news/279768.html)（该文并引
  《协纪辨方书·喜神》与《考原》论证「喜神者，见丙也」）。实现见 tyme 库
  [`HeavenStem.getJoyDirection`](https://pub.dev/documentation/tyme/1.4.4/tyme/HeavenStem/getJoyDirection.html)
  （`[7,5,1,8,3][index % 5]`）。
- **财神**：《财神方位歌》「甲乙东北是财神，丙丁向在西南寻，戊己正北坐方位，庚辛正东去安身，
  壬癸原来正南坐」。实现见 tyme 库
  [`HeavenStem.getWealthDirection`](https://pub.dev/documentation/tyme/1.4.4/tyme/HeavenStem/getWealthDirection.html)
  （`[7,1,0,2,8][index ~/ 2]`）。
- 两者都是 **`index % 5` / `index ~/ 2` 的纯日干函数**，与日支无关——
  可直接替换现有 `shenWeiDirection()`。

**（c）已知反例——用户一眼可查**

**2024-01-01（甲子日）**：

| 来源 | 喜神 | 财神 |
|---|---|---|
| 本 App / `huangli_db.json` | 东北 | **西南 ✗** |
| [周新春易学网](https://3g.d5168.com/caishenwei/2024-1-1) | 东北 | **东北** |
| [今日黄历 jrhuangli](https://www.jrhuangli.com/2024-1-1.html)（作「财神位」） | 东北 | **东北** |
| 日干规则计算 | 东北 | 东北 |

喜神这天恰好蒙对，财神错。另有两处已核实：

| 日期 | 日柱 | 库中输出 | 正确（日干规则） |
|---|---|---|---|
| 2024-01-11 | 甲戌 | 喜神:西南 财神:正南 | 喜神:东北 财神:东北 |
| 2024-01-21 | 甲申 | 喜神:东北 财神:正西 | 喜神:东北 财神:东北 |

> ⚠️ 注意 App 的**同库内自相矛盾**：`docs/HUANGLI_DATA_SOURCE.md:22,67` 与
> `docs/XCODE_BUILD_GUIDE.md:309` 都把「喜神:东北 财神:西南」当作 schema 示例，
> 而库中 1827 天**没有任何一天**是这个值（喜神东北+财神西南的组合需要日支=子、日干∈{庚,辛}，
> 六十甲子中无此搭配）。这说明 schema 文档的示例取自别处，不是本库产物。

#### ✅ 已于 2026-09-30 修复

`Huangli.swift:209` 改为传 `dayGanZhi.gan`；`shenWeiDirection` 按两套口诀重写
（`[i%5]` / `[i/2]`，附出处）；`huangli_db.json` 重新生成（419 KB → 435.8 KB，
仅 `g` 字段变化 1797/1827 天，其余 5 字段 0 差异）。

新增 4 条回归断言（权威基准、同日干必同方位、取值域各 5 个、逐日干对照口诀），
并把 `HuangliDBProviderTests` 的一致性测试从**抽样 29 天**改为**逐日全量 1827 天**。
**这些断言已用「临时改回旧实现」验证过会失败**（失败信息为「天干 index N 出现了 6 种方位」），
不是碰巧全绿。实跑：`swift test` 332 用例 × 4 时区 0 失败。

上述三处**错误的文档示例**已一并更正为真实值。详见 `EXECUTION_PLAN` §P1-2「实施结果」。


> **修复需注意**：日干版口诀存在多家变体，需先裁决采用哪一派；
> 修完必须**重新生成 `huangli_db.json`**（1827 天数据全变），
> 并同步调整 `Tests/.../HuangliDBProviderTests.swift` 中「离散库 == 算法」的采样断言，否则测试会红。

### ⚠️ 更正：「离散库」不是可信度更高的数据源

既有文档（含 `docs/HUANGLI_DATA_SOURCE.md`）把 `huangli_db.json` 描述为「验证数据库」。
**这是错的**：该库就是算法自身的输出——对 1827 天 × 6 字段全量比对，**0 处差异**。

因此 `Support/HuangliDBProvider.swift:47-50` 的 `.discreteDB` / `.algorithm`
只是**缓存命中标记，不是「已验证 vs 推算」的可信度标记**，
代码注释里「保证最近 5 年准」**没有依据**。
未来若要做数据可信度区分（`AI_DEVELOPMENT_CONTEXT.md` §6 的要求），
**不能拿这个枚举当基础**，需要另建真实来源校验。

### 其他已核实项

- **1900-01-01 ~ 1900-01-30 显示伪造农历**：`LunarDate.isSupported` 只校验公历年份，
  于是 `lunarDateSafe` 走公历镜像分支（`Models/LunarDate.swift:203-211`），
  `Date.lunar` 返回如「庚子年正月初一」且 `isUnsupported == false`，
  **UI 的兜底守卫不会触发**。经年视图的 1900…2100 选择器可达（`Views/DateJumpView.swift:41`）。
- **忌「诸事不宜」与 8 条宜并存**：`Models/Huangli.swift:119`，
  1827 天中有 **123 天（6.7%）** 同时输出「忌诸事不宜」和多条「宜」，语义自相矛盾。
- **`Calendar.gregorian` 冻结时区** 确认属实，且**冻结于首次访问**（非进程启动）。
  全仓只有 `Models/LunarDate.swift` 用它（19 处），其余都新建日历，
  于是**一个进程里存在两个「今天」**：`HuangliDBProvider.resolve` 用新日历取日键（`:106-114`）、
  却用冻结日历算农历（`:108`），会话内切换时区后可能出现
  「D 日农历 + D±1 日宜忌」的错位；`Date.isToday`（`LunarDate.swift:373-375`）也会把红点标错格。
- **中国锚数据落在设备本地日**：`SolarTermProvider.termOn/nextTerm` 按设备本地日归属
  （`:305-312`，被 `TimeZoneGoldenTests:117-138` 锁定为**有意行为**）。
  于是 2026 清明（北京 04-05 02:40 = 纽约 04-04 14:40）在纽约显示为 **04-04**；
  黄历/日干支同理。这与 `Support/QingheCalendarContext.swift:8-16` 主张的「历法用中国时间」
  存在**未裁决的冲突**。
- **`ganZhiOfYear(for:)` 是死代码**：`Models/LunarDate.swift:330-338` 硬编码 2 月 4 日 00:00 边界，
  全仓**无调用点**。1900–2100 中立春落在 2 月 4 日的只有 **128/201** 年
  （2 月 5 日 34 年、2 月 3 日 39 年）。生产显示走的是「春节换年」（`:90` `yearGanZhi`），自洽。
  文档要求的「App 层用精确立春换年柱」**从未实施**。
- **`CalendarDayKey.endOfDay` 用 `+86_399`**（`Models/CalendarDayKey.swift:53-56`）：
  在 DST 春季跳变日会让单个全天事件跨 2 天（下一个美国 DST 日 **2027-03-14**）。对中国用户无影响。

---

## 7. 有确定到期日的数据悬崖

这三个都不是紧急 bug，但**到期后会静默降级**（不报错），建议现在就加提醒或改数据加载方式。

| 数据 | 覆盖范围 | 到期表现 | 到期日 |
|---|---|---|---|
| 节气表 `Support/SolarTermProvider.swift` | **2024–2032**（216 条 = 9 年 × 24，分钟精度，上海时区锚） | `nextTerm` 先失效 → `termOn` 失效：**节气显示整体消失**，月历节气条 / 灵动岛 / 节气节日全无 | `nextTerm` **2032-12-22**；`termOn` **2033-01-01** |
| 放假安排 `Support/HolidayProvider.swift` | **2025-01-01 ~ 2026-10-10** | 所有节日（含元旦/春节）返回 `.normal`、`""` | **2027-01-01** |
| 黄历离散库 `Resources/huangli_db.json` | **2024-01-01 ~ 2028-12-31**（1827 天，连续无缺口） | 落到算法兜底（即同一算法，无质量变化） | 2029-01-01 |

**两个必须注意的维护陷阱**：

1. `HolidayProviderTests.swift:61-72` **把错误行为写成了断言**
   （断言 2027-01-01 为 `.normal`）。每年补放假数据时**必须同步修改该测试**。
2. `SolarTermProvider.swift:6` 的注释写「2025–2028」，`Support/FestivalManager.swift:148`
   也重复了这个错误范围——实际是 2024–2032。**这类注释不可信，以代码为准。**

**已确认可靠的部分**（不必返工）：

- 农历转换表**精确**：1900–2100 共 73,384 天与 ICU 中文历逐日比对，
  闰月位置 **0 差异**、双向换算 **0 失败**；农历三十在 29 天月被正确拒绝。
- 节气表数据**无抄录错误**：经独立 Meeus 太阳黄经计算校验，
  最大偏差 **13 分钟**、平均 4.1 分钟、无一条超过 30 分钟。问题只在**时区归属**，不在数值。
- 节日（春节/除夕/闰月）为算法生成，安全到 2100，处理正确。

---

## 8. 质量基础设施现状

**优点**：328 条单测 + 12 条 UI 测试（10 条编号流程 + 截图巡游），CI 按 **4 个时区**各跑一遍
（日期边界必须跨时区自证，这条纪律执行得很好）；CI 还有一道**硬编码字号红线** job
（本报告作者本地复扫：**0 处未豁免命中**，该门禁健康）。

**缺口**：

- **没有单元测试 target**（单测走 SPM，`xcodebuild test` 只跑 UI）。这是有意的架构选择，
  但意味着 Xcode 里无法单独跑单测。
- `RealCloudKitProvider`（636 行）**零自动化覆盖**；Mock 与 Real **不共享契约**。
- `ActivityKit` 相关（request/update/end、跨活动仲裁、staleDate）**全部不可测**；
  Widget 的 `getTimeline`/`getSnapshot`/`placeholder` 无测试。
- **UI 测试盲区**：编辑/删除事件、全天、重复规则、提醒/通知、倒数日增删、导入、
  深色模式、Dynamic Type、英文/日文界面、VoiceOver、天气、Widget、Live Activity、
  年视图、日期跳转——均未覆盖。
- 12 条 UI 方法中 **7 条会在某一端 `XCTAssertSkip`**，真正的 iPad 覆盖只有 2 条。
- `LunisolarCalendarUITests.swift:31-56` 手工维护了一份 ID 表副本，会与 `AccessibilityID` **静默漂移**。
- 节气测试只校验了 216 条中的 **12 条**，且**无一条对照星历**；
  `HuangliDBProviderTests` 拿库与「产出它的生成器」比对，**永远发现不了宜忌算错**。

---

## 9. 既有文档的失效点（避免被误导）

| 文档 | 陈述 | 实际 |
|---|---|---|
| `UI_DESIGN_REVIEW_2026-09-28_IMPLEMENTATION.md:6,197` | 本批次「代码改动已完成」，仅「未 commit / 未 push / 未真机验证」 | **从未编译过**——正是本报告 §1 三处编译缺陷的来源 |
| `PROGRESS_ANALYSIS_2026-09-25.md:43-44` | `CalendarMonthView` 725 行、`SettingsView` 786 行需拆分 | 当前实测 **567 行**、**<400 行**，该待办已过时 |
| `SolarTermProvider.swift:6`、`FestivalManager.swift:148` | 节气表覆盖 2025–2028 | 实际 **2024–2032** |
| `HuangliDBProvider.swift:41` | 黄历库 385 KB | 实际 **436 KB** |
| 多份文档 | `huangli_db.json` 是「验证数据库」 | **算法自身输出**，0 差异（§6） |
| `NotificationManager.swift:56` | 「首次添加提醒时调用」请求权限 | 权限**只在设置页**请求（`SettingsView.swift:146-150`）；从不打开设置的用户**永远收不到通知** |
| 多份文档 | `FloatingCard`/`modernCard`/`liquidCard` 等 | 已清零，现为 `glassCard` + `softChipBackground` |

---

## 10. 建议的接手顺序

| 序 | 事项 | 理由 |
|---|---|---|
| 1 | **`git init` + 基线提交** | 当前零版本控制，任何改动都不可回滚 |
| 2 | **正常终端跑 `Tools/run_tests.sh`** | 补齐本会话未能验证的 `xcodebuild` + 两条 UI 通道；本报告修的 3 处只在 SwiftPM 通道暴露 |
| 3 | **修 B1/B2**（真实 CloudKit 版本校验 + 等版本收敛），并补 Mock↔Real 契约测试 | 唯一会**永久分叉用户数据**的缺陷 |
| 4 | **修喜神/财神用柱**（§6）——先裁决口诀，再改生成器 + 重生成库 + 更新测试 | **已上线、用户会照着用的错误信息**，影响每一天 |
| 5 | **清除 `EventStore.shared` 泄漏点**（§5 U3，3 处） | 让 UI 测试隔离真正成立，是后续补 UI 测试的前提 |
| 6 | 节日格子对比度（U1）、iPhone 横屏根视图（U2）、3 处漏译 | 都是小改动、用户直接可见 |
| 7 | 数据到期预警：节气 2033 / 放假 2027 / 黄历 2029 | 避免到期后静默消失；放假表还需同步改测试 |
| 8 | 补导出入口（B5） | 否则用户**永远没有备份路径** |

**不建议现在做**：目录重排（`Features/`/`Domain/` 等，见 `PROGRESS_ANALYSIS_2026-09-25.md` §4-C——
功能等价、只改路径）、拆分大文件、以及任何「为了对齐文档」的重构。
先把「可验证 + 数据正确」这两件事做实。

---

## 附：本报告的证据等级说明

- **实跑验证**：§1 的三通道结果、328 用例 × 4 时区、字体红线复扫——本报告作者亲手执行。
- **代码核对验证**：§4 §5 §6 中标注 `文件:行` 的每条断言——作者本人读过对应代码；
  其中喜神/财神、离散库自产、`EventStore.shared` 泄漏点、节日格子对比度路径、
  四个数据悬崖的边界日期，作者**独立复核过**。
- **未验证**：`xcodebuild` / UI 测试通道（§1 末）；农历表与 ICU 的 73,384 天全量比对、
  节气表的 Meeus 校验、6 处月界分歧的逐案裁决（§7，由并行审查给出，作者仅复核了结论方向）。
  涉及这几项的上线决策，建议自行复算一次。
