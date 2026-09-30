# 执行计划（2026-09-30 起）

> 配套文档：[`HANDOFF_REVIEW_2026-09-30.md`](HANDOFF_REVIEW_2026-09-30.md)（证据与行号都在那里，本文件只排「怎么做、按什么顺序、如何验收」）。
>
> **排序原则**：
> 1. **先建「可验证」，再改代码**。当前项目 CI 必红、无版本控制，任何改动都无法证伪。
> 2. **先修「数据正确」，再修「界面好看」**。喜神/财神与 CloudKit 是数据问题，对比度和布局是外观问题。
> 3. **先修「会静默损坏用户数据」的，再修「看得见但不致命」的**。
> 4. **不做「为了对齐文档」的重构**（目录重排、大文件拆分），除非它挡在某个 P0/P1 前面。
>
> 任务编号：`P0-x` 安全底座 · `P1-x` 数据正确性 · `P2-x` 数据安全与悬崖 · `P3-x` 界面与无障碍 · `P4-x` 维护性。
> 每个任务卡：**改什么 / 不改什么 / 怎么验收 / 依赖 / 需否你裁决**。

---

## 一、总览

| 阶段 | 主题 | 任务 | 出口标准（Exit Criteria） |
|---|---|---|---|
| **P0** | 安全底座 | P0-1 Git 基线 · P0-2 四通道跑通 · P0-3 CI 转绿 | 有可回滚的提交历史；`Tools/run_tests.sh` 四通道全绿；CI 在 main 上绿 |
| **P1** | 数据正确性（高危） | P1-1 CloudKit 版本校验 · ~~P1-2 喜神/财神用柱~~ ✅ · ~~P1-3 单例泄漏清除~~ ✅ | 双设备同步不再分叉；喜神/财神符合日干规则；UI 测试隔离真正成立 |
| **P2** | 数据安全与悬崖 | P2-1 导出/备份+迁移 · P2-2 同步状态卡死 · P2-3 导入覆盖 · P2-4 数据到期机制 | 用户能造出备份；同步状态可恢复；导入不再静默覆盖；到期前有预警 |
| **P3** | 界面与无障碍 | P3-1 节日对比度 · P3-2 横屏根视图 · P3-3 漏译 · P3-4 Dynamic Type · P3-5 性能 | 首屏可读性合规；Plus/Max 横屏正确；0 漏译；辅助字号不截断 |
| **P4** | 维护性（可延后） | P4-1 无障碍覆盖 · P4-2 数据可信度标识 · P4-3 大文件拆分 | 仅在有明确收益时做 |

**建议节奏**：P0 必须一次做完（半天量级）；P1 逐项独立提交；P2/P3 可穿插；P4 暂不启动。

---

## 二、P0 · 安全底座（最高优先，必须先完成）

> 目标：把「无法验证、无法回滚」变成「可验证、可回滚」。**在 P0 完成前不要动任何功能代码。**

### P0-1 建立 Git 基线

> **前置已裁决（2026-09-30）**：D1 = **对齐远端仓库历史**。
> 远端 `main` = `1cc0b7f`；本工作区内容与该提交逐文件一致（已核对），
> 差异只有本次 4 处修复 + 2 份新文档。**但工作区没有 `.git`，是导出快照而非克隆**，
> 因此必须重新 `git clone` 后再把改动搬过去——不能在原地 `git init`，
> 否则会得到一条与远端**没有共同祖先**的独立历史，无法 push / 无法对齐。

