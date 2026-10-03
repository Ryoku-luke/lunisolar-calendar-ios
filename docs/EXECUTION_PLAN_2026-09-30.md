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
| **P0** | 安全底座 | ~~P0-1 Git 基线~~ ✅ · P0-2 四通道跑通 · ~~P0-3 CI 转绿~~ ✅ | 有可回滚的提交历史；`Tools/run_tests.sh` 四通道全绿；CI 在 main 上绿 |
| **P1** | 数据正确性（高危） | ~~P1-1 CloudKit 版本校验~~ ✅ · ~~P1-2 喜神/财神用柱~~ ✅ · ~~P1-3 单例泄漏清除~~ ✅ | 双设备同步不再分叉；喜神/财神符合日干规则；UI 测试隔离真正成立 |
| **P2** | 数据安全与悬崖 | P2-1 导出/备份+迁移 · P2-2 同步状态卡死 · P2-3 导入覆盖 · P2-4 数据到期机制 | 用户能造出备份；同步状态可恢复；导入不再静默覆盖；到期前有预警 |
| **P3** | 界面与无障碍 | P3-1 节日对比度 · P3-2 横屏根视图 · P3-3 漏译 · P3-4 Dynamic Type · P3-5 性能 | 首屏可读性合规；Plus/Max 横屏正确；0 漏译；辅助字号不截断 |
| **P4** | 维护性（可延后） | P4-1 无障碍覆盖 · P4-2 数据可信度标识 · P4-3 大文件拆分 | 仅在有明确收益时做 |

**建议节奏**：P0 必须一次做完（半天量级）；P1 逐项独立提交；P2/P3 可穿插；P4 暂不启动。

---

## 二、P0 · 安全底座（最高优先，必须先完成）

> 目标：把「无法验证、无法回滚」变成「可验证、可回滚」。**在 P0 完成前不要动任何功能代码。**

### P0-1 建立 Git 基线 ✅ 已完成（2026-09-30）

> **结果**：用户已把全部改动同步到远端 `main`，最新提交
> **`50ab407`**「fix(9/30): 同步用户侧修复（编译阻断/历法/测试隔离/清单）」
> （其后是 `b3ec5e4` 真机清单闭环）。工作区现已对齐该提交、`git status` 干净、共 128 个提交。
> 本轮全部改动（§1 四处编译阻断 + P1-2 喜神财神 + P1-3 单例隔离 + `.gitignore`
> + 两份文档）**均已在 `50ab407` 中**，`Assets/.../Contents.json` 也已纳入版本控制。
>
> ⚠️ **一处交接细节**：本会话工作目录 `~/Downloads/lunisolar-calendar-ios-main/` 现已确认
> 是**完整 Git 仓库**（`origin` → GitHub，`main` 跟踪 `origin/main`，HEAD = `50ab407`）。
> 若你在别的路径也有克隆，用 `git log -1` 看是否为 `50ab407` 来判断该用哪个。

<details><summary>原计划步骤（已由用户执行完成，保留备查）</summary>

> **前置已裁决（2026-09-30）**：D1 = **对齐远端仓库历史**。
> 远端 `main` 当时 = `1cc0b7f`；本工作区内容与该提交逐文件一致（已核对），
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

</details>

### P0-2 跑通通道验证 ✅ 已完成（2026-10-02）

- **做什么**：正常终端执行 `Tools/run_tests.sh`（四通道串行）。
- **已知预期**：前两条（`swift test` + iOS SDK 构建）应绿；**后两条 UI 测试从未在本次审查中跑过**，是主要未知项。
- **若 UI 测试失败**：按 `/tmp/run_tests.*.log` 定位。注意脚本默认 `OS_VER=26.5`、
  机型 `iPhone 17 Pro` / `iPad Pro 11-inch (M5)`，本机均存在；
  若机型/OS 不符，用 `OS_VER=27.0 Tools/run_tests.sh` 或 `IPAD_SIM=…` 覆盖。
- **验收**：脚本输出「✅ 全部通过」，**5 条**通道全绿（2026-10-02 起多了第 3 条「UI 测试 target 类型检查」）。
- **不做**：不要在此时修 UI 测试的业务断言（那是 P3 的事），只确认通道能跑、能判定。

> **2026-09-30 实测记录：`xcodebuild` 在 DSH 会话沙箱内不可用（环境限制，非项目问题）**
>
> 本会话已把三条不需要 Xcode 的通道跑到全绿：
> `swift build`（macOS）✅ · `swift build --triple arm64-apple-ios17.0-simulator` ✅ ·
> `swift test` × 4 时区 **332 用例 0 失败** ✅。
>
> 但 `xcodebuild` 反复失败于依赖解析，根因已定位清楚，**与项目无关**：
>
> ```
> xcodebuild: error: Could not resolve package dependencies:
>   cannot open file '~/Library/Caches/org.swift.swiftpm/manifests/ManifestLoading/
>   lunisolar-calendar-ios-main.dia' for diagnostics emission (Operation not permitted)
> ```
>
> Xcode 内置的 SwiftPM 要写**固定的全局缓存** `~/Library/Caches/org.swift.swiftpm`，
> 而会话沙箱只允许写工作区内路径。已尝试且**均无效**：
> 重定向 `TMPDIR` / `CLANG_MODULE_CACHE_PATH` / `-clonedSourcePackagesDirPath`、
> 覆盖 `HOME`（macOS 经 `pwuid` 解析真实家目录，不认 `$HOME`）、
> 把该缓存目录换成指向工作区的符号链接（沙箱拒绝 `rm`）。
>
> **因此 P0-2 的两条 UI 测试通道仍必须在正常终端做。**
> 请执行 `Tools/run_tests.sh` 并回传汇总行。

> ✅ **补充（2026-09-30，CI 截图证实）**：P0-2 的前三条通道已在 GitHub Actions 上
> **独立复现并通过**——见下方 P0-3。也就是说「本地绿」不是环境侥幸。
> 仅剩两条 UI 测试通道（`Tools/run_tests.sh` 的后两条）从未跑过。

> 🚨 **2026-10-02 实测：第一次真跑 UI 测试通道，炸的不是断言，是编译**
>
> 用户在正常终端执行 Flow 3d 用例（带 `-only-testing:`），`LunisolarCalendarUITests`
> **编译失败**：
>
> ```
> LunisolarCalendarUITests/LunisolarCalendarUITests.swift:363:39:
>   error: type 'ID' has no member 'aiGoToCreatedDay'
> ```
>
> 根因：UI 测试 target 没有链接 App 框架模块，`LunisolarCalendarUITests.swift` 里
> 维护着一份 `AccessibilityID` 的**字面量副本**（`private enum ID`）。Flow 3d 提交
> `ea51f25` 只在 App 侧加了 `aiGoToCreatedDay`，副本没跟。而 UI 测试 target **不在
> SwiftPM 包里**，`swift test` 根本看不见它——所以当时「356 用例 × 4 时区全绿」
> 与这次编译失败**可以同时成立**。
>
> 这也推翻了副本注释里「失配不会静默」的假设：它不静默，但它只对 `xcodebuild` 出声。
>
> **本次新增的两道防线（已实证）**
>
> 1. **UI 测试 target 的类型检查**（`Tools/typecheck_uitests.sh`，秒级、不需要 DerivedData、
>    不碰模拟器，已接进 `Tools/run_tests.sh` 作为第 3 条通道）：
>
>    ```bash
>    Tools/typecheck_uitests.sh        # 成功打印 UITESTS_TYPECHECK_OK
>    ```
>
>    内部就是一次 `swiftc -typecheck`。关键点是 `-Isystem …/Developer/usr/lib`——Swift 版
>    XCTest 断言（`XCTAssertTrue` 等）来自那里的 `XCTest.swiftmodule`，不是
>    `XCTest.framework` 的头文件（头文件里只有 C 宏，Swift 会报
>    「function like macros not supported」，看起来像环境坏了，其实是少这一条路径）。
>    **证伪**：删掉副本里那行 → 脚本 `EXIT=1` 并复现用户看到的同一条报错；加回 → `EXIT=0`。
>
> 2. **`Tests/LunisolarCalendarTests/UITestIDMirrorTests.swift`**（4 项，随 `swift test` 跑）：
>    从源码解析那份副本，对照 `AccessibilityID.all` 检查
>    ①引用到但没定义的 `ID.*` ②副本字面量不在 App 侧目录 ③副本内重名重值
>    ④`monthDay` 格式与 App 侧逐位一致。
>    **证伪**：四种人为漂移各造一次，分别被对应的那一条拦住（4/4）。
>
> **提醒**：`xcodebuild` 在会话内仍然不可用，这次又确认了一条新死路——
> `CFFIXED_USER_HOME` 重定向家目录后 SwiftPM 会调 `sandbox-exec`，而嵌套沙箱
> 被拒（`sandbox-exec: sandbox_apply: Operation not permitted`）。
> 所以**两条 UI 测试通道依然必须在正常终端跑**：`Tools/run_tests.sh`。
>
> **教训（写给下一个接手的人）**：只要改了 `AccessibilityID.swift`，就必须同步
> 副本；`swift test` 绿 **不等于** UI 测试 target 能编译。
>
> **同日第二次真跑（补齐编译后）**：用例终于执行到了断言，结果**抓到一个真实产品缺陷**
> ——「去看看」按钮从未渲染（见 §八点五 的更正）。这正好说明这条通道的价值：
> 它第一次跑就否掉了「已实施」的结论。现场证据（屏幕录制逐帧）已归档在 §八点五。
>
> ✅ **第三次真跑：Flow 3d PASSED**（18:48，19.9 秒）。`LunisolarCalendarUITests` 这个
> target 从「从未编译过」到「一条用例全绿」，用了三次真跑。
> **仍未跑**：该 target 里其余 13 条用例（见 §七 的下一步）。

> **第四次真跑（全量 5 通道）**：4 绿 1 红——**iPhone UI 通道 11/11 通过**（0 失败，
> 3 条按设计跳过），红的只有一条 Flow 3c：它写死「今天下午3点」，而
> `AICommandValidator` 会（正确地）拒绝落在过去的一次性日程，18:54 跑必红。
> 已修（`laterTodayText()`：现在 + 1 小时，距零点 <5 分钟则 `XCTSkip`）。
> iPad 通道 5/5 通过（Flow 1/2/4/6/9），其余按设计跳过。
>
> **第五次真跑**：iPhone 11/11 ✅（Flow 3c 修复确认），**iPad 通道红在基础设施**——
> `Failed to install or launch the test runner … SBMainWorkspace … Busy
> ("Application failed preflight checks")`，一条用例都没跑；同一通道上一轮 5/5。
> 已给 `Tools/run_tests.sh` 加对症处理：两条 UI 通道开跑前 `simctl shutdown all`，
> 且只在 `FLAKY_INFRA_PATTERN` 白名单上重试一次（真实断言失败**绝不**重试）。
> 重试逻辑用假通道验证过：抖动通道重试后计通过、真实失败通道立即计失败。

> ✅ **第六次真跑：5 条通道全绿**（`✅ 全部通过`）。P0-2 到此真正完成——
> 两条 UI 测试通道从「从未跑过」变成「全量跑通」：iPhone 11/11、iPad 5/5
> （其余按设计跳过），加上单测 360 × 4 时区、iOS SDK 构建、UI 测试 target 类型检查。
> 期间在该通道上抓出并修掉的缺陷（全部有实跑证据）：ID 副本漏同步（编译不过）、
> `.containing` 误用、事件行精确匹配、标题被解析器啃字、
> 「去看看」按钮从未渲染（**真实产品缺陷**）、Flow 6 必红断言、Flow 3c 写死时刻、
> 以及一次纯粹的基础设施抖动（已给闸门加预清理 + 白名单重试）。

### P0-3 让 CI 真正转绿 ✅ 已完成（2026-09-30）

> **结果**：`main` 分支 `50ab407` 的 CI **全绿**（用户截图证实）：
>
> | Job | 结果 |
> |---|---|
> | `CI / build-and-test (push)` | ✅ Successful in 2m |
> | `CI / hardcoded-font-gate (push)` | ✅ Successful in 5s |
>
> **这个结果的价值**：`build-and-test` 在 `macos-26` 干净 runner 上跑正是
> `swift build` + `swift test` × 4 时区 + iOS SDK 构建——即**独立复核了本地三通道**，
> 排除了「本机缓存/环境侥幸通过」。同时证明 §1 修的三处编译阻断是真修复，
> 而非把 CI 绕过；字号红线也仍健康。
>
> ⚠️ 注意 CI **不跑 UI 测试**（设计如此，见 `ci.yml:27-29`：双端模拟器在 runner 上慢且不稳），
> 所以 `LunisolarCalendarUITests` 的 12 条用例至今**仍未被任何自动化执行过**。
> 这是目前最大的未验证面 → 见 P0-2 结尾。


> **P0 完成后的状态**：项目从「不可编译、不可测试、不可回滚」变为「三通道可验证 + CI 门禁 + 可回滚」。
> 这是后续所有工作的前提。

---

## 三、P1 · 数据正确性（高危，逐项独立提交）

### P1-1 修复 CloudKit 推送的版本校验缺失 ✅ 已完成（2026-09-30）

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

#### P1-1 实施结果（2026-09-30）

**根因**：Mock 与 Real **各自实现**了 last-write-wins，语义还不同——
Mock 显式比 version 并拒绝陈旧推送，Real 只 fetch change tag 就**无条件覆盖**。
所有同步测试只跑 Mock，所以真机上的分叉在 CI 里永远看不见。

**改了什么**

| 文件 | 改动 |
|---|---|
| **新增** `Sync/SyncConflictResolver.swift` | 把 LWW 收成**纯函数**（`resolve(incoming:existing:)` + pull 侧 `shouldAdoptRemote`），并写明「不得让低版本覆盖高版本」的原因。纯函数化的关键理由：`RealCloudKitProvider` 在测试进程里**无法构造**（entitlement 预检使容器恒为 nil），规则必须可脱离 CloudKit 验证 |
| `Sync/MockCloudKitProvider.swift` | push 的 LWW 判定 + store `upsert` 都改调共享规则（原先各内联一份），行为逐字不变 |
| `Sync/RealCloudKitProvider.swift` | **核心修复**：push 在覆盖前比对版本，云端更高时记 per-record `.conflict` 并**跳过写入**；并新增 `isRecordAbsent` —— 只有 `CKError.unknownItem` 才算"云端无此记录"，**其余 fetch 失败（网络/限流/鉴权）必须报错并保留脏标记**，绝不能当成"不存在"去新建（那会绕过 LWW 直接覆盖）；另加 `guard database != nil` 防御空数据库 |
| `Sync/EventSyncCoordinator.swift` | ① pull 的采纳判定改走 `shouldAdoptRemote`，与 push 侧同源；② **修水位线缺陷**：只允许用「已采纳/已按墓碑删除」的记录推进 `lastSyncMs`，不再用 `remote.map(\.updatedAtMs).max()` 迈过被拒记录 |
| **新增** `Tests/.../SyncConflictResolverTests.swift` | 10 条：7 条纯规则 + 2 条**契约测试**（用同一组场景锁住 Mock 行为与纯规则一致）+ 1 条 pull 规则 |
| **新增** `Tests/.../SyncDivergenceConvergenceTests.swift` | 2 条**双设备**端到端：两台独立 store/UserDefaults/provider 共享一个云端，验证等版本分叉**一轮收敛**且不静默丢数据 |
| **新增** `Tests/.../SyncWatermarkTests.swift` | 2 条：被拒记录必须仍可拉（隔离水位线缺陷）+ 已采纳记录必须推进水位线（防重复拉） |

**测试有效性已证伪**：把规则临时改成"无条件接受"（模拟修复前 Real 的行为），
**10 条里 9 条失败**，且失败信息直指数据分叉路径——

```
testRejectsLowerVersionAgainstNewerServer : ("accept") is not equal to ("rejectHigherVersionOnServer")
    - 陈旧设备（低版本）不得覆盖云端更新记录——这就是 P1-1 的数据分叉路径
testContract_MockProviderMatchesSharedRule : ("1") is not equal to ("0")
    - v3 不得覆盖云端 v5——修复前 Real 正是在这里覆盖
testContract_MockStoreUpsertRejectsLowerVersion : ("Optional(3)") is not equal to ("Optional(5)")
```

**验收（实跑）**：macOS 构建 ✅ · iOS SDK 构建 ✅ ·
`swift test` **346 用例 × 4 时区 0 失败** ✅（328 → 346）。
另用「注入语法错误」探针确认 `RealCloudKitProvider` 确实参与 iOS 编译
（探针使 iOS 构建报 5 条 error → 该文件不是死代码，改动真的被编译）。

#### ⚠️ 收敛测试又挖出第三个缺陷（已修）：增量水位线会迈过「被拒绝」的记录

写等版本分叉的收敛测试时，测试**没通过**，暴露出一个独立的、更隐蔽的缺陷：

`pullAndMerge` 原来用 `remote.map(\.updatedAtMs).max()` 推进增量水位线——
把**被拒绝**的记录也一起迈过。而下一轮 pull 的谓词是 `updatedAtMs > sinceMs`，
于是那条记录**再也拉不回来**，永远无法合并 → 正是「永久分叉」本身。

**修复**：只有**真正处理掉**（采纳 / 按墓碑删除）的记录才允许推进水位线
（`EventSyncCoordinator.pullAndMerge` 改为累加 `mergedMaxMs`）。

**这个修复是经过证伪验证的**：用一个隔离探针（注入等版本但内容不同的云端记录 →
第一轮 pull 被拒 → 检查该记录是否仍可拉取）：

| 实现 | 结果 |
|---|---|
| 旧逻辑（`remote.map(\.updatedAtMs).max()`） | `record-still-pullable = **false**`（永久不可合并）❌ |
| 新逻辑（只算 `mergedMaxMs`） | `record-still-pullable = **true**` ✅ |

修复后**等版本分叉一轮 sync 即收敛**（收敛测试断言 `cycles == 1`），
比原先以为的「两轮」更好。同时这也让既有测试 `testIncrementalPull` 暴露出一处
**固化了错误行为**的断言（它断言「pull 到 0 条时水位线也必须推进」，而这正是 bug 的来源），
已按真实意图改写为「采纳了 3 条之后水位线才应推进」。

**代价（如实记录）**：未被采纳的「自身回声」每轮会被重拉一次。这不改变内容、
不影响正确性，但理论上随本地记录数增长。彻底解法是改用 CloudKit 原生
`CKServerChangeToken` 增量机制（`AI_DEVELOPMENT_CONTEXT.md` §11 已把它列为未来方向）。

**仍未做（诚实记一笔，勿当成已解决）**

1. **`RealCloudKitProvider` 仍无真机/集成测试**（本环境无法构造容器——它做 entitlement
   预检，容器恒为 nil）。
   本次修复靠的是「共享纯函数 + 契约测试 + 隔离探针 + iOS 编译验证（注入语法错误确认该文件
   确实参与 iOS 编译）」，**真机双设备同步仍需人工走查一次**。
2. **自身回声每轮重拉**（见上，正确性无碍，属性能债）。

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

> ✅ **2026-10-02 已完成：存储格式版本 + 目录级迁移机制**（导出入口仍卡 D6）
>
> **落地了什么**（`Sources/LunisolarCalendarApp/Stores/StorageFormat.swift` 新增）：
> - 独立小文件 `storage_format.json` 记版本，**不动数据文件本身的形状**——
>   旧版 App 仍能照常读裸数组，只是不认识这个标记（不会因此报错）；
> - **无标记 = v1**（本机制落地前的历史格式）；**标记存在但读不懂 = 不确定**，
>   一律拒绝写（`MigrationError.markerUnreadable`），绝不猜着当 v1 迁移；
> - 迁移按 `StorageMigrator.registered` **逐级执行**，缺一环直接报错（不许跳过，
>   跳过就是带着旧结构继续跑）；**只在全部成功后才落版本标记**；
> - 磁盘版本比本 App 新（用户回退到旧版 App）→ `EventStore.storageIsReadOnly = true`，
>   该实例**不写这个目录里的任何文件**（事件 / dirty 标记 / 隔离文件全跳过）。
>   取舍写死在注释里：不落盘只是这次会话的改动丢失，覆盖写却会把新版本的数据连同
>   它认识不到的字段一起抹掉。数据仍尽力读出来给用户看。
> - `storageIsReadOnly` 会让第 4 条**每次读盘都不写盘**成立：全新目录、历史目录、
>   只读目录三种情况下，目录内容都逐字节不变（有测试用目录快照钉住）。
>
> **为什么现在注册表是空的（重要，别误以为是没写完）**：`current = 1`，当前**没有**
> 已知的格式变更需要迁移——`startDay/endDay` 这类历史演进早已用
> `decodeIfPresent` + 「旧 payload 整块跳过」兼容掉了。所以这一版交付的是**机制**：
> 下次改字段语义 / 枚举 rawValue 时「有地方可写、有测试可依」，
> 而不是又一个事后一次性脚本。它立刻兑现的价值是**回退保护**（D 类事故里最静默的一种）。
>
> **它自己的测试当场抓到过一个真实缺陷**：版本标记原先把 `updatedAt` 存成 ISO8601
> （写侧 `dateEncodingStrategy = .iso8601`），读侧却用默认数字策略 → 标记**刚写完就读不懂**
> → 整个存储被误判成「版本不确定」而切成只读。已改成 Unix 秒，彻底去掉策略耦合。
>
> **验证**：369 用例 × 4 时区 0 失败（新增 `StorageFormatTests` 9 条）；
> macOS + iOS SDK 构建；UI 测试 target 类型检查；
> ✅ **五通道全绿**（`Tools/run_tests.sh`，2026-10-02）——覆盖「迁移在正常目录上无副作用」。
> **证伪**：对实现造 5 种突变，**5/5 分别被对应的那条用例拦住**——
> 去掉只读守卫 →「只读目录逐字节不变」红；标记读不懂当 v1 →「不确定必须拒绝」红；
> 先落标记再迁移 / 缺环跳过 / 迁移抛错仍落标记 → 两条「迁移失败不得落标记」红。

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