- **做什么**
  1. **先备份当前改动**（4 处修复 + 2 份文档共 15 个文件），它们目前是未提交状态。
     最省事的做法：先把整个工作区复制一份到旁边目录留底。
  2. 在**正常终端**（本会话沙箱无法访问 `github.com`，见下方说明）执行：
     ```bash
     cd ~/Downloads
     git clone https://github.com/Ryoku-luke/lunisolar-calendar-ios.git lunisolar-git
     cd lunisolar-git && git log --oneline -5      # 确认 HEAD == 1cc0b7f
     ```
  3. 把本轮的全部改动搬到克隆里。**权威清单（25 改 + 3 新增，2026-09-30 与远端 `1cc0b7f` 逐文件核对）**：

     **被改（25）**
     ```
     .gitignore                                             README.md
     Sources/LunisolarCalendarApp/App/LunisolarCalendarApp.swift
     Sources/LunisolarCalendarApp/Models/Huangli.swift                    ← P1-2
     Sources/LunisolarCalendarApp/Resources/huangli_db.json               ← P1-2 重新生成
     Sources/LunisolarCalendarApp/Services/EventService.swift             ← P1-3
     Sources/LunisolarCalendarApp/Stores/EventStore.swift                 ← P1-3
     Sources/LunisolarCalendarApp/Support/AppTheme.swift
     Sources/LunisolarCalendarApp/Support/NotificationManager.swift       ← P1-3
     Sources/LunisolarCalendarApp/Support/WidgetSnapshotStore.swift
     Sources/LunisolarCalendarApp/Views/AIAssistantView.swift
     Sources/LunisolarCalendarApp/Views/CalendarDisplaySettingsView.swift
     Sources/LunisolarCalendarApp/Views/CalendarMonthView.swift
     Sources/LunisolarCalendarApp/Views/DayDetailView.swift
     Sources/LunisolarCalendarApp/Views/DocSheetView.swift
     Sources/LunisolarCalendarApp/Views/EventEditView.swift
     Sources/LunisolarCalendarApp/Views/SettingsView.swift
     Sources/LunisolarCalendarApp/Views/YearOverviewView.swift            ← 编译修复 + P1-3
     Sources/LunisolarCalendarApp/Widgets/SnoozeReminderIntent.swift      ← P1-3
     Tests/LunisolarCalendarTests/CalendarDaySummaryTests.swift
     Tests/LunisolarCalendarTests/HuangliDBProviderTests.swift            ← P1-2
     Tests/LunisolarCalendarTests/HuangliTests.swift                      ← P1-2
     Tests/LunisolarCalendarTests/NotificationManagerTests.swift          ← P1-3
     docs/HUANGLI_DATA_SOURCE.md
     docs/XCODE_BUILD_GUIDE.md
     ```

     **新增（3）**
     ```
     docs/HANDOFF_REVIEW_2026-09-30.md
     docs/EXECUTION_PLAN_2026-09-30.md
     Assets/Assets.xcassets/AppIcon.appiconset/Contents.json   ← 远端缺失，必须补提交
     ```

     > 核对方法：在克隆里 `git status --porcelain`，应与上面清单逐条对应。
     > 注意 `LunisolarCalendar.xcodeproj/project.xcworkspace/xcshareddata/` 本地是空目录，
     > git 不收录空目录，无需处理。
     > ⚠️ `huangli_db.json` 是 1827 天的整体重写，建议**单独一个提交**便于回溯。
  4. **同时修 `.gitignore` 的 `*.json` 缺陷**（见 `HANDOFF_REVIEW` §2）：
     全局 `*.json` 把 asset catalog 的 `Contents.json` 也忽略了，
     导致远端 `AppIcon.appiconset/` 里**只有 PNG、没有 Contents.json**，克隆后 Xcode 无可用 AppIcon。
     修复后需**补提交 `Contents.json`**。→ 这是本次对齐顺带必须解决的真问题。
  5. 按逻辑分组提交，建议拆成 **7 个**提交以便回溯（每个都独立可编译）：
     1. `fix(build): 修复 macOS 编译（AppTheme.title1 + 9 处 navigationBarTitleDisplayMode）`
     2. `fix(test): CalendarDaySummaryTests 改用 lunar.isUnsupported`
     3. `fix(widget): WidgetSnapshotStore 路径可写性探测`
     4. `fix(notify): NotificationManager 显式注入 store，清除 EventStore.shared 泄漏（P1-3）`
     5. `fix(huangli): 喜神/财神改按日干取（P1-2）+ 重新生成 huangli_db（单独提交，1827 天整体重写）`
     6. `chore(git): 修 .gitignore 的 *.json 误吞 asset catalog Contents.json + 补提交 Contents.json`
     7. `docs: 接手审查报告 + 执行计划`
  6. 最后 `git status` 应干净；`git log` 显示这些提交接在 `1cc0b7f` 之后。
- **验收**：`git log` 以 `1cc0b7f` 为祖先；`git status` 干净；改一行代码 `git diff` 能看出差异；
  `git stash` / `git checkout --` 可回滚；`Contents.json` 已在版本控制中。
- **不做**：不要在这次提交里夹带任何格式化或重构，保持「快照 + 修复」可读。