> ✅ **2026-10-02 已完成**（选「保留源时间」这条，没有做冲突弹窗）
>
> **根因更正**：审查报告指到 `CalendarEvent.swift:247`（构造器把 `updatedAt` 写成 `now`），
> 但那个构造器对**真正新建**的事件是对的。真正的缺陷在**两条「构造型」导入路径**——
> 它们把外部数据先构造成本地事件，于是导入时间被当成了记录的修订时间：
> - `importICS`：不解析 `DTSTAMP` / `LAST-MODIFIED`（RFC 5545 的创建/最后修订时间）；
> - `SystemImportMapper`：`SystemImportEvent` 根本没带源修订时间。
>
> 两处都用**确定性 id**（伪 UID / sourceID 哈希）→ 重复导入必然落进
> `merge(policy: .keepLatest)` 的「同 id 冲突」分支，而 incoming.updatedAt = 导入那一刻
> → **必然判「导入更新」** → 本地编辑被静默盖掉，设置页还提示「导入成功」。
> JSON 导入这条路本来就没问题（它走解码、保住了文件里的时间戳），所以只有 ICS 与系统日历中招。
>
> **改法**：
> - `importICS`：解析 `DTSTAMP`（→ `createdAt`）与 `LAST-MODIFIED`（→ `updatedAt`，优先）；
> - `exportICS`：补写 `LAST-MODIFIED`——`DTSTAMP` 的语义是「创建/盖章时间」而不是最后改动，
>   只写它的话，本 App 导出的文件被别人重新导入时同样判断不出新旧（往返一圈就丢修订信息）；
> - `SystemImportEvent` 新增 `sourceModifiedAt`，真实 provider 填 `EKEvent.lastModifiedDate`，
>   mapper 用它写 `updatedAt`（联系人没有这个概念 → nil）；
> - **源文件确实没给时间戳时**保持原来的「导入时刻」语义：源没给时间，只能认为它就是最新
>   （否则导入会永远不生效）。这条反向守卫也有测试，避免把修复做成"导入永远输"。
>
> **验证**：376 用例 × 4 时区 0 失败（新增 `ImportOverwriteTests` 5 条 + `SystemImportTests` 2 条）；
> macOS + iOS SDK 构建；UI 测试 target 类型检查。
> **证伪**：两条「先写测试再改」的用例在**改之前就是红的**（本地编辑被盖回原标题、
> `updated=1`），修完全绿；另对实现造 3 种突变（mapper 不取源时间 / ICS 不取时间戳 /
> 导出不写 LAST-MODIFIED），**3/3 分别被对应用例拦住**。
> ✅ **五通道全绿**（`Tools/run_tests.sh`，2026-10-02）。

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

> ✅ **2026-10-02 已完成「到期防线」部分**（放假表补数据受限于现实：国务院尚未发布 2027 安排）
>
> **落地了什么**：
> - `Tests/.../DataExpiryTests.swift`：三份数据集的到期检查，**两档阈值**——
>   距可信边界 < 30 天**测试失败**、< 120 天**打印告警**（不失败）。
>   30 天的依据：放假安排每年约 11 月底公布，2027-01-01 往前 30 天是 2026-12-02，
>   那时数据已可获取 → 失败是**可行动**的，而不是提前两个月制造噪音。
> - 可信边界取自数据本身（不是写死的常量）：新增 `SolarTermProvider.dataCoverage`
>   与 `HuangliDBProvider.dataCoverage`，放假安排复用已有的 `HolidayProvider.dataCoverage`。
> - **性质区分**：节气与放假是 `correctness`（过期后用户可见地出错）→ 可判失败；
>   黄历是 `degradation`（越界后落到**同一算法**的兜底，质量不变）→ **只告警**。
>   这更正了本节表格把三者并列的口径（审查报告 §4 已更正其"经核验数据"的表述）。
> - 放假安排的可信边界取「**下一个缺失年份的 1 月 1 日**」而不是数据末日
>   （数据末日之后到年底本就没有法定节假日，`.normal` 是正确答案而非降级）；
>   该推导由 `testNovemberAndDecemberHaveNoHolidayEntries` **直接验证**，不靠人记得。
> - `HolidayProviderTests` 里原先把悬崖写成契约的那条断言（2027-01-01 == `.normal`）
>   改成**自更新**：没覆盖就要求「不许编造、退回普通日」，覆盖了就要求「元旦必须是假期」。
> - 修正三处过期注释：`SolarTermProvider`（2025–2028 → **2024–2032**）、
>   `FestivalManager`（同上，且 2029+ → **2033+**）、`HuangliDBProvider`（385KB → **436KB**）。
> - 新增 [`docs/DATA_UPDATE_RUNBOOK.md`](../docs/DATA_UPDATE_RUNBOOK.md)：速查表（覆盖 / 到期日 /
>   表现 / 来源 / 同步哪些测试）+ 放假安排年度流程 + 节气表与黄历库的再生方式 + 检查清单。
>
> **验证**：`swift test --filter DataExpiryTests` 3 条通过，并**真的打印出**
> 「放假安排可信至 2027-01-01，还剩 90 天」的告警；全量 379 用例 × 4 时区 0 失败。
> **证伪**：把 hardFail 阈值放宽到 200 天 → 该用例**立刻红**（失败路径可达）；
> 把 warn 阈值收到 10 天 → 告警消失（告警路径确实由阈值驱动，不是装饰）。
> ✅ **五通道全绿**（`Tools/run_tests.sh`，2026-10-02）。**P2 至此只剩 P2-1 的导出入口（卡 D6）**。
>
> **仍未做（两条，都不是代码问题）**：
> 1. **放假表补到 2027**：国务院通常 11–12 月才发布。到期检查会在 2026-12-02 起硬失败提醒，
>    届时按 runbook §3 走即可。
> 2. **D4 运行时计算节气**：待你裁决（能一次性消除这个悬崖类别，但改动大）。

---

## 五、P3 · 界面与无障碍

> 这些是用户直接可见、但改动量小的问题。**建议在 P1 完成后穿插进行。**

| 任务 | 做什么 | 验收 | 备注 |
|---|---|---|---|
| ~~**P3-1 节日对比度**~~ ✅ 2026-10-02 | `Views/CalendarMonthView.swift:507-508` 把未校验的 `festivalTint` 当填充色，`Views/CalendarComponents.swift:250` 强制白字 → 儿童节 1.40:1、中秋 1.97:1。改为按亮度选前景色（黑/白）或改用描边强调 | 新增测试覆盖**这条真实路径**（现有 `AccentContrastTests` 只测助手函数），而非仅助手 | 首屏问题，优先 |
| ~~**P3-2 横屏根视图**~~ ✅ 2026-10-02 | `App/LunisolarCalendarApp.swift:93` 用 `horizontalSizeClass == .regular` 切根视图 → Plus/Max iPhone 横屏变 iPad 三栏、TabBar 消失。改为按 `userInterfaceIdiom` 或同时判宽度 | iPhone 横屏保留 TabBar；iPad 仍三栏 | 项目自己的 `DEVICE_TEST_CHECKLIST.md:267` 标注未验证 |
| ~~**P3-3 修 3 处漏译**~~ ✅ 2026-10-02 | `Views/WeatherCardView.swift:101`、`Views/SelectedDayCardView.swift:46`、`Views/CalendarMonthView.swift:381`（`Text(verbatim:)` 让英文界面显示「9月」） | 4 语言表 key 齐备；英文界面实测无中文 | 小改动 |
| ~~**P3-4 Dynamic Type 截断**~~ ✅ 2026-10-02 | 大号数字（`numeralXL` 56pt）被限制在 `.frame(width: 92)` / `.frame(width: 110)`（`Views/SelectedDayCardView.swift:23-31`、`Views/DayDetailView.swift:85-92`）→ 辅助字号下截断 | 最大辅助字号下不截断、不重叠 | 无障碍硬缺口 |
| ~~**P3-5 性能**~~ ✅ 2026-10-04 | ①`Views/AllEventsView.swift` 每次 body 约 10 轮 O(N) 全量扫描（`:337-341` 起），搜索逐键触发 → 改为算一次缓存；②`Views/YearOverviewView.swift:193-238` 主线程同步算 365 天 + 每日新建 `DateFormatter` + 约 440 个 `AnyView` → 移到后台/复用 formatter | 大库（数百事件）下横滑与搜索无卡顿 | 建议先加性能基线再改 |
| **P3-6 无障碍覆盖**（年视图 ✅ 2026-10-03；其余待做）| 29 个视图文件中 23 个零 `accessibilityLabel/Hint`；年视图约 440 个可点格无标签/ID 且点击目标 16–20pt（低于 44pt HIG） | VoiceOver 能走通月历/年视图/日期跳转 | 可与 P4-1 合并 |

### P3-6 无障碍覆盖 · 年视图 ✅ 已完成（2026-10-03）

**先纠正计划里的描述**：「年视图约 440 个可点格、点击目标 16–20pt」不准确——
月卡的**命中区域是整张卡**（`.contentShape + onTapGesture`，远大于 44pt），16–20pt 的日期格
只是装饰、本来就不可点。真正的缺口是另外两条：

1. **用 gesture 而不是 `Button`**：VoiceOver 拿不到「按钮」特征与激活语义，
   等于一张读不出用途的图；
2. **整卡没有任何标签**，而卡内 43 个迷你日期格会**逐个**被朗读。

**改法**（视觉与语义拆开）：
- 视觉月卡在外面并 `.accessibilityHidden(true)`；`Button` 只承载语义，
  用 `Color.clear + contentShape` 覆盖整卡命中区；
- 标签 = 月份名（有日程时补「，N 项日程」）+ 提示「选择该月份」（两条新 key × 4 语言）。

**踩到并值得记住的 SwiftUI 行为**：**`Button` 会丢弃 label 内部的 accessibility 修饰符**。
我先试了「Button { miniMonthCard } 里加 `.accessibilityElement(children: .ignore)`」和
「label 内两个网格加 `.accessibilityHidden(true)`」，两种写法实测**卡内 43 个迷你日期格
仍逐个暴露**（UI 测试断言 `card.staticTexts.count == 0` 直接量到 43）。
只有把视觉内容移到 Button **外面**再隐藏才有效——这条已写进代码注释。

**验证**：新增 `testFlow12_...`（第 15 条 UI 测试）——12 张月卡都是按钮、宽高 ≥44pt、
卡内 0 个暴露子元素；并额外断言**点月卡仍会跳月**（结构从手势换成覆盖层按钮，
必须证明点击行为没被破坏）。
iPhone 通道 15 条（3 skip）/ iPad 通道 15 条（10 skip）**全绿**；本地 412 用例 × 4 时区 0 失败。
**证伪**：改回 `onTapGesture` → 测试以「年视图应有名为「一月」的月卡按钮」变红。

**仍待做（P3-6 其余部分）**：`SettingsView`、`QingheUIComponents`、小组件/灵动活动视图等
约 15 个 UI 文件仍是零无障碍修饰符；下一条按「纯图标控件给文本替代 + 关键控件 ≥44pt」推进。

> 🔍 **2026-10-03 续：改为「审计运行中的界面」而不是按 grep 加标签，抓到 2 处真缺陷**
>
> 新增 `testFlow13_allVisibleButtonsHaveReadableLabels`（第 16 条 UI 测试）：走遍四个 Tab，
> 把**标签为空**的按钮全部报出来，并顺带发现「AX 遍历时崩溃」。
> 为什么用审计：**零无障碍修饰符 ≠ 不可读**——`Toggle("显示农历")`、`Button("完成")`
> 本来就朗读正常；真正要修的是「图标控件没有文本替代」，只有问运行中的界面才知道。
> （顺带纠正：`SettingsView` 等 18 个「零修饰符」文件里多数控件是自描述的标准控件，
> 这条启发式误导性很大。）
>
> **实测到的 2 处缺陷（均未修，已记入测试的精确白名单）**：
> 1. **日历工具栏图标菜单**：AX 里按钮元素无标签，名字掉在子 `Image` 上（`label: '编辑'`）；
> 2. **设置页「导入 / 恢复数据」菜单**：同样无标签，且 AX 外框只有 **154.7×20.3pt**（HIG 要 44pt 高）。
>
> **两条修法都试过，都失败（细节值得记住）**：
> - 日历处：把 `.accessibilityLabel` 从 `.pressableFeedback()` 之前挪到之后 + 加
>   `.accessibilityElement(children: .combine)` → **实测无效**（按钮仍无标签），已回退，不留无效改动；
> - 设置处：在 `Menu` 上挂 `.accessibilityLabel` → **app 崩溃**
>   （`EXC_BAD_ACCESS`，栈：`initializeWithCopy for Button/Menu` ← `Section` ← `SettingsView.body`，
>   发生在 XCUITest 抓 AX 快照时）。`children: .combine`、以及 label 内 `.frame`/`.contentShape`
>   同样崩。**对照实验定性**：源码回 HEAD、只留测试 → 不崩；加回改动 → 必崩。
>   即崩溃由该改动引入，不是先天性问题。→ 需要**改结构**（例如把嵌套 `Menu` 换成
>   `NavigationLink` + 选择页）才能修，记为待办。
>
> **白名单的写法**：按「子元素的 accessibilityIdentifier」精确匹配（SF Symbol 名稳定唯一，
> 不会像 frame 那样随字号/机型变、也不会像文案那样随语言变），并且反断言
> 「已知项必须恰好各命中一次」——**某条被修好时那条断言会提醒你去删白名单**。
> 除这两条外，任何新增的无标签控件都会让测试变红。

> ✅ **2026-10-04：设置页那处已修（改结构，不动 accessibility 修饰符）**
>
> 嵌套 `Menu` → **`Button` + `confirmationDialog`**：标准控件自带标签与整行命中区，
> 「先选格式再导入」的防误触语义不变（仍是两选一后才走导入）。修好后：
> - 该行现在**按名字就能找到**（`app.buttons["导入 / 恢复数据"]`），Menu 时代按名字是找不到的；
> - 命中高度达到 HIG（原 20.3pt）；
> - 点开仍给出「从 .ics 日历文件导入 / 从 .json 备份恢复」两个选项（已在用例里断言，
>   证明换结构没把功能换坏）；
> - 白名单从 2 条减到 1 条 —— **反断言果然先红了**（`knownSkipped` 期望 2、实际 1），
>   逼着我把那条删掉，白名单不会烂在原地。
>
> 顺带两条实测记录：
> 1. `confirmationDialog` 的系统「取消」**不在 app 的元素树里**（`app.buttons["取消"]` 无匹配），
>    所以用例把它放在最后、不关对话框（每条用例都会重启 app，无副作用）；
> 2. Flow 13 只在 iPhone 上跑——iPad 没有底部 Tab（设置走侧栏），侧栏各节的按钮审计
>    尚未覆盖，已用 `XCTSkipUnless` 明确跳过并注明待办（否则 iPad 通道必红）。
>
> ✅ **2026-10-04 再续：日历工具栏菜单也修好了，审计白名单已清空**
>
> **根因不是修饰符，而是「光秃秃的 `Image(systemName:)` 当 label」**：
> 换成 `Label(文字, systemImage:)` 后控件立刻有名字了，**不需要任何 accessibility 修饰符**
> （这点关键——给这个 Menu 挂修饰符会崩，见上文）。导航栏里 `Label` 仍只渲图标，
> 已截图确认工具栏外观没有变化（没有冒出「功能菜单」文字）。
>
> 验伪/自证过程同样是白名单反断言先红：期望命中 1 条、实际 0 条 → 逼我删掉最后一条。
> 现在 `knownUnlabeledControls` **为空**，机制保留（将来新增已知项时按同样格式写）。
>
> ✅ **2026-10-04 收尾：审计改为「屏幕清单驱动」，并覆盖到深层界面**
>
> - **Flow 13** 不再写死 iPhone 的四个 Tab，改成 `mainScreens(app)` 清单：
>   iPhone 走底部 Tab（4 个）、iPad 走侧栏（5 节，日历 / AI 助手 / 全部日程 / 倒数日 / 设置）。
>   两者**互斥**（iPhone 无侧栏、iPad 无底部 Tab），所以必须分开写入口。
> - **Flow 14（新）** 覆盖主屏之外的三处：全部日程 / 倒数日 / 年视图（前者两形态各走
>   菜单或侧栏，年视图走「月历标题 → 日期跳转 → 全年视图」）。
>   每处**新起一次 app**——跨界面返回逻辑本身也随形态不同，一次启动约 3 秒，
>   比写三条返回路径可靠得多。
>
> **两个实测坑（都写进了代码注释）**：
> 1. **iPad 竖屏下侧栏是收起的**（Flow 11 清单里就有这条），直接按标识 tap 会以
>    「No matches found」失败；抄 Flow 9 的成熟做法——先转横屏，若仍收起就点系统「显示边栏」。
> 2. iPad 上点月历标题后**「全年视图」入口 5 秒内没出现**，排查方向有三种（面板未展开 /
>    该入口需滚动 / iPad 走了别的入口——侧栏的 `iPadSidebarYear` 已随「年视图改走方案 C」
>    删除）。**未定论前不留假绿**：年视图那屏暂时限定 iPhone，并在用例里写明待办。
>
> **验证**：iPhone 上 Flow 13+14 通过；iPad 上 Flow 13（侧栏 5 节）+ Flow 14（全部日程 /
> 倒数日）通过。两形态审计结果一致：**零无标签控件**，白名单仍为空。
> 本轮只改测试文件，应用源码未动（仍是上次两通道全绿的状态）。

### P3-5 性能 · 基线已建立（2026-10-04）

计划说「主线程算 365 天 + **每日新建 DateFormatter**」——**后半句不符合代码**：
`buildMarks()` 只建了一个 `DateFormatter`（`en_US_POSIX` + `yyyyMMdd` 当分桶键），
事件也只 `filter` 一遍。真正的成本是 **365 天 × (节气查询 + 节日查询)**，
而且它在 `onAppear` 里**同步跑在主线程**上 —— 年视图弹出时的那一下卡顿就来自这里。

**基线（`YearMarksPerformanceTests`，macOS 宿主，10 次采样均值）**：

| 组成 | 耗时 |
|---|---|
| 365 天全扫（节气 + 节日）| **216 ms** |
| ├ 节气查询 | 79 ms |
| └ 节日查询 | 141 ms |

用 `measure` 而不是断言阈值：阈值型性能测试会随机变红（本项目已经因为"环境相关断言"
踩过一次）。这个文件的作用是**回答"值不值得为它改代码"**以及改完是否真的更快。

✅ **2026-10-04：已挪到后台（`@concurrent`）**

改法：`buildMarks()` 拆成三段——`store.events` 在**主线程快照**（store 是主线程隔离的）；
计算体抽成**纯函数** `YearOverviewView.computeMarks(year:events:now:cal:)`；算完在
`Task { @MainActor in … }` 里赋值。`MonthMarks` 补 `Sendable`（跨隔离域回传）。

**这里有个会让优化静默失效的语言细节，值得单独记**：Swift 6.2 起
`nonisolated async` **默认继承调用者的隔离**（SE-0461 `nonisolated(nonsending)`）——
只写 `nonisolated` 的话，这个函数依然在主线程上跑，"挪到后台"变成一句空话且**没有任何报错**。
必须写 **`@concurrent`** 才是"保证在协作线程池上执行"的显式语义。
（本项目的目标是 iOS 17+/Swift 6.2 工具链，这条适用。）

**验证**：
- 新增 `YearMarksBuilderTests`（4 条）——`computeMarks` 抽成纯函数后可直接测，
  正好当这次挪线程的安全网：12 个月的天数、首日星期（表头错位老 bug 的语义）、
  `todayDay` 的年份作用域、中秋 2026-09-25 与霜降 2026-10-23 的落位；
- 419 用例 × 2 时区 0 失败；macOS + iOS SDK 构建 0 警告；iPhone UI（Flow 12 年视图 + Flow 14）通过。

**诚实的边界**：①216ms 的**总计算量没变**，变的是它不再占主线程——年视图弹出时不再卡；
标记晚约 0.2s 出现（Flow 12 用的是前缀匹配断言，不受影响）。
②"确实不在主线程"由**编译器保证**（`@concurrent` 的语义就是不在调用者执行器上跑），
而不是靠一条会抖的计时断言——计时型的并发断言在本项目属于"随机变红"那一类。
③查询本身当时还没变快（见下一条）。

✅ **2026-10-04：查询本身也变快了（节气查询 79ms → 3ms）**

`SolarTermProvider.termOn` 原本是「遍历整张表（≈216 条）+ 逐条 `isDate(_:inSameDayAs:)`」。
改成**二分定位**：`sortedEntries` 按交节**时刻**升序，二分找第一个 `date >= 当日 0 点` 的条目，
落在当日 24h 内就是它。O(log n)（约 8 次比较）且**与时区无关**。

| 组成 | 改前 | 改后 | 提升 |
|---|---|---|---|
| 节气查询 | 79 ms | **3 ms** | ~26× |
| 节日查询（内部含 termOn）| 141 ms | **66 ms** | 2.1× |
| 365 天全扫 | 216 ms | **67 ms** | **3.2×** |