> **本会话为何不能代做**：`github.com` 与 `codeload`/`api.github.com` 的**只读**接口可达
> （已成功下载 tarball 核对内容），但 git 的 `info/refs` 端点不可达、SSH 21/22 无法鉴权，
> 因此**无法在此建立带历史的仓库**。第 2 步请在正常终端执行。


### P0-2 跑通四通道验证

- **做什么**：正常终端执行 `Tools/run_tests.sh`（四通道串行）。
- **已知预期**：前两条（`swift test` + iOS SDK 构建）应绿；**后两条 UI 测试从未在本次审查中跑过**，是主要未知项。
- **若 UI 测试失败**：按 `/tmp/run_tests.*.log` 定位。注意脚本默认 `OS_VER=26.5`、
  机型 `iPhone 17 Pro` / `iPad Pro 11-inch (M5)`，本机均存在；
  若机型/OS 不符，用 `OS_VER=27.0 Tools/run_tests.sh` 或 `IPAD_SIM=…` 覆盖。
- **验收**：脚本输出「✅ 全部通过」，4 条通道全绿。
- **不做**：不要在此时修 UI 测试的业务断言（那是 P3 的事），只确认通道能跑、能判定。

### P0-3 让 CI 真正转绿

- **做什么**
  1. 推送 P0-1 的提交，观察 `.github/workflows/ci.yml`：
     `swift build`（macos-26）· `swift test` × 4 时区 · iOS SDK 构建 · 硬编码字号红线。
  2. **本次审查已确认前三条在本地可绿**，CI 理应转绿；若仍红，优先怀疑
     `runs-on: macos-26` runner 镜像的工具链版本（见 `ci.yml:10-15` 的历史踩坑记录）。
- **验收**：main 分支 CI 全绿；红的情况下能在**无需登录**的 `::error::` 注解里看到编译诊断。
- **依赖**：P0-1、P0-2。

> **P0 完成后的状态**：项目从「不可编译、不可测试、不可回滚」变为「三通道可验证 + CI 门禁 + 可回滚」。
> 这是后续所有工作的前提。

---

## 三、P1 · 数据正确性（高危，逐项独立提交）

### P1-1 修复 CloudKit 推送的版本校验缺失

> 对应审查报告 §4 B1/B2。**唯一会永久分叉用户数据的缺陷。**

- **问题**：`Sync/RealCloudKitProvider.swift:181-198` 只为拿 change tag 而 fetch，
  随后无条件覆盖所有字段；`saveBatch` 用 `.ifServerRecordUnchanged`（`:431`）而这个 tag 恰好满足。
  持陈旧 `versionMap` 的设备会用**更低版本**覆盖云端记录，其他设备再在
  `Sync/EventSyncCoordinator.swift:248` 的严格 `>` 处丢弃 → 永久分叉。
- **做什么**
  1. 推送前**逐条比对云端 `version` 与本地待推 `version`**：云端更高 → 不覆盖（记为冲突，走拉取）。
  2. 统一 Mock 与 Real 的冲突语义：`MockCloudKitProvider` 已实现「先 version、再 updatedAtMs」
     （`:6-9,24-25`），**让契约以它为准并让 Real 对齐**。
  3. 修 B2：等版本分叉的收敛规则（当前严格 `>` 使等版本远端被无条件丢弃）。
  4. **补契约测试**：Mock 与 Real 共享一套冲突场景断言（Real 需可注入测试替身，
     现有实现无法在测试中构造 → 需先抽一层可测的边界）。
- **不改什么**：不动 CloudKit 的 zone/recordType/cursor/分页机制（`LunisolarZone`、`CalendarEvent`），
  不动墓碑 TTL 与 `applyRemote*` 路径。
- **验收**：新增冲突场景测试覆盖「云端更新 → 本地陈旧推送被拒」「等版本双向编辑 → 收敛」；
  现有 `ICloudSyncTests` 全绿。
- **风险**：这是同步核心，改动必须小步；建议**先补测试再改行为**。

### P1-2 修复喜神/财神用错柱

> 对应审查报告 §6。**已上线、用户会照着用的错误信息，影响每一天。**
> **D2 已由证据解决（2026-09-30）**：口径不是「多家变体任选」，而是有古籍 + 现代权威库
> 双重出处的确定规则（详见 `HANDOFF_REVIEW` §6 的复核小节）。