> 🚨 **中途的错误值得单独记：第一版是缓存，被这个仓库的时区金标准测试当场抓住。**
>
> 我先做的是「`yyyyMMdd` → 节气名」的 `static let` 字典缓存——单测立刻红了 6–8 条
> （`TimeZoneGoldenTests`：`termOn` 返回 nil 而不是「立春」）。原因：**节气是绝对时刻，
> 而它"落在哪一天"取决于设备时区**；那个缓存是在**第一个时区**的进程里建好的，
> 之后逐个时区跑就全错。改成二分后四个时区全绿。
>
> 教训（已写进代码注释）：**凡是「时刻 → 本地日」的映射都不能跨时区缓存**。
> 这个坑不是我推理出来的，是仓库既有的时区金标准测试抓出来的——没有它，
> 我会带着一个"只在首个时区正确"的 bug 上线，而它在单一时区的开发机上永远不复现。

**验证**：419 用例 × **4 时区** 0 失败；macOS + iOS SDK 构建 0 警告；iPhone UI 17 条（3 skip）0 失败。

✅ **2026-10-04：节日查询也加了缓存（冷 66ms → 热 0.6ms）**

`festivals(on:)` 的大头是**农历转换**（≈0.18ms/天）。加了「每本地日结果缓存」，
**键里带 `TimeZone.current.identifier`**——正是上一节那个教训的直接应用：农历日同样依赖时区，
不带时区的缓存会重蹈覆辙。缓存用 `NSLock` 保护（年视图现在从后台线程调它）、有容量上限。

| 场景 | 耗时（365 天）| 说明 |
|---|---|---|
| 冷（真算）| 64.4 ms | 每天一次农历转换，无法避免 |
| **热（命中）** | **0.6 ms** | **~100×** |

真实使用走的正是热路径：月历网格每格**每次渲染**都会问一次、年视图一次问 365 天。

> ⚠️ **顺手排掉一个"偶发红"的隐患**：微基准初版把冷热混在一次测量里（首轮冷 66ms、
> 其余热 1ms），双峰分布让相对标准差飙到 **161%**，而 `measure` 对相对标准差有容差
> （默认 10%）→ **实测偶发判红过一次**（某时区 421 条里挂 1 条，重跑又绿）。
> 现在冷/热分开量、每采样放大到 200 遍，三条抖动降到 1.2% / 5.9% / 2.0%，都在容差内。

**剩余**：计划的另一半（`AllEventsView` 每次 body 约 10 轮 O(N) 扫描）仍未做。

> ⚠️ **更正（2026-10-04）**：`934e20c` 的提交信息写的是「421 用例 × 4 时区 0 失败」，
> **两处都不对**——实际 **419 用例**，且那一次 **UTC 有 1 条失败**。
> 原因在我的检查脚本：用 `grep -q "with 0 failures"` 在全量输出里找子串，
> 它会匹配到**分套件**的汇总行（每个 suite 各有一条），于是失败没被拦住，
> 而我照旧在提交信息里写了「0 失败」。
>
> 那条失败是**偶发**的：随后连跑 5 次 UTC 全绿，其余三个时区也干净；**没有抓到它的名字**
> （过滤输出时只留了尾行）。两个怀疑方向（**未定论，只是怀疑**）：
> ①`measure` 型微基站的相对标准差容差；②依赖"今天"的用例在 00:50（刚过午夜）附近跨日。
> **若再复发，先抓全量输出再判断。**
>
> 脚本写法教训：判定必须看**最后那条总计行**（`Executed N tests, with 0 failures`）
> 且 `N` 要对得上，不能用 `grep -q` 在全量输出里找子串。

✅ **2026-10-04 五通道由我本人跑完**（借 iOS 开发插件，不必再请你代跑）：

| 通道 | 结果 |
|---|---|
| swift test | 419 用例 × 4 时区 0 失败（曾偶发 1 条、随后连跑 5 次未复现，见上面的更正）|
| iOS SDK 构建 | Build complete，**0 警告** |
| UI 测试 target 类型检查 | `UITESTS_TYPECHECK_OK` |
| iPhone UI | 17 条（3 skip）**0 失败** |
| iPad UI | 17 条（10 skip）**0 失败** |
| xcodebuild（app target）| 0 error / 0 warning |

**P3-5 只剩**：`AllEventsView` 每次 body 约 10 轮 O(N) 扫描（照年视图那套：先建基线再改）。

**2026-10-04 读了码，把扫描清单钉下来**（`Views/AllEventsView.swift`，454 行）——
计划说「约 10 轮 O(N) 扫描」，读下来确实如此，具体来源是**计算属性被反复求值**：

| 位置 | 扫描 |
|---|---|
| `filteredEvents`（339-340）| **2 遍**（两个链式 `filter`）|
| `pastEvents`（348）| 1 遍（对 `filteredEvents`）|
| `upcomingGroups`（353）| 1 遍 + 分组 |
| `visibleEvents`（364）| 1 遍 |
| `allSelected`（368）| 1 遍 |
| a11y 文案（430）| 又访问一次 `filteredEvents` → **又 2 遍** |

关键点：`filteredEvents` 是**计算属性**，被 `pastEvents` / `upcomingGroups` / `visibleEvents` /
无障碍文案各访问一次 → 每次都重新跑那 2 遍 filter。所以实际扫描次数 ≈ 6–10 遍，
且随事件数线性增长（全量日程页对重度用户最明显）。

**下一步（未开工，建议单开一轮做）**：把这套派生抽成**一次遍历**的纯函数
（如 `AllEventsDerived.compute(events:typeFilter:showCompleted:showPast:now:)`，
单趟分出 filtered/past/upcoming/groups），配一条 `measure` 基线（不同 N：
100 / 1,000 / 10,000 条），然后像年视图那次一样给出改前/改后数字。
**为什么这轮不动手**：这是 454 行视图的派生重构，要改视图取值方式、跑 UI 两通道，
而本轮上下文已接近尾声——半成品比不动更糟。扫描清单与做法留在这里，下轮可直接开工。

✅ **2026-10-04：派生管线已抽成单趟纯函数并量出改前/改后**

新增 `Views/AllEventsDerived.swift`：一遍遍历同时完成「过滤 + 分桶（已过去 / 未过去）」
+ 桶内分组，替代原先 `filter(isPast)` + `filter { !isPast }`（同一条事件判定两遍）。

| N = 10,000 条 | 每趟耗时 |
|---|---|
| 旧多趟模式（与视图原实现同构）| **59.6 ms** |
| 新单趟 `AllEventsDerived.compute` | **28.2 ms**（**2.1×**）|

新增 `AllEventsDerivedTests`（4 条）：单趟分桶与朴素实现**逐元素等价**、`isIncluded` 为假的
事件不落入任何桶、两桶恰好覆盖过滤集，以及上述两条对比基线。

> ⚠️ 基线也踩了同一个坑：单遍 30–60ms 时抖动 10–13%（超 `measure` 默认容差，会偶发判红）。
> 按上一条提交的教训处理——**每次采样跑 5 遍**，抖动降到 3.7%。

**仍未做（下一步）**：把视图接过去。`filteredEvents` 等 5 个计算属性各访问一次就各重算一次，
**真正的收益要靠「每次 body 只算一次并往下传」**（视图取值点要一起改），
预期在 2.1× 之上再省掉 3–6 倍重复求值。这一步要改视图 + 跑 UI 两通道，需单独一轮。

> 🧾 **又一次脚本教训（同一天第二次）**：本轮用
> `out=$(swift test 2>&1); echo "$out" | tail -3 | grep -q "with 0 failures" || FAILED=1`
> 做「有失败就不提交」的闸门，结果**测试 423/0 全绿、脚本却判失败**（还因此跳过了文档那步）。
> 上一轮是 `grep -q` 匹配到分套件行（**漏判失败**），这一轮是 `tail -3` 抓不到总计行
> （**误判失败**）——同一个薄弱点、两种错法。判定不要自己拼 `tail`/`grep`：
> 直接核对 **`Executed N tests, with 0 failures`** 那条总计行，或用插件的解析结论。

**视图重接的取值点清单（2026-10-04 量清，下轮直接用）**：
- `body`（66–192）内各访问一次：`filteredEvents` 在 84 / 87 / 192（**3 次**）、
  `upcomingGroups` 在 87 / 95、`pastCount` 在 104 / 107、`pastGroups` 在 113、
  `isAllSelected` 在 156、`visibleEvents` 在 161 / 172 / 174（**4 次**）；
- 工具栏 280–289 在 `rows(_:)`（233）内部；
- 动作路径（非 body，频率低可保持原样）：`toggleSelectAll` 372–375、
  无障碍文案 430 的 `filteredEvents`。

改法：`body` 顶部 `let derived = AllEventsDerived.compute(...)` 一次求值，body 内引用改走它，
`rows(_:)` 加参数（2 个调用点）；5 个计算属性改为 `derived` 的访问器，让动作路径继续可用。
`visibleEvents` 需要把 `showPast` 纳入 `compute` 入参（它目前由视图状态参与拼接）。
**验收**：iPhone + iPad 两条 UI 通道 + 一条「同一批数据下只算一次」的证据。

✅ **2026-10-04：视图重接已完成**（`body` 顶部一次求值 + 5 个属性改访问器）

- `AllEventsDerived` 增 `visible` 字段（承载原 `visibleEvents` 语义）与 `showPast` 入参；
- `AllEventsView` 新增 `derived` 作为**唯一派生入口**，`filteredEvents` / `pastEvents` /
  `pastCount` / `upcomingGroups` / `pastGroups` / `visibleEvents` 全部改为它的访问器；
- `body` 顶部取一次局部量 `derived`，body 内 10 处取值改走它——**访问器每次访问都会重算**，
  所以关键是"一次求值、往下用"，而不是把属性写得多漂亮。
- 改动**刻意做成"部分替换也仍然正确"**：访问器保留，最坏情况只是某些取值仍走旧路径（慢但不错）。

**护栏**：新增 `testVisibleRespectsShowPast`（折叠/展开时可见行分别等于 `upcoming`、
`upcoming + past`，顺序也要一致）；此前的分组等价与分桶等价断言继续生效。

**验证**：426 用例 × 2 时区 0 失败；macOS + iOS SDK 构建 0 警告；**iPhone UI 17 条（3 skip）0 失败**。
**iPad UI 通道也已补跑：17 条（10 skip）0 失败**——两通道全绿，P3-5 结项。

### P3-4 Dynamic Type 截断 ✅ 已完成（2026-10-02）

**缺陷**：日期胶囊里的数字用 `AppTheme.Font.numeralXL`（基准 56pt，经 `UIFontMetrics`
按 Dynamic Type 缩放），而胶囊写死 `.frame(width: 92)`（当日卡）/ `.frame(width: 110)`（日详情）。
默认字号放得下「31」，辅助档位把 56pt 放大 2–3 倍后数字被裁掉——
**用户把字调大，反而看不见日期**。

**改法两层**（只做第一层是不够的）：
1. **辅助档位改为上下堆叠**：数字独占一行，不再与右侧详情争宽度。
   判据抽成纯函数 `DayCardLayout.axis(for: typeSize)`（`isAccessibilitySize` → 纵向）——
   只放开宽度会让详情列被挤扁、极端档位下互相重叠。
2. **胶囊宽度 `width` → `minWidth`**，并给数字加 `.fixedSize(horizontal: true, vertical: false)`：
   任何档位下都不会被父级压缩成截断；非辅助档位的版式与改动前一致（横排、92/110pt 起）。

**验证**：412 用例 × 4 时区 0 失败（新增 `DayCardLayoutTests` 5 条）；
macOS + iOS SDK 构建；UI 测试 target 类型检查。
**证伪 5/5**：①判据永远横排（回到缺陷）→ 2 条红；②判据永远竖排（过度纠正）→ 2 条红；
③当日卡胶囊退回固定宽度 → 接线守卫红；④日详情不再用 adaptiveCardStack → 守卫红；
⑤当日卡数字去掉 fixedSize → 守卫红。

**诚实说明（本次没能机器验证的部分）**：**渲染结果**——"最大辅助档位下确实不裁切、不重叠"——
单测构造不出带 environment 的 SwiftUI 视图，所以判据与接线有测试、**外观只能靠眼睛**。
已在 `docs/DEVICE_TEST_CHECKLIST.md` 新增 §12 记录复测步骤（含"调回默认字号确认版式未变"）。

> 🔍 **2026-10-03 补记：用截图真正看了一遍最大辅助字号，又抓到两处（已修）**
>
> 借助 iOS 开发插件把 app 装进模拟器、把系统字号拉到最后档
> （`xcrun simctl ui booted content_size accessibility-extra-extra-extra-large`）后截图，
> 发现**主屏**（不只是日期卡）在最大档位下还有两处坏，根因与 P3-4 同一类——
> **`Text` 没被告知「只允许一行」**：
>
> | 现象 | 修前 | 修法 |
> |---|---|---|
> | 年份折成两行 | `202` / `6`（`2026` 被换行切开）| 月/年都补 `.lineLimit(1).minimumScaleFactor(0.6)` |
> | 日期数字逐位换行 | `27` 渲染成 `2`/`7`，整片网格错行 | 格内数字补 `.lineLimit(1).minimumScaleFactor(0.6)`（与农历行一致）|
>
> 两处都在**默认字号下无视觉变化**（放得下就不缩放）。这次是**看截图验证**的：
> 修前/修后的模拟器截图逐项对照，年份回到单行、网格数字单行对齐。
>
> **仍未处理（记下来，不是漏看）**：
> 1. 节气倒计时条在最大档位下把「下一个节气」竖排成三行、和「寒露 还有 5 天」挤成两块——
>    可读但难看，属于需要设计的重排（不是补一个 modifier 能解决的）；
> 2. 月历最后一行会落到 TabBar 之下（网格可滚动，能划到）；
> 3. 节日名在格内被截成「国…」（`lineLimit` + `minimumScaleFactor` 的既有取舍）。

### P3-3 漏译 ✅ 已完成（2026-10-02）

**实际漏了什么**（不是计划里写的 3 处，而是**两处 + 一层缺失的验证**）：

1. `CalendarMonthView` 的月份标题写死 `Text(verbatim: "\(month)月")` → 英文界面显示「9月」。
   改法：新增 `MonthLabel.name(for:locale:)`——**locale 感知但日历固定公历**。
   为什么不用 `Text(date, format: .dateTime.month(.wide))`：那个跟随 `Locale.current` 的**日历**，
   系统区域设为伊斯兰历时月名会变成该历法的月（而下面的网格是公历），
   这类坑在 `DataPortability` 的日期格式化注释里已经踩过一次。
   模板取 `MMM` 而非 `MMMM`：中文/日文的 `MMM` 就是「9月」（与 App 其它日期串一致），
   `MMMM` 会变成「九月」——那是本次修复之外的中文界面变更。英文得 "Sep"。
2. `WeatherCardView` 的 `Text("最高\(max)° 最低\(min)°")` 走 LocalizedStringKey 查表，
   但**4 张表里都没有这条 key** → 英文界面直接显示中文。改成显式 `NSLocalizedString`。
3. 另外扫出 3 条 `NSLocalizedString` 查了表里没有的 key（iPad 详情占位副标题：
   「在此与 AI 对话…」「所有事件按时间线汇集于此」「外观、同步、数据与关于信息」）→ 已补四语言。

**一层缺失的验证（这才是根因）**：4 张 `.strings`（472 key）**此前没有任何测试**——
key 是否齐备、源码查的 key 是否存在，全靠人眼。新增 `LocalizationTests`（9 条）覆盖：
- **A 表本身**：四张表 key 集合一致、无重复 key（`.strings` 会静默取最后一条）、无空翻译；
  解析器必须吃下每一行（解析不了就红，防止解析器与实际文件悄悄错位）；
- **B 显式查表**：源码里 `NSLocalizedString` / `L10n.str` 的 key 在四张表都存在（330 个）；
- **C `Text("字面量")`**：key 也要存在（2 条刻意不翻译的走白名单：版权行、占位破折号）；
- **D 含中文的插值 `Text`**：**必须显式进白名单**——插值后的 key 形如 `%@/%d`，
  源码级推不准，所以用"必须声明"代替"自动判定"。这正是天气那条漏译的类别；
- 月份名本地化 + **公历固定**（伊斯兰历 locale 下不得输出该历法月名）的守卫；
  以及月历标题**接线**的源码守卫（视图里的那一行单测够不着，理由同 P3-2）。

**验证**：407 用例 × 4 时区 0 失败；macOS + iOS SDK 构建；UI 测试 target 类型检查。
**证伪 7/7**：①en 表删一条 key ②四张表都删天气 key ③表内重复 key ④空翻译
⑤月历标题退回写死「(月)月」⑥`MonthLabel` 去掉公历固定 ⑦新增一处含中文的插值 `Text`
—— 分别被 A/B/C/D 与两条守卫拦住。

**仍未做**：纯插值（不含中文）的字面量与 `.stringsdict` 复数规则不在检查范围内（已在测试注释里写明）。

✅ **五通道全绿**（`Tools/run_tests.sh`，2026-10-02）。

### P3-2 横屏根视图 ✅ 已完成（2026-10-02）

**缺陷**：判断「是不是 iPad 那套分栏」用的是 `horizontalSizeClass == .regular`。
但 **iPhone Plus/Max 横屏也是 regular** → 手机被切成三栏、底部 TabBar 消失。
`sizeClass` 回答的是「有多宽」，不是「是什么设备」。

**同一处错误判据其实有 2 个调用点**（计划里只点了根视图那一处）：
1. `AdaptiveRootView`（切根视图，TabBar 消失的那条）；
2. `CalendarMonthView.isIPadSplit`（会让手机套上 iPad 的弹性行高网格布局）。

**改法**：新增 `Support/LayoutIdiom.swift`，判据收敛成一个纯函数
`usesSplitLayout(device:horizontalSizeClass:) = (device == .pad && sizeClass == .regular)`，
两个调用点都走它。保留 sizeClass 这一半是刻意的——iPad 分屏/侧拉的窄栏
（compact）继续回落单栏，这是既有行为，本次不动。宽度为 `nil` 时保守走单栏。

**验证**：398 用例 × 4 时区 0 失败（新增 `LayoutIdiomTests` 9 条）；
macOS + iOS SDK 构建；UI 测试 target 类型检查。
**证伪**：4 种突变 4/4 被拦——①判据退回「只按宽度」→ 3 条红；②**根视图**接线被改回按宽度判
→ 接线守卫红；③**isIPadSplit** 接线被改回 → 接线守卫红；④判据放宽成「手机也算 iPad」→ 3 条红。

**关于测试手段的诚实说明**：两个调用点都在 SwiftUI 视图里（`body` / 计算属性），
单测构造不出带 environment 的 View，所以除了判据的单测之外，另加了一条**只扫这两行代码**的
接线守卫（扫源码、排除注释）。它偏脆（改格式要同步字符串），但它是唯一能发现
「调用点被改回按宽度判」的手段——上面 ②③ 两条突变正是它拦下的。

✅ **五通道全绿**（`Tools/run_tests.sh`，2026-10-02）。

> 🚨 **2026-10-02 用户复核发现：这一版带着 4 条并发警告（已修）**
>
> `LayoutIdiom.current` 读 `UIDevice.current`，而 iOS 26 SDK 里 `UIDevice` 是
> **主线程隔离**的 → 严格并发下 2 条警告 ×2 个读取点 = Xcode 里 4 条 ⚠️：
> 「Main actor-isolated property 'userInterfaceIdiom' can not be referenced from a nonisolated context」。
> 修法：`current` 与 `usesSplitLayout(horizontalSizeClass:)` 标 `@MainActor`
> （消费方全是视图 body 与单测，没有代价）；纯函数那支保持 nonisolated。
>
> **为什么四通道全绿却没发现——这是本次真正的教训**：
> 1. **警告不改变退出码**，而四通道只判「Build complete / 测试 0 失败」；
> 2. 我自己复核时还额外踩了一脚：只看 `tail -1` 的 "Build complete"，把警告整个吞了；
> 3. 这条分支在 **macOS 构建里根本不参与编译**（`#include UIKit` 那段在 `#else` 外面），
>    所以只有 iOS SDK 构建会报——而我恰恰在那条通道上只看了一行。
>
> **已做的根治**：`Tools/run_tests.sh` 现在支持 `CHANNEL_FORBID='warning: '`，
> 在该通道**判定通过的同时**若日志里还有编译器警告就判失败（SwiftPM 缓存噪音在白名单里）。
> 已对「swift test（macOS）」「iOS SDK 构建」「UI 测试 target 类型检查」三条通道启用。
> 用假通道验证过：带警告 → ❌、只有缓存噪音 → ✅、未启用 → 不受影响。
> （过程中还修掉一个 bash 陷阱：`"$name（…）"` 里变量后紧跟中文会被当成变量名的一部分，
> 必须写 `"${name}（…）"`。）

**未做（可选后续）**：真正的行为验收需要**Max 尺寸的 iPhone 横屏**才能暴露
（Pro 尺寸横屏仍是 compact，不会踩到这个 bug）。可以加一条「转横屏后断言 TabBar 仍在」
的 UI 用例，但它只在 Max 机型上才有鉴别力；而把 Max 加成第六条通道会让每次闸门再慢十几分钟。
要手工验证时跑：`IPHONE_SIM="iPhone 17 Pro Max" Tools/run_tests.sh`。

### P3-1 节日对比度 ✅ 已完成（2026-10-02）

**缺陷**：选中一个节日日时，格子填充用的是**装饰层**的节日原色
（`CalendarMonthView` 把 `cell.festivalTint` 传给了 `cellAccent`），而格内文字固定白字
→ 儿童节 `#FDD835` **1.40:1**、中秋 `#F9A825` **1.97:1**、劳动节 `#FB8C00` 2.37:1。

**改法**（选「按亮度挑白/黑」，没有选「压暗填充」）：
- 压暗会把儿童节黄、中秋金洗掉，而识别度正是这两个颜色的价值；
- 挑色则有**数学保证**：任一填充色在白/黑里总有一支达标——两者相等的最坏点在
  亮度 ≈0.179，此时 ≈4.58:1 > 门槛 4.5。