- **问题**：`Models/Huangli.swift:207` 把**日支**传给 `shenWeiDirection`，
  正确规则以**日干**定方位。数据侧已确证：1827 天与「纯日支公式」**0 条不一致**，
  每个日干出现 6 种方位；库中喜神只有 4 个取值、财神 7 个，而规则要求各恰好 5 个。
- **已知反例（可直接写进测试）**：2024-01-01（甲子日）本 App 给「财神:西南」，
  而[周新春易学网](https://3g.d5168.com/caishenwei/2024-1-1)与
  [今日黄历](https://www.jrhuangli.com/2024-1-1.html)均为「财神:东北」。
- **做什么**
  1. 改写 `shenWeiDirection`，入参由**日支**改为**日干**，用下面这张表
     （出处：《喜神方位歌》《财神方位歌》，实现对齐 tyme 库
     [`getJoyDirection`](https://pub.dev/documentation/tyme/1.4.4/tyme/HeavenStem/getJoyDirection.html)
     `[7,5,1,8,3][index % 5]` /
     [`getWealthDirection`](https://pub.dev/documentation/tyme/1.4.4/tyme/HeavenStem/getWealthDirection.html)
     `[7,1,0,2,8][index ~/ 2]`）：

     | 日干 | 喜神 | 财神 |
     |---|---|---|
     | 甲己 / 甲乙 | 东北 | 东北 |
     | 乙庚 / 丙丁 | 西北 | 西南 |
     | 丙辛 / 戊己 | 西南 | 正北 |
     | 丁壬 / 庚辛 | 正南 | 正东 |
     | 戊癸 / 壬癸 | 东南 | 正南 |

  2. `Huangli.swift:207` 的调用改为传 `dayGanZhi.0`（天干）而非 `zhiIndex`。
  3. **重新生成 `Resources/huangli_db.json`**（`Tools/gen_huangli_db`）——1827 天数据全变。
  4. 更新 `Tests/.../HuangliDBProviderTests.swift` 中「离散库 == 算法」的采样断言。
  5. 新增断言：**同日干必同方位**；并锁定 2024-01-01 = 喜神东北 / 财神东北、
     2024-01-11 = 喜神东北 / 财神东北、2024-01-21 = 喜神东北 / 财神东北（三个甲日必须同值）。
  6. 顺手修正 `Huangli.swift:206` 的「简化」注释，改为写明出处。
- **不改什么**：不动农历换算表、节气表、宜忌的既有轮转逻辑（后者是独立问题，见 P1-2b）。
- **验收结果**：✅ **已完成（2026-09-30）**，见下方「实施结果」。
- **附 P1-2b（可合并或独立）**：`Huangli.swift:119` 有 123/1827 天（6.7%）
  同时输出「忌：诸事不宜」与多条「宜」，语义自相矛盾。修与不修都行，但**不要和用柱修复混在同一次提交**。

#### P1-2 实施结果（2026-09-30）

**改了什么**

| 文件 | 改动 |
|---|---|
| `Models/Huangli.swift:209` | 调用点由 `shenWeiDirection(zhiIndex)` 改为 `shenWeiDirection(dayGanZhi.gan)` |
| `Models/Huangli.swift:317` | 重写 `shenWeiDirection(_ ganIndex:)`：`[i%5]` / `[i/2]` 两套口诀，并写明《喜神方位歌》《财神方位歌》出处与 tyme 库口径，附「不要改回按日支」告警 |
| `Resources/huangli_db.json` | **重新生成**（`swift run gen_huangli_db`）：419 KB → 435.8 KB，仅 `g` 字段变化（1797/1827 天），其余 5 字段 0 处差异 |
| `Tests/.../HuangliTests.swift` | 新增 **4 条**回归断言（见下） |
| `Tests/.../HuangliDBProviderTests.swift` | 一致性测试由**抽样 29 天**改为**逐日全量 1827 天**；更正一处错误注释（2024-01-01 是甲子日，非甲戌） |
| `docs/HUANGLI_DATA_SOURCE.md` | 修正错误示例「喜神:东北 财神:西南」→ 真实值；新增 §5 方位规则与三条自检；更正「库有 `a` 字段」的错误说法；更新体积 |
| `docs/XCODE_BUILD_GUIDE.md` | 示例 JSON 与实际库对齐（原示例 `c` 字段也是错的） |

**新增的 4 条回归断言**

1. 权威基准：2024-01-01（甲子日）= 喜神东北 / 财神东北（对齐周新春易学网 + jrhuangli）。
2. **核心不变量**：同一日干必同方位（六十甲子逐日扫）。
3. 取值域：喜神 ∈ 5 个、财神 ∈ 5 个（旧实现退化为 4 / 7）。
4. 逐日干对照两套口诀（甲…癸）。

**测试有效性已证伪过**：临时把代码改回旧实现，断言 1️⃣2️⃣4️⃣ **全部失败**，
且失败信息正是 bug 指纹——「天干 index N 出现了 **6** 种方位」（旧实现每个日干 6 种）。
即这些断言**确实能抓住**该 bug，不是「碰巧全绿」。

**验收（实跑）**：macOS 构建 ✅ · iOS SDK 构建 ✅ ·
`swift test` **332 用例 × 4 时区 0 失败** ✅（测试数 328 → 332；全量比对使单测耗时 +0.7s）。

**尚未处理（诚实记一笔）**：`Huangli.swift:119` 的「忌诸事不宜 + 8 条宜」矛盾（P1-2b）未动；
农历表等其余历法数据未受影响（未改 `LunarDate.swift`）。


### P1-3 清除 `EventStore.shared` 泄漏点 ✅ 已完成（2026-09-30）

> 对应审查报告 §5 U3。**是 P3 补 UI 测试的前置条件。**

- **做了什么**：把「让 `NotificationManager` / 视图自己去读单例」改为**由调用方显式传入 store**：
  - `Support/NotificationManager.swift`：`scheduleNotification(for:in:)` 与
    `snoozeReminder(eventID:in:after:)` 增加 `in store: EventStore` 参数（并标 `@MainActor`），
    内部不再读 `EventStore.shared`。
  - 调用点同步改为传各自已有的 store：`Stores/EventStore.swift:367`（`in: self`）、
    `Services/EventService.swift:60`（`in: store`）、
    `Support/NotificationManager.swift:281`（`in: store`，本就有 store 入参）。
  - `Widgets/SnoozeReminderIntent.swift`：该 intent 的 `perform()` 在主 App 进程执行，
    显式传 `.shared` 并在注释里说明**不要改回**「让 NotificationManager 自己读单例」。
  - `Views/YearOverviewView.swift`：改用 `@Environment(EventStore.self)`。
  - `Tests/.../NotificationManagerTests.swift`：两处调用改用 `makeIsolatedEventStore()`
    （测试现在跑在隔离库上，不再碰真实库）。
- **不改什么**：`App/LunisolarCalendarApp.swift:20` 的 `@State private var store = EventStore.shared`
  是**正常的默认值**（宿主会注入覆盖），不要动；`#Preview` 里的引用也无害。
- **验收结果**（实跑）：`grep -rn 'EventStore.shared' Sources/` 剩余命中**全部是注释或合法默认值**，
  无实现路径读单例；macOS 编译 ✅ · iOS SDK 编译 ✅ · 328 用例 × 4 时区 0 失败 ✅。
- **未完成部分**：计划中「新增一条 `-uitest-empty-store` 下的年视图断言：全库为空时年视图不显示事件点」
  需要 UI 测试通道（本会话沙箱跑不了 `xcodebuild`），留到 P0-2 之后补。

### P1-3b 修 `.gitignore` 吞掉 asset catalog `Contents.json` ✅ 已完成（2026-09-30）

> 对应审查报告 §2。**已造成实际损失的真问题**，顺带在 P0-1 之前修掉。

- **做了什么**：`.gitignore` 的全局 `*.json` 后面补两条反选：
  ```gitignore
  !**/*.xcassets/**/Contents.json
  !**/*.xcodeproj/**/*.json
  ```
- **验收结果**（用临时 git 仓库实测忽略行为）：
  `Contents.json` 与 `Resources/*.json` **纳入版本控制**；
  `calendar_events.json` / `widget_snapshot.json` / `countdowns.json` **仍被忽略**。
- **P0-1 时必须一并做**：把 `Assets/Assets.xcassets/AppIcon.appiconset/Contents.json`
  补提交进远端（远端 `1cc0b7f` 缺这个文件，干净克隆后 Xcode 没有可用 AppIcon 资产目录）。


---

## 四、P2 · 数据安全与到期悬崖

### P2-1 补导出入口 + 存储迁移机制

> 对应审查报告 §4 B5。**用户目前能恢复备份，却造不出备份。**

- **做什么**（**先裁决 D6**：导出 UI 是被主动移除的产品决策，函数有意留作测试镜像）
  1. 若裁决恢复：在设置页「数据」分区接上已有的 `DataPortability.exportJSON/exportICS/exportCSV`
     （`Support/DataPortability.swift:60,117,196`），走系统分享/文件导出。
  2. 补存储格式版本与迁移：`JSONBackupWrapper.version`（`:621-632`）**存在但从未被读取**（`:83`）；
     `calendar_events.json` 无版本号。
  3. 缓解 B4 的「一条坏记录清空整库」：`CalendarEvent` 的 rawValue 是**中文枚举字符串**
     （`Models/CalendarEvent.swift:36-43,59-63`），任一未知值即整文件隔离。
     建议改为**逐条容错解码**（坏记录进隔离区，其余保留），而非整文件丢弃。
- **验收**：能从设置页导出三种格式并成功回导；构造一条未知 rawValue 记录，
  验证**其余记录不丢**。
- **风险**：逐条容错解码会改 `EventStore` 的加载路径，需先补「部分损坏」测试
  （现有仅测整文件垃圾，`EventStoreTests.swift:444-480`）。

### P2-2 修同步状态卡死

> 对应审查报告 §4 B3。

- **做什么**：`Sync/EventSyncCoordinator.swift:107` 的 `status = .inProgress(.push)`
  在抛错与 `!isEnabled` 提前返回时都不复位（`:110-123`），错误又被
  `EventStore.flushDirtyAndDeleted`（`:502-505`）吞掉 → 设置页「立即同步」永久禁用。
  改为 `defer` 复位或显式状态机收敛。
- **验收**：新增「离线推送失败后状态回到 idle/failed 且按钮可用」的测试
  （当前 `SyncStatus` 任何状态迁移都无测试）。

### P2-3 修导入静默覆盖本地编辑

> 对应审查报告 §4 中危项。

- **做什么**：导入时把 `updatedAt` 盖成当前时间（`Models/CalendarEvent.swift:247`），
  使 `.keepLatest` 下**重复导入必然覆盖本地编辑**而提示仍是「成功」。
  改为保留源时间或明确提示冲突。
- **验收**：新增「导入 → 本地编辑 → 再次导入」用例，验证本地编辑不被悄悄覆盖。

### P2-4 建立数据到期机制

> 对应审查报告 §7。三个悬崖都会**静默降级**（不报错）。

| 数据 | 覆盖到 | 到期表现 | 到期日 |
|---|---|---|---|
| 节气表 | 2024–2032 | 节气显示整体消失（`nextTerm` 先失效） | `nextTerm` 2032-12-22 / `termOn` 2033-01-01 |
| 放假安排 | 2025-01-01 ~ 2026-10-10 | 全部返回 `.normal` | **2027-01-01** |
| 黄历离散库 | 2024–2028 | 落到算法兜底（同一算法，质量不变） | 2029-01-01 |

- **做什么**
  1. 加**开发期可见的到期提醒**：数据窗口临近（如剩余 90 天）时在 CI 或测试里告警
     （比运行时横幅更合适——这是开发者要处理的事，不是用户的问题）。
  2. 放假表年度更新流程文档化，**并明确 `HolidayProviderTests.swift:61-72` 把错误行为写成了断言
     （断言 2027-01-01 为 `.normal`），补数据时必须同步改测试**。
  3. 修正过期注释：`SolarTermProvider.swift:6` 与 `FestivalManager.swift:148` 写的「2025–2028」
     实际是 2024–2032，`HuangliDBProvider.swift:41` 写的 385 KB 实际 436 KB。
- **验收**：CI 中有一条能在到期前失败的检查；放假表补到 2027 且测试同步更新。
- **备选（需你裁决）**：是否改为「运行时按需计算节气」以彻底摆脱 9 年窗口——改动大，
  但能一次性消除这个悬崖类别。

---

## 五、P3 · 界面与无障碍

> 这些是用户直接可见、但改动量小的问题。**建议在 P1 完成后穿插进行。**

| 任务 | 做什么 | 验收 | 备注 |
|---|---|---|---|
| **P3-1 节日对比度** | `Views/CalendarMonthView.swift:507-508` 把未校验的 `festivalTint` 当填充色，`Views/CalendarComponents.swift:250` 强制白字 → 儿童节 1.40:1、中秋 1.97:1。改为按亮度选前景色（黑/白）或改用描边强调 | 新增测试覆盖**这条真实路径**（现有 `AccentContrastTests` 只测助手函数），而非仅助手 | 首屏问题，优先 |
| **P3-2 横屏根视图** | `App/LunisolarCalendarApp.swift:93` 用 `horizontalSizeClass == .regular` 切根视图 → Plus/Max iPhone 横屏变 iPad 三栏、TabBar 消失。改为按 `userInterfaceIdiom` 或同时判宽度 | iPhone 横屏保留 TabBar；iPad 仍三栏 | 项目自己的 `DEVICE_TEST_CHECKLIST.md:267` 标注未验证 |
| **P3-3 修 3 处漏译** | `Views/WeatherCardView.swift:101`、`Views/SelectedDayCardView.swift:46`、`Views/CalendarMonthView.swift:381`（`Text(verbatim:)` 让英文界面显示「9月」） | 4 语言表 key 齐备；英文界面实测无中文 | 小改动 |
| **P3-4 Dynamic Type 截断** | 大号数字（`numeralXL` 56pt）被限制在 `.frame(width: 92)` / `.frame(width: 110)`（`Views/SelectedDayCardView.swift:23-31`、`Views/DayDetailView.swift:85-92`）→ 辅助字号下截断 | 最大辅助字号下不截断、不重叠 | 无障碍硬缺口 |
| **P3-5 性能** | ①`Views/AllEventsView.swift` 每次 body 约 10 轮 O(N) 全量扫描（`:337-341` 起），搜索逐键触发 → 改为算一次缓存；②`Views/YearOverviewView.swift:193-238` 主线程同步算 365 天 + 每日新建 `DateFormatter` + 约 440 个 `AnyView` → 移到后台/复用 formatter | 大库（数百事件）下横滑与搜索无卡顿 | 建议先加性能基线再改 |
| **P3-6 无障碍覆盖** | 29 个视图文件中 23 个零 `accessibilityLabel/Hint`；年视图约 440 个可点格无标签/ID 且点击目标 16–20pt（低于 44pt HIG） | VoiceOver 能走通月历/年视图/日期跳转 | 可与 P4-1 合并 |

---

## 六、P4 · 维护性（明确可延后，暂不启动）

| 任务 | 内容 | 启动条件 |
|---|---|---|
| **P4-1 无障碍系统化** | 把 `AccessibilityID` 补到倒数日行、全部日程行、设置行；统一 `accessibilityLabel` 规范 | P3 完成后 |
| **P4-2 数据可信度标识** | `AI_DEVELOPMENT_CONTEXT.md` §6 要求区分「验证库 vs 算法推算」。**注意：现有 `.discreteDB` 枚举不是可信度信号**（离散库就是算法自身输出，0 差异） | 需先有真实外部数据源 |
| **P4-3 大文件拆分** | `Stores/EventStore.swift` 992 行、`Widgets/LunisolarWidgetViews.swift` 894 行、`Sync/RealCloudKitProvider.swift` 636 行 | 仅在改动这些文件时顺带拆 |
| **P4-4 目录重排** | `Features/`/`Domain/`/`DesignSystem/` | **不建议做**：功能等价、只改路径（详见 `PROGRESS_ANALYSIS_2026-09-25.md` §4-C） |

---

## 七、测试补强（横跨各阶段，按需随任务进行）

现状：328 单测 + 12 UI 测试（10 流程），无单元测试 target（单测走 SPM）。**主要缺口**：

| 缺口 | 何时补 |
|---|---|
| `RealCloudKitProvider` 全部路径、Mock↔Real 契约、等版本 LWW、双设备冲突 | **P1-1 一并做** |
| `SyncStatus` 状态迁移、墓碑 TTL 清理、`versionMap` 跨实例持久化 | P2-2/P2-4 |
| 部分损坏（vs 整文件损坏）、`importJSON` 畸形输入、缺 DTSTART、不可解析 TZID | P2-1 |
| 喜神/财神 vs 日干规则、农历表穷举 oracle（现有只覆盖 5 个年份）、节气 vs 星历 | P1-2 / P4-2 |
| UI 测试盲区：编辑/删除、全天、重复规则、提醒、倒数日增删、导入、深色模式、Dynamic Type、en/ja、VoiceOver | P3 各项 |
| `xcodebuild test` 补一个单元测试 target（可选） | P4 |

---

## 八、需要你裁决的事项（阻塞项）

| # | 事项 | 阻塞谁 | 说明 |
|---|---|---|---|
| ~~D1~~ | ~~工作区快照与远端仓库的关系~~ | ~~P0-1~~ | ✅ **已裁决（2026-09-30）：对齐远端仓库历史**。远端 `main` = `1cc0b7f`，工作区内容与之一致；但因无 `.git`，需重新 `clone` 后搬改动（详见 P0-1） |
| ~~D2~~ | ~~喜神/财神采用哪套口诀~~ | ~~P1-2~~ | ✅ **已由证据解决（2026-09-30）**：不是「任选变体」——日干规则有《喜神方位歌》《财神方位歌》古籍出处，且 tyme 权威库实现一致，二者取值域各为 5 个。替代了原先「日支」假设。详见 `HANDOFF_REVIEW` §6 复核小节 |
| D3 | **中国锚业务时区是否立项** | P2-4 / P4-2 | 海外用户看到清明/黄历差一天（纽约 2026-04-04 vs 北京 04-05）。这是**产品决策**，不是 bug：`QingheCalendarContext.swift:8-16` 主张用中国时间，但节气/黄历实际按设备本地日归属（`TimeZoneGoldenTests:117-138` 有意锁定） |
| D4 | 节气是否改为运行时计算 | P2-4 | 可一次性消除 9 年窗口，但改动大 |
| D5 | 通知权限是否改到「首次添加提醒时」请求 | 未排期 | 现在只在设置页请求（`SettingsView.swift:146-150`），从不打开设置的用户**永远收不到通知**，而 `NotificationManager.swift:56` 的注释说会请求 → 注释与实现矛盾 |
| D6 | **是否恢复导出/备份入口** | P2-1 | 远端 `1cc0b7f` 说明导出 UI 是**被主动移除**的产品决策、三个 `export*` 函数有意留作测试镜像。所以这是产品决策而非代码缺陷（详见 `HANDOFF_REVIEW` §4 B5 的更正） |

---

## 九、里程碑与验收

| 里程碑 | 内容 | 验收标准 |
|---|---|---|
| **M0 可验证** | P0 全部 | 四通道全绿 + CI 绿 + 可回滚；`HANDOFF_REVIEW` 中 §1 的四处修复已进提交历史 |
| **M1 数据可信** | P1 全部 | 同步不再分叉（有测）；喜神/财神符合日干规则（有测）；单例泄漏清零 |
| **M2 数据安全** | P2 全部 | 有导出/备份；存储可迁移且逐条容错；同步状态可恢复；三处悬崖有预警机制 |
| **M3 体验达标** | P3 全部 | 首屏对比度合规；横屏正确；0 漏译；最大辅助字号不截断；大库无卡顿 |
| **M4 上架就绪** | P3 + `docs/APP_STORE.md` 清单 | 真机走查 `DEVICE_TEST_CHECKLIST.md`；4 语言截图；性能测试 |

**贯穿性纪律（每个任务都必须遵守）**

1. **小步提交**：一个任务一次提交，提交信息说明「改了什么 + 为什么 + 如何验证」。
2. **先测后改**：P1-1、P1-2、P2-1 这类核心路径，**先补能复现问题的测试，再改行为**。
3. **实跑验证**：任何标「已完成」前，必须实跑 `Tools/run_tests.sh`——
   本仓库已有多次「文档声称完成但从未编译」的先例（见审查报告 §1、§9）。
4. **不改注释就改代码**：发现注释与实现矛盾时，一并修正注释（如 `NotificationManager.swift:56`）。
5. **不机械对齐文档**：文档与代码冲突时以代码为准，并在本文件或审查报告里记录偏离。

---

## 十、建议的第一周安排

| 天 | 事项 |
|---|---|
| 第 1 天 | P0-1 Git 基线（已裁决对齐远端；需在正常终端 `clone` 后搬改动 + 修 `.gitignore` 的 `*.json`） |
| 第 2 天 | P0-2 跑通四通道 + P0-3 CI 转绿 |
| 第 3–4 天 | P1-1 CloudKit（**先补测试**，再改行为）|
| 第 5 天 | ~~P1-2 喜神/财神~~ ✅ 已完成 2026-09-30 |

> P1-3 单例泄漏、`.gitignore` 修复、**P1-2 喜神/财神**均**已于 2026-09-30 完成**（见对应小节）。

之后再按 P2 → P3 推进；P4 不排期。