- 填充仍是节日原色（装饰层逐字未动），只把选中格的文字色换成挑出来的那支。

**顺带发现的第二个（更隐蔽的）问题**：选中格里的白字是**半透明**的
（节日名 0.95、农历 0.9）。半透明白合成到填充色上会把对比度拉低——
即便填充按「白字 ≥4.5」校验过，实测 0.95 白字只剩 **4.23:1**、0.9 白字只剩 **3.94:1**。
所以选中格文字统一改为**不透明**（层次感交给字号/字重，不交给透明度）。

**为满足「测试覆盖真实路径而不是只测助手」做的两处抽取**：
1. 决策点抽成 `SelectedCellForeground.resolve(festivalHex:)`——原先写在 `DayCellView`
   （SwiftUI 视图）里，单测够不着；
2. 单格派生抽成 `GridCellModel.derive(...)`——原先在 `CalendarMonthView` 的扩展里（同样是视图）。
   于是测试能用**真实节日**（中秋 2026-09-25、儿童节 2026-06-01）断言
   「填充仍是原色 + 选中字色已切黑」。

**验证**：389 用例 × 4 时区 0 失败（新增 `SelectedCellContrastTests` 10 条）；
macOS + iOS SDK 构建；UI 测试 target 类型检查。
**证伪**：3 种突变 3/3 被拦——①`resolve` 退回「一律白字」（原实现的 bug）→ 4 条红；
②**接线断掉**（`derive` 不再把节日色传进决策点）→ 2 条接线用例红；
③拾色反向（挑更差的那支）→ 6 条红。

✅ **五通道全绿**（`Tools/run_tests.sh`，2026-10-02）。

**遗留缺口 → D8**：`appTint`（`#4B6FF2`）当选中填充时，白字只有 **4.33:1**，本就低于 AA；
不透明化之后农历行从 3.83 提到 4.33，但仍未达标。这条**没有**在本次动它——
无节日日的选中格是品牌色填充 + 白字的既有视觉契约，改填充色或改黑字都属于视觉决策。
现状已被 `testAppTintSelectedFillRemainsAKnownGap` 钉住（改了会红，提醒同步 D8）。

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
| **UI 测试 target 本身能否编译**：它不在 SwiftPM 包里，`swift test` 看不见，改 `AccessibilityID` 漏同步副本时会静默到 `xcodebuild` 才炸 | ✅ 已补（2026-10-02）：`UITestIDMirrorTests` + 单文件 `swiftc -typecheck` 通道，见 P0-2 |
| Flow 6「搜索真的把内容筛掉了」这一半在 `-uitest-empty-store` 下是**空洞**的（列表本来就空，搜不搜都空） | P3 搜索用例：先造一条数据再搜 |
| UI 用例写死时刻导致「几点跑决定红绿」：Flow 3c 写死「今天下午3点」，而 `AICommandValidator` 会（正确地）拦下过去的一次性日程 → 15:00 之后必红 | ✅ 已修（2026-10-02）：改用 `laterTodayText()`（现在 + 1 小时，距零点 <5 分钟则 `XCTSkip`） |
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
| D8 | ✅ **已决（2026-10-04）：只压「选中日填充」，不动品牌色** | P3-1 遗留 | 两个备选：①把控件层的 appTint 也压暗到达标（品牌色会变深）；②选中日改用黑字（`black on #4B6FF2` = 4.85:1 达标，但每天都变黑字，视觉变化更大）。现状由 `SelectedCellContrastTests.testAppTintSelectedFillRemainsAKnownGap` 钉住 |
| D7 | **存储只读时要不要在界面上告诉用户** | 未排期 | `EventStore.storageIsReadOnly`（磁盘格式比本 App 新 / 版本标记读不懂）目前只写日志：那段时间用户的增删改**不会落盘**。要提示就得加 4 语言文案（并过 `LocalizationParity` 类的 key 数校验），属于产品决策 |

---

## 八点五、真机 bug 结案：「AI 创建的日程不立刻出现在今日安排」（2026-09-30）

**用户报告**：AI 日历助手创建的日程不会立刻出现在「今日安排」里，必须再手动创建一条才一起显示。

### 结论：**不是刷新 bug**，而是「日程正确建到了别的日子 + 反馈没说清是哪天」

埋点实测拿到决定性时间线（诊断代码已移除）：

```
10:37:12.665  write:AI-created | rev=2 total=10 id=40D74C2F start=10-01 10:00
10:37:12.709  card.body        | rev=2 today=4 selDay=09-30 sameDay=true   ← 今天仍 4 条
   SelectedDayCardView: \EventStore.revision changed.                        ← SwiftUI 自证被 revision 触发
10:37:17.171  card.body        | rev=2 today=1 selDay=10-01 sameDay=false  ← 切到 10-01，事件在这里
   SelectedDayCardView: \EventStore.eventCache changed.
```

- 观察通知、`month.body`、`card.body` **全部正常触发**，新事件 id 也出现在它所属那天的数组里；
- `10-01 10:00` 来自输入「**明天**上午10点…」（解析器实测：「明天上午10点提醒我开会」→ `10-01 10:00`）；
- 用户人在**今天**的日历页，今天列表当然不变 → 看起来"没反应"，切日期/再操作一次才看见。

**排查中排除的三个假设**（都曾是我的主要怀疑）：`@Observable` 观察失效、`eventCache` 私有存储导致依赖登记失败、`selectedDate` 不是今天（`sameDay` 实测为 `true`）。

### 修复（已实施）

| 文件 | 改动 |
|---|---|
| `Views/AIAssistantView.swift` | `create()` 判断落点是否今天：非今天时提示改为「**已加入 <日期> 的日程**」，并给「**去看看**」按钮（复用 `NavigationCoordinator.openEventDate`）。`showSuccess` 统一清 `completedOffDay`，避免删除/修改的提示上挂到无关按钮 |
| `Support/AccessibilityID.swift` | 新增 `aiGoToCreatedDay = "ai.created.goto"` 并登记进 `all`（有命名规范测试把关） |
| 4 套 `Localizable.strings` | 新增 `已加入 %@ 的日程`、`去看看`（四语言 key 数一致：472；**当时点**的数字，P3-3 后为 476） |
| `LunisolarCalendarUITests` | 新增 **Flow 3d**：用「明天…」创建 → 断言提示含日期 + 有「去看看」→ 点它跳过去并看到该事件 |

**为什么不只是改文案**：笼统的「日程已加入日历。」在落点是别的日子时是**误导性成功**——用户据此以为操作生效了。所以必须同时给日期**和**去路。

> 🚨 **2026-10-02 更正：上表的「并给『去看看』按钮」当时是假的——按钮从未渲染过**
>
> UI 测试第一次真正跑起来（Flow 3d）就抓到了它：断言「提示含日期」通过，
> 断言「有『去看看』按钮」失败，6 次轮询全部为空。屏幕录制把现场留得很清楚：
>
> - `t=14.0s`：预览正确（标题 `AI跨日日程-1790937713`、时间 **2026年10月3日 10:00**）
> - `t=17.0s`：提示出现，文案**正确**：`✓ 已加入 2026年10月3日 的日程`——**但卡片里没有按钮**
> - `t=18.0s`：提示消失，界面回到空输入态
>
> **真因是顺序**（`AIAssistantView.create()`）：
>
> ```swift
> completedOffDay = startDate          // ① 先设
> showSuccess(String(format: …))       // ② showSuccess 第一件事就是 completedOffDay = nil ← 立刻被清
> ```
>
> 而 `showSuccess` 上方的注释还写着「需要『去看看』的只有 create，它在调用本方法**之后**才设置该字段」
> ——**注释与代码相反，代码是错的**。文案对是因为文案不走这个字段；按钮是死的。
> 也就是说：`279cb1a` 那次「真机 bug 结案」只修好了一半（说清了是哪天，但没给去路）。
>
> **改法（结构性，不是调顺序）**：把 off-day 变成 `showSuccess` 的**参数**
> （`showSuccess(_ text: String, offDay: Date? = nil)`），让 `completedOffDay` 只有这一个写入点。
> 顺序 bug 从此不可能再犯，注释也不再是一句会过期的承诺。
>
> **顺带调整（UX 取值，可一句话驳回）**：带按钮的提示停留 **6 秒**，纯文案仍是 2 秒。
> 理由是 2 秒不够「读日期 → 决定 → 点中」，而这正是本修复的补救路径；
> 常量在 `AIAssistantView.plainSuccessDwell / actionableSuccessDwell`。
>
> **教训**：这次不是测试写错，是**测试第一次跑就抓到了我自己上一轮漏掉的真实缺陷**。
> 之前「已实施」的结论只来自读代码，而读代码时我看的是那行注释。
>
> ✅ **2026-10-02 18:48 复验通过**：修复后在 iPhone 17 Pro / iOS 26.5 上
> **PASSED**（19.9 秒，三步断言全过：提示带日期 → 有「去看看」→ 点它跳到 10月3日
> 并看到该事件）。**这是本项目 UI 测试第一次真正跑完一整条用例**。
> 同时把断言里一处会假红的写法一并修了：`EventRow` 用
> `.accessibilityElement(children: .combine)` 把整行合成一个元素、label 是「标题 + 时间段」，
> 所以按标题做精确匹配（`app.staticTexts[title]`）永远找不到事件行——
> 已统一改用 `eventRow(_:title:)`（前缀匹配），Flow 2 / 3a / 3d 三处。

### 顺带发现的解析器问题（**已修两条静默错误**，2026-09-30）

扫描常见说法时发现，其中「静默建到错误日期」类比"拒绝"更危险：

| 输入 | 修复前 | 修复后 | 性质 |
|---|---|---|---|
| `明早10点开会` | `09-24 10:00`「**明**开会」 | `09-25 10:00`「开会」 | ✅ 已修（日期错 + 标题被啃字） |
| `下个月15号10点开会` | **`09-24 10:00`**（月=9、日=24，即"今天"！） | `10-15 10:00`「开会」 | ✅ 已修（日期词被当标题） |
| `这个月20号10点开会` | `09-24 10:00`「这个月20号开会」 | `09-20 10:00`「开会」 | ✅ 已修 |
| `国庆节上午10点` | `09-30 10:00` | 未改 | 节日名不参与日期推断（**待定**） |
| `明天上午10点提醒我` | FAIL「没识别到日程标题」 | 未改 | 拒绝型（加个"开会"就过）— **待定** |
| `10月1号上午10点提醒我` | FAIL | 未改 | 拒绝型 — **待定** |
| `明天上午10点提醒我明日方舟开服` | 标题「方舟开服」 | 未改 | **标题里的日期词被全局删掉**（2026-10-02 新发现，**待定**，见下） |

**改法**（`AICommandParser.swift`）：
1. `normalize` 补「明早/明晚/明儿早/明儿晚」→「明天早上/明天晚上」（口语高频，旧实现识别不出「明天」）；
2. 日期分支新增「`(下|本|这)个月 N号`」，**整段一次吃下**并按前导词做月份偏移，
   标题剔除随之干净。此前只命中**裸号**分支，对错取决于今天几号
   （「下个月1号」在 9/30 会碰巧顺延成 10-01，而「下个月15号」直接错成今天）。

**两条踩坑记录**（都靠探针/测试才定位）：
- 正则**不能**写成 `(下|本|这)\s*个?\s*月`——实测吃不下完整的「这个月」，
  必须用 `(?:[下本这]\s*个?\s*月|…)` 这种字符类写法；
- **不要用 `(?!\d)` 前瞻**：ICU 下会让「下个月1号**1**0点」整体不匹配
  （`号`后紧跟数字即失配）。裸号分支有独立正则，无需前瞻兜底。
- 新分支插在年-月-日分支之前，曾吞掉显式年份（`2027年10月1日` → 年份丢、标题残留），
  故新正则带可选年前缀并单独认年；已加回归守卫。

**测试有效性已证伪**：把新增的 5 条断言拿到**未修复的 HEAD** 上跑（`git worktree`），
**11 处失败**，失败信息与上表修复前一致（含 `"24" is not equal to ("15")` 这类"算成今天"）。

**2026-10-02 新发现：标题里的日期词会被啃掉（未修，待裁）**

探针（Flow 3d 用例真正会输入的那句话）意外暴露的第三个问题：第 3 步用的是
`title.replacingOccurrences(of: consumedDate, with: "")`，**全局**替换；而 `normalize`
会把「明日/今日」归一成「明天/今天」，于是标题自己带的日期词也被一起删光：

```text
明天上午10点提醒我明日方舟开服     → 标题「方舟开服」        ← 游戏名被啃
明天上午10点提醒我明日日程-<ts>    → 标题「日程-<ts>」       ← Flow 3d 原本就踩这个
明天上午10点提醒我明天开会         → 标题「开会」            ← 重复的日期词被删（这条像是想要的）
明天上午10点提醒我今日开会         → 标题「今天开会」        ← 归一成"今天"后没删（consumedDate 是"明天"）
明天上午10点提醒我今年总结         → 标题「今年总结」        ← "今年"不在词表
```

**为什么先不修**：把它改成「只删被日期识别真正消费掉的那一次」，会同时改变
「…提醒我明天开会 → 开会」这类现有行为——标题里重复的日期词该不该保留属于产品口径，
是 D 类裁决而不是纯 bug 修复。**当前只在 UI 测试侧绕开**：Flow 3d 的标题改用
「AI跨日日程-&lt;ts&gt;」（不含日期词），已用探针验证原样落库。

### 一处必须记住的教训

`xcscheme` 被 Xcode **反复静默改写**：除了写入诊断参数，还会**删掉
`parallelizable = "NO"` 及其注释**。本次排查中已被改写两次——一次是 Xcode 手动跑，
一次是命令行 `xcodebuild test`。

原因推测：scheme 里 `shouldAutocreateTestPlan = "YES"`，Xcode 27 在自动生成/落盘
test plan 时会重写 `TestableReference`，而 `parallelizable` 在新格式下不再被保留。

**两点结论**：
1. **提交前必须 `git diff` 检查 xcscheme**，否则会把 `parallelizable = "NO"` 的删除一并带上；
2. **不要把"UI 测试不并行"这条纪律只寄托在 scheme 上**——它会被 Xcode 悄悄抹掉。
   真正生效的约束是 `Tools/run_tests.sh` 的**串行**执行与 CI（`ci.yml` 不跑 UI 测试）。
   scheme 里的属性只是"顺手挡一下"，不是可靠防线。

---

## 八点六、P2 已开工：两项数据安全修复（2026-09-30）

### ✅ B4 部分损坏只丢坏记录，不再清空整库（`f44dc78`）

**为什么优先做它**：这是全项目**唯一会一次性毁掉用户全部日程**的路径。

旧实现 `JSONDecoder().decode([CalendarEvent].self, …)` 是**整文件一次性解码**；
而 `CalendarEvent` 的 rawValue 是**中文枚举字符串**（Priority/RepeatRule/EventType），
解码用 `try c.decode`（缺键即抛）。于是**一条**记录被写坏（未知 rawValue / 缺字段 /
半截写入）就会让整个数组解码失败，把用户全部日程清零，只留一个 `.corrupt` 备份。

**新行为分两档**（保留原契约）：
| 情况 | 行为 |
|---|---|
| 文件不是 JSON 数组、或**一条都解不出** | 仍整份隔离 `.corrupt.<ms>`（行为不变） |
| 有部分能解出 | 好记录照常加载；坏记录另存 **`.bad.<ms>`** 旁路文件（JSON Lines） |

**证伪**：新断言在未修复提交上跑 → `("0") is not equal to ("2") - 只应丢弃坏的那 1 条；实际：[]`
——3 条记录因 1 条坏而**全部归零**。

### ✅ B3 任何退出路径都不得停在 `.inProgress`（`e57b071`）

**现象**：设置页显示「同步中…」并**禁用**「立即同步」，无任何提示，只能重启 App。

**两条卡死路径**（都用 worktree 在未修复提交上证伪过）：
1. **`provider.push` 抛出**（断网/限流/CloudKit 网络错误）—— 真机主路径。
   错误被上层 `flushDirtyAndDeleted` 吞进日志，用户看不到。
2. **同步开关关闭**（`isEnabled == false`）—— 提前 return、不抛错，因此没有复位点。

> ⚠️ **更正一处本计划早先的判断**：原记录说「`guard available else` 已设 `.failed`，
> 所以抛错路径没漏」。实跑证明**是错的**：Mock 的 offline 模式下 `isAvailable` 仍为 true，
> 抛错发生在更靠后的 `provider.push(records:)`。两条路径都真实存在，且第 1 条更贴近真机。

**改法**：`status = .inProgress` 移到 `isEnabled` guard **之后**；用 `defer` 统一兜底；
`provider.push` 的抛出先记进 `currentError` 再 rethrow（**不吞异常**，上层仍需保留脏标记）；
兜底如实反映错误 `currentError as? SyncError ?? mapError(...)`——无脑包成 `.unknown` 会把
`.networkUnavailable` 这类已分类错误盖掉（修的过程中实测发现）。

**证伪**：新断言在未修复提交上 **4/4 失败**，两条都停在 `inProgress(.push)`，与真机现象一致。

### P2 剩余项

| 项 | 状态 |
|---|---|
| P2-1 导出/备份入口 | **待裁决 D6**（导出 UI 是被主动移除的产品决策，非代码缺陷） |
| P2-1 存储格式版本与迁移 | 未做（`JSONBackupWrapper.version` 存在但从未被读取） |
| P2-3 导入静默覆盖本地编辑 | 未做（导入把 `updatedAt` 盖成当前时间，`.keepLatest` 下必然覆盖） |
| P2-4 数据到期机制 | 未做（**节气 2032-12-22 / 放假 2027-01-01 / 黄历 2029-01-01** 三个悬崖，均静默降级） |

---

## 九、里程碑与验收

| 里程碑 | 内容 | 验收标准 |
|---|---|---|
| **M0 可验证** ✅ 2026-10-02 | P0 全部 | 五通道全绿 + CI 绿 + 可回滚；`HANDOFF_REVIEW` 中 §1 的四处修复已进提交历史 |
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
| 第 1 天 | ~~P0-1 Git 基线~~ ✅ 已完成（远端 `50ab407` 已含全部改动） |
| 第 2 天 | P0-2 剩余部分：跑 `Tools/run_tests.sh` 的两条 **UI 测试**通道（CI 已替他三条） |
| 第 3–4 天 | P1-1 CloudKit（**先补测试**，再改行为）|
| 第 5 天 | ~~P1-2 喜神/财神~~ ✅ 已完成 2026-09-30 |

> P1-3 单例泄漏、`.gitignore` 修复、**P1-2 喜神/财神**均**已于 2026-09-30 完成**（见对应小节）。

之后再按 P2 → P3 推进；P4 不排期。

---

## 数据到期防线（P2-4 的后续，2026-10-04 加固）

**背景**：三份内置数据都会到期，且到期是**静默降级**（用户看不到报错，只发现功能不对）：

| 数据集 | 覆盖到 | 到期后果 |
|---|---|---|
| 放假安排 | 2026-10-10（可信边界 = **2027-01-01**）| 全部返回 `.normal`：放假与调休消失 |
| 节气表 | 2032-12-21 | `nextTerm` 返回 nil，节气倒计时消失 |
| 黄历离散库 | 2028-12-31 | 落到算法兜底（同算法）→ 只告警 |

**本轮加固**：到期检查原本把时间写死成 `Date()`——那条断言在今天永远绿，
**"闹钟会不会响"从来没被验证过**。现在：
- 抽出 `expiryReport(now:)`（可注入时间）；
- 新增 **`testExpiryAlarmActuallyFires`** 自检三个时间点：悬崖后一天必须硬失败并点名数据集、
  悬崖前 10 天必须已进入报告、**今天必须干净**（不提前误响）；
- 断言预警窗口 `warnDays > 10`（放假安排通常 11 月底才公布）。

**关键日期**：**2026-12-02** 起 `swift test` 会开始报「放假安排」预警（`⚠️ 数据到期预警`），
届时按 `docs/DATA_UPDATE_RUNBOOK.md` 补 2027 年放假安排即可。这条红是**设计如此**——
它是强制更新数据的闹钟，不是 bug。

### D8 已决并实施（2026-10-04）

**问题**：选中日格子的填充是 `appTint`（#4B6FF2），白字只有 **4.33:1**——低于 AA 4.5，
而格子里的农历行是小字号，必须达标。（这是 P3-1 当时留给产品决策的遗留项。）

**决策**：**只给「选中日填充」一个压暗到刚好达标的 token（`SelectedCellFill`），
不动 `appTint` 本身**。理由：
- `#4B6FF2` 只需亮度降约 **5%** 就够（肉眼几乎无差），不必动整个品牌色；
- 备选「选中日改黑字」会让同一品牌蓝底上一处白字、一处黑字，反而不一致，故未采用；
- 按钮/强调色等处的品牌观感完全不变。

**实现**：`SelectedCellFill.brandHex = AccentContrast.darkenedForWhiteText(hex: "#4B6FF2")`；
`CalendarComponents` 的选中填充由 `Color.appTint` 改为 `SelectedCellFill.color`
（只在**无节日强调色**时生效——有节日时仍用节日原色，见 P3-1）。

**测试翻转**：原 `testAppTintSelectedFillRemainsAKnownGap`（钉住缺口）改为
`testSelectedFillMeetsAAWithWhiteText`（守住达标）：断言新填充白字 ≥4.5、原 `appTint` 确实 <4.5、
且两者不同。**谁把填充改回 `appTint`，它会红。**

**验证**：428 用例 × 4 时区 0 失败；macOS + iOS SDK 构建 0 警告。
UI 两通道未重跑：这是**纯色值改动**，而 UI 用例只断言结构/文案、不断言颜色，
重跑无法提供额外信息（视觉确认可用截图）。