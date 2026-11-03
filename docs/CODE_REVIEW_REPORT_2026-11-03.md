# 清和日历（LunisolarCalendar）全量代码与开发过程审查报告

- 审查对象：`/workspace` 快照（HEAD `chore: 导入当前工程快照`，2026-10-22，单提交浅克隆）
- 审查日期：2026-11-03
- 审查范围：`Sources/` 106 个 Swift 文件全量结构扫描 + 30 余个核心/高风险文件逐行精读；单元测试 63 个文件、UI 测试 1 个文件、Xcode 工程配置、`Package.swift`、`Tools/`、`.github/workflows/`、`docs/` 全部 24 份文档
- 结论概览：**未发现 P0 级缺陷**；共确认 **1 个 P1（发布验证工具链）**、**10 个 P2**、**15 个 P3**。工程整体成熟度高，综合评分 **8.0 / 10**。

> 说明：本报告基于静态审查 + 可执行的静态检查。由于当前环境没有 iOS/macOS SDK，未运行单测与 UI 测试，真实 CloudKit 也未联调；详见第 2 节。

---

## 0. 结论摘要

**做得好的地方（经代码验证）：**

1. 分层清晰：纯算法（LunarCore）→ 领域模型 → `EventStore` → Service/Coordinator → SwiftUI/Widget，依赖方向基本单向。
2. 测试密度高：472 个单元测试函数（9,347 行）对 20,671 行源码，另有 25 条 UI 流程；四时区矩阵、数据到期防线、跨日历系统（佛历/和历）防御都有专门用例。
3. 存储可靠性设计完整：版本标记、原子写、损坏文件兜底、逐条打捞、自动备份、合并去重、写盘防抖。
4. 同步冲突方案有明确不变量：`version` + 单调水位线（timestamp floor）+ 墓碑，避免"被拒记录越过水位线导致永久分叉"这一类经典问题；代码注释里保留了复现过程。
5. 本地化扎实：4 种语言各 470 条词条，代码中 334 个 `NSLocalizedString` key 在四种语言中命中率 100%；`InfoPlist.strings` 也有本地化。
6. 无障碍与设计约束可执行化：硬编码字号红线进 CI；动态字号有 UI 用例；设计 token 统一出处。

**需要优先处理的地方：**

1. **P1：`Tools/run_tests.sh` 的 iOS SDK 构建通道实际不可通过**。第 141–142 行断行写错，`--sdk` 那行会被 shell 当作独立命令执行（已本地复现退出码 127），而文档/发布清单把它当作"五通道全绿"的发布门。
2. **P2：同步失败会被 UI 报成"同步完成"**。`syncBidirectional()` 捕获所有错误后正常返回，`syncNow()` 因此永远返回 `nil`。
3. **P2：提醒存在 iOS 64 条待发上限，代码没有配额/优先级处理**。`.workday` 一件事件就占 5 条，事件一多会静默丢提醒。
4. **P2：隐私清单与"天气向 Open-Meteo 发送坐标"不一致**，且坐标精度 4 位小数（约 11 m）。发布前需核对隐私标签。
5. **P2：`Calendar.gregorian` 静态实例缓存了启动时的时区**，跨时区旅行后 App 内日期边界会与 Widget 不一致，直到重启。
6. **P2：真实 CloudKit Provider 的 `@unchecked Sendable` 与并发回调内可变字典存在数据竞争**（当前构建未启用 iCloud，属潜在风险）。

| 维度 | 评分 | 主要依据 |
|---|---:|---|
| 架构与分层 | 8.5 | 职责边界清晰，Core 可独立编译；少数工具/服务存在重复常量 |
| 数据与算法正确性 | 8.5 | 1900–2100 表驱动 + 黄金用例；边界/时区/历法防御充分 |
| 可靠性与异常路径 | 7.5 | 存储很强；同步状态上报、提醒配额、导入上限有缺口 |
| 安全与隐私 | 7.0 | 无密钥/无 HTTP/无追踪；隐私清单与定位外发需要修正 |
| 测试 | 8.5 | 数量与针对性都高；UI 用例集中在一个 1,729 行文件；无覆盖率门 |
| 文档 | 8.5 | 24 份、8,807 行，含复盘/审计/发布门；存在链接与数字漂移 |
| 工程化与 CI | 7.5 | CI 三通道设计合理；本地全量脚本有硬故障且未被 CI 覆盖 |
| **综合** | **8.0** | 个人项目里少见的高完成度，但"最后一公里"验证仍需收口 |

---

## 1. 项目画像

| 指标 | 数值 |
|---|---|
| 语言/工具链 | Swift 6.0（`swift-tools-version:6.0`），Xcode 工程 `SWIFT_VERSION = 6.0` |
| 最低系统 | iOS 17.0 |
| 版本 | `MARKETING_VERSION = 1.0.1`，`CURRENT_PROJECT_VERSION = 1` |
| 源码 | 106 个 Swift 文件 / 20,671 行 |
| 单元测试 | 63 个文件 / 472 个 `func test` / 9,347 行 |
| UI 测试 | 1 个文件 / 25 条流程 / 1,729 行 |
| 本地化 | zh-Hans / zh-Hant / en / ja，各 470 条词条 |
| 文档 | `docs/` 16 篇 + `docs/archive/` 8 篇，共 8,807 行 |
| 外部依赖 | 无 SPM 第三方依赖；网络仅 `api.open-meteo.com`（天气）与 Apple 反地理编码 |
| 数据资源 | `huangli_db.json`（2024-01-01 ~ 2028-12-31，1,827 天）、`lunar_calendar.json` |

**架构（按依赖方向）：**

```text
LunarCore (纯算法：LunarDate / Huangli)
        │
Models (CalendarEvent, CountdownEvent, CalendarDayKey/Summary ...)
        │
Stores (EventStore, CountdownStore, StorageFormat)
        │
Services (EventService, AIAssistantService, AICommandParser/Validator)
        │
Sync / Support (EventSyncCoordinator, RealCloudKitProvider, NotificationManager,
                WeatherService, DataPortability, HolidayProvider ...)
        │
Views / Widgets / App (SwiftUI、WidgetKit、ActivityKit、生命周期协调器)
```

**功能与交付状态：**

| 能力 | 代码状态 | 交付状态 |
|---|---|---|
| 公历/农历/节气/黄历 | 完整，资源 + 内置兜底 | 可用 |
| 事件 CRUD、重复规则、提醒 | 完整 | 可用 |
| 导入导出（ICS/CSV/JSON）、系统日历/通讯录导入 | 完整 | 可用 |
| 天气 | 完整（Open-Meteo + 定位 + 缓存） | 可用，需隐私口径复核 |
| Widget / 灵动岛 / 时间胶囊 | 完整 | 可用 |
| iCloud 同步 | 代码完整（真实 Provider + Mock Provider） | **当前 entitlements 已移除 iCloud capability，运行时降级为"不可用"** |
| 实时同步推送（CKQuerySubscription） | Provider 内有实现 | **未接线（无调用方、无后台模式、无远程通知注册）** |

---

## 2. 审查方法与限制

**已执行的检查：**

| 检查 | 命令/方法 | 结果 |
|---|---|---|
| Linux 编译 | `swift build`（Swift 6.2.4） | 在 123 步编译中失败：`no such module 'SwiftUI'`（预期平台限制） |
| SPM 解析 | `swift package describe` | 成功；target 结构符合描述 |
| 脚本语法 | `bash -n Tools/*.sh` | 全部通过 |
| 脚本语义 | 复现 `\ $SWIFT_EXTRA_ARGS` + 换行 + `--sdk` | 确认 `--sdk` 被当成独立命令，退出码 127 |
| 本地化键 | Python 解析 334 个 `NSLocalizedString` key 与 4 份 `.strings` | 4 语言缺失均为 0 |
| 危险 API | `grep` + Python 正则全量扫描 | `try!` 0、`as!` 0、强制解包 8 处（均有守卫或为常量）、`TODO/FIXME/HACK` 0、明文 `http://` 0 |
| 并发标注 | 全量统计 | `@unchecked Sendable` 9 处（其中 3 处回调路径需复核，见 P2-5） |
| 字号红线 | 按 CI 同款命令本地执行 | 通过 |
| 测试规模 | 统计 `func test` | 472 单元 / 25 UI |

**未能执行的检查（限制）：**

1. **单元测试与 UI 测试未运行**：本机为 Linux，无 SwiftUI/UIKit/CloudKit/WidgetKit SDK；README 所称的"Linux 仅验证模型层"也与实际不符（P3-7）。
2. **真实 CloudKit 未联调**：当前 entitlements 不含 iCloud，无法在真机/模拟器验证 schema、订阅与账号切换。
3. **开发历史不可核验**：仓库是单提交浅克隆（`.git/shallow`，HEAD 2026-10-22），文档中提到的 83/128 次提交、逐轮回归无法在 Git 历史中复核，只能以文档自述 + 代码现状为准。
4. **未做真机/动态字号/锁屏/灵动岛实机走查**。

---

## 3. 开发过程审查

### 3.1 过程证据（来自文档，按时间）

| 日期 | 文档 | 作用 |
|---|---|---|
| 2026-09-20 | `PROJECT_IMPROVEMENTS`、`UI_REDESIGN` | 早期结构与视觉重设计 |
| 2026-09-25 | `UI_POLISH_REVIEW`、`PROGRESS_ANALYSIS` | UI 打磨与进度评估 |
| 2026-09-27 | `IPAD_UI_DESIGN`、`UI_DESIGN_REVIEW` | iPad 分栏与设计审查 |
| 2026-09-30 | `EXECUTION_PLAN`、`HANDOFF_REVIEW`、`ALLDAY_TIMEZONE_PLAN` | P0→P4 执行计划、交接复盘、全天事件时区专项 |
| 2026-10-04 | `RETROSPECTIVE`、`POLISH_CHECKLIST`、`REFACTOR_ASSESSMENT` | 复盘、打磨清单、重构评估 |
| 2026-10-19 | `BUG_AUDIT` | 全仓缺陷审计（P0/P1/P2/P3 分级） |
| 2026-10-22 | `FOLDABLE_ADAPTATION_PLAN` | 折叠屏适配计划（规划态） |
| 长期 | `RELEASE_CHECKLIST`、`DATA_UPDATE_RUNBOOK`、`ENTITLEMENTS`、`APP_STORE`、`DEVICE_TEST_CHECKLIST`、`XCODE_BUILD_GUIDE`、`HUANGLI_DATA_SOURCE`、`AI_DEVELOPMENT_CONTEXT` | 发布、数据更新、签名、上架、真机、构建、数据源、AI 协作规范 |

### 3.2 过程成熟度亮点（可验证部分）

1. **"验证即门禁"**：CI 三通道（`swift build`、四时区 `swift test`、iOS SDK 构建）+ 硬编码字号红线；发布清单把数据到期做成自动化门（`DataExpiryTests`）。
2. **测试能反向约束实现**：`SyncDivergenceConvergenceTests` 明确写了"不假设一轮收敛"，并要求"不静默丢数据"；`HolidayProviderTests` 把 2027 断言写成自更新形式，避免补数据时误红。
3. **事故复盘具体**：复盘记录"只筛选 `error:` 导致漏掉 warnings"、"连续 5 次盲试"、"写了永远为真的守卫"等真实教训，并转成规则（警告即失败、四时区、UI target 类型检查）。
4. **数据到期有可行动日期**：放假安排可信到 2027-01-01，`DataExpiryTests` 从 2026-12-02 起硬失败，避免静默降级。
5. **重构有度量**：文档记录 `CalendarMonthView` 592→358、`AIAssistantView` 657→425 等，不靠口号。

### 3.3 过程风险

1. **陈述与提交物漂移**：`docs/README.md:57` 声称"五通道全绿"，但当前 `Tools/run_tests.sh:141-142` 存在硬故障；发布清单 `0.4` 依赖该脚本。CI 只跑前三通道，因此**不会发现这个回归**。
2. **数字漂移**：测试数在文档中分别是 436（`docs/README.md:55`）、463（`RELEASE_CHECKLIST.md:12`），实测 472；通道数在 `README.md:143` 写"四通道"，脚本实际是"五通道"。
3. **文档链接失效**：`README.md:10` 与 `README.md:233` 指向不存在的 `docs/docs/archive/...`（实际目录是 `docs/archive/...`）。
4. **静态审计覆盖不全**：`BUG_AUDIT` 把 9 个 `@unchecked Sendable` 归为"三类均成立"，但未覆盖 CloudKit 回调内并发写字典（P2-5），也未审视隐私清单与定位外发的一致性（P2-3）。
5. **功能宣称与交付能力不一致**：iCloud 同步在 README 功能表中仍在列；实际构建已移除 entitlement。文档有脚注，但产品文案仍会给用户"可同步"的预期。
6. **单提交快照**：无法验证"每轮回归/每次修复都有独立提交"的纪律，也无法用 `git bisect` 定位未来回归。

### 3.4 过程结论

开发过程整体属于"文档驱动 + 测试驱动 + 复盘驱动"的高标准个人工程：计划、审计、复盘、发布门齐全，且大量约束已经代码化。主要短板不是"没想到"，而是**最后一道验证没有自证**：本地全量脚本失修、CI 不覆盖它、文档数字不随代码更新。

---

## 4. 代码审查（按模块）

### 4.1 农历 / 节气 / 黄历核心

- 算法采用 1900–2100 表驱动 + 节气/干支/宜忌数据，资源 JSON 失败时有内置 fallback；`lunarDateSafe` 对越界返回 `nil`，不会产生"1900 年之前"的幽灵日期。
- `LunarDate.formatter` 统一固定 `en_US_POSIX` + Gregorian，规避佛历/和历/伊斯兰历改写年份，这是本项目最有价值的防御之一。
- 数据到期防线设计正确：放假安排按"下一个缺失年份的 1 月 1 日"计算可信边界，而不是把 11–12 月无节假日误判为降级。
- 遗留风险：`Calendar.gregorian` 静态实例缓存时区（P2-4）；数据悬崖 2027-01-01（P2-9）。

### 4.2 存储与数据模型

- `EventStore` 1,122 行，承担排序、索引、缓存、脏标记、墓碑、导入合并、防抖写盘、损坏打捞、示例数据，复杂度高但不变式清楚。
- 可靠性亮点：`.atomic` 写、主文件损坏时读 `.backup`、逐条打捞并隔离坏记录、`StorageFormat` 版本标记、`flushPendingSave()` 在后台落盘。
- 发现：
  - `merge()` 先 `saveNow()` 再插入 dirty 标记（P3-1），导入后强退可能丢同步标记。
  - `removePushedFlags()` 只改内存不落盘，而 `versionMap` 立即落盘（P3-2），成功推送后强退会在下次启动重复推高版本。
  - `shiftIndices()` 每次插入/删除遍历整个 `idToIndex`（P3-4），大批导入呈 O(K·N)。

### 4.3 同步（CloudKit）

- 设计正确：`version` 严格递增 + `timestampFloor` 防时钟回拨 + 只对"真正处理过"的记录推进水位线 + 30 天墓碑清理 + 单向失败保留脏标记。
- 冲突语义：同版本用 `updatedAtMs` 决胜；败方 push 被拒后 `versionMap` 不前进，下一轮 pull 会用严格大于采纳云端版本，因此能在一轮内收敛（代码注释与测试一致）。
- 发现：
  - `syncBidirectional()` 吞掉所有 provider 错误并返回结果，`syncNow()` 只检查抛错 → UI 永远成功（P2-1）。
  - `pullAndMerge()` 在 `provider.pull` 抛错时没有 `defer` 复位状态（push 有），独立调用会让状态卡在 `.inProgress(.pull)`（P2-7）。
  - `RealCloudKitProvider` 是 `@unchecked Sendable`，但 `perRecordResultBlock` / `perRecordSaveBlock` / `recordMatchedBlock` 内直接改本地字典/数组，Apple 不保证回调串行（P2-5）。
  - `setupSubscription` / `enableSubscription` 无调用方；Info.plist 无 `UIBackgroundModes: remote-notification`，也无远程通知注册 → "实时推送"是死代码（P2-6）。
  - 前台回到 `.active` 不触发同步，只有启动/手动/开启时同步；结合上一条，跨设备变更只能靠重启 App 看到（P2-6）。
  - 账号"暂时不可用"会把用户开关写成 `false` 且不重试（P2-10）。

### 4.4 AI 自然语言（本地规则引擎）

- 不是 LLM，完全本地规则 + 正则，符合"不上传数据"的承诺。
- 安全路径正确：删除/改期属破坏性指令，必须经过 `resolveTarget` → 界面确认才执行；`AIAssistantService.handle()` 虽提供一站式直执行入口，但当前 UI 未使用。
- 已知局限：英文 "3pm" 这类无"点"锚点的时间不会被解析（测试里已明确记录，属设计取舍，P3-13）。
- `cleanedKeyword` 用 `replacingOccurrences` 删除"的/了/把"等词，可能误伤包含这些字的标题，属低风险误匹配。

### 4.5 通知

- 权限、分类、重复规则、农历周年、稍后提醒（snooze）路径完整；`isNotified` 与重复事件的处理有明确注释。
- 主要缺口：iOS 64 条 pending 上限没有配额/去重/优先级策略，`.workday` 单事件 5 条（P2-2）。
- `content.userInfo` 写入 `eventID`，但没有 `UNUserNotificationCenterDelegate`，点击提醒不会定位到事件（P3-5）；前台提醒也不会主动展示。

### 4.6 天气与定位

- 流程简洁：只取一次定位 → 反地理编码 → Open-Meteo → UserDefaults 缓存；失败区分 `denied` / `failed`，无"坐标缺失就显示北京"的兜底。
- 隐私面：坐标以 4 位小数发送给第三方（P2-3）；App Group ID 在 `WeatherService:312` 硬编码，而 `EventStore` 是注入式，存在双源维护风险（P3-11）。
- 健壮性：`LocationService` 轮询授权最长 6 秒，避免无限等待；`WeatherService` 用 ephemeral session，不留磁盘缓存。

### 4.7 导入 / 导出

- ICS：全天事件按 RFC 5545 排他 `DTEND` 处理、`LAST-MODIFIED` 参与冲突、UID 稳定，跨日历兼容性考虑充分。
- CSV/JSON：日期格式显式固定 locale/calendar/timezone；导入有标题与时间区间校验、冲突策略与统计。
- 缺口：
  - CSV 未防公式注入（P3-3）。
  - 导入无文件大小/条数上限，同步主线程读入并解析（P3-4）；大文件可造成明显卡顿。
  - JSON 备份不校验 `version`，解析失败静默返回空数组（P3-12）。

### 4.8 UI / Widget / 灵动岛

- 设计系统统一（`AppTheme`），动态字号与无障碍标识覆盖到 UI 测试；空态、首次使用、键盘遮挡都有专门用例。
- Widget 快照经 App Group 共享，`WidgetCenter.reloadAllTimelines()` 在数据变更时触发；时间线按需刷新。
- 月历/年视图做了缓存与派生数据优化（`AllEventsDerived`、日摘要缓存），大库渲染风险已被主动处理。
- 遗留：`CalendarEvent.timeDisplay` 每次访问新建 `DateFormatter`（仅 2 处使用，影响有限）；`Calendar.gregorian` 时区问题同样影响 Widget 与 App 的一致性。

### 4.9 生命周期

- `AppLifecycleCoordinator` 把散落的 `.task` / `scenePhase` / CloudKit 装配 / 通知重排收口，修复了"冷启动排两遍提醒"这类问题。
- 发现：`.inactive` 与 `.background` 共用复位逻辑，控制中心/来电等瞬时失活会多排一次全量提醒（P3-9）；启动时 `cleanUpLegacyImportNotes()` 会对匹配事件 `update()`，产生一次额外同步写入（仅一次，可接受）。

### 4.10 安全与隐私

- 无硬编码密钥、无分析 SDK、无明文 HTTP；外部域名仅 Open-Meteo 与 Apple。
- 深链只接受 UUID/日期，不接受任意动作；通知 payload 未被执行。
- `PrivacyInfo.xcprivacy` 已声明 UserDefaults 与 FileTimestamp 的 required-reason API，但 `NSPrivacyCollectedDataTypes` 为空；与"坐标发送给 Open-Meteo"存在口径冲突（P2-3）。
- Widget/锁屏会展示事件标题，属于系统可见面；用户可在系统设置控制，未发现越权。
- 主要风险集中在**第三方定位外发**与**隐私标签一致性**，不是代码注入类风险。

### 4.11 构建与工具链

- `Package.swift` 用 `LunarCore`（仅 2 个算法文件）+ `LunisolarCalendarApp`（排除核心文件）避免重复编译；App 不生成 SPM 资源 bundle，规避 Xcode 16 codesign 问题，取舍有记录。
- CI 设计合理：macOS 26 对齐开发工具链、四时区单测、iOS SDK 构建、字号红线；UI 测试留本地。
- 主要问题：`run_tests.sh` 的 iOS 通道硬故障（P1-1）；脚本未被 CI 覆盖；README 宣称的 Linux 模型层验证不可执行（P3-7）。

---

## 5. 问题清单

> 分级标准：P0 = 数据丢失/安全漏洞/启动崩溃；P1 = 阻塞发布验证或核心功能不可用；P2 = 特定场景下功能错误或用户可感知；P3 = 可维护性/低概率边界/文档问题。

### P1（1 项）

| ID | 位置 | 问题 | 影响 | 建议 |
|---|---|---|---|---|
| P1-1 | [`Tools/run_tests.sh:141-142`](../Tools/run_tests.sh) | `swift build ... \ $SWIFT_EXTRA_ARGS` 后换行，`--sdk` 行成为独立命令；已复现 `--sdk: command not found`（exit 127） | 发布清单 0.4 的"五通道"实际不可能全绿；iOS SDK 通道失去可信度，且 CI 不跑该脚本，回归无人发现 | 改为标准续行：`swift build --triple arm64-apple-ios17.0-simulator --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" $SWIFT_EXTRA_ARGS`；并在 CI 增加 `bash -n` + 一条脚本冒烟（macOS 上跑 `SKIP_UI=1 Tools/run_tests.sh`） |

### P2（10 项）

| ID | 位置 | 问题 | 影响 | 建议 |
|---|---|---|---|---|
| P2-1 | [`AppLifecycleCoordinator.swift:238-254`](../Sources/LunisolarCalendarApp/App/AppLifecycleCoordinator.swift)、[`EventSyncCoordinator.swift:383-429`](../Sources/LunisolarCalendarApp/Sync/EventSyncCoordinator.swift)、[`SettingsSyncSections.swift:50-54`](../Sources/LunisolarCalendarApp/Views/SettingsSyncSections.swift) | `syncBidirectional()` 把 push/pull/purge 的错误全部收集后**正常返回**，`syncNow()` 只在抛错时返回 `Error`，因此按钮永远弹"同步完成" | 用户以为已备份/已拉取；失败时无重试入口，信任受损 | 让 `syncBidirectional` 在 `allErrors` 非空时返回 `SyncResult`，`syncNow` 检查 `result.errors` 并返回首个错误；`enableCloudSync` 同样按 `errors` 判定 `.syncFailed` |
| P2-2 | [`NotificationManager.swift:282-309, 386-399`](../Sources/LunisolarCalendarApp/Support/NotificationManager.swift) | `rescheduleAllReminders` 先全量 `cancelAll` 再逐事件排；`.workday` 单事件 5 条 repeating trigger，没有 64 条上限的配额/优先级策略 | 事件较多时 iOS 静默丢弃部分待发提醒，用户感知为"某些提醒不响" | 统计预计条数，超限时按最近触发时间保留（或合并 repeating）；对 `.workday` 用单条 daily 触发 + 当天工作日过滤；补充超过 64 条的回归用例 |
| P2-3 | [`PrivacyInfo.xcprivacy`](../Sources/LunisolarCalendarApp/PrivacyInfo.xcprivacy)、[`WeatherService.swift:233-251`](../Sources/LunisolarCalendarApp/Support/WeatherService.swift)、[`ENTITLEMENTS.md:174`](ENTITLEMENTS.md) | 坐标为 `%.4f`（约 11 m）发送给 Open-Meteo；隐私清单 `NSPrivacyCollectedDataTypes` 为空，文档称"不收集用户数据" | App Store 隐私标签与清单/实现可能不一致（ITMS 风险）；定位精度超出天气所需 | 明确口径：在清单与 App Store 隐私标签声明 Coarse Location（不关联用户、仅 App 功能）；坐标降到 2 位小数（约 1 km）；文档补充第三方服务与数据用途 |
| P2-4 | [`LunarDate.swift:14`](../Sources/LunisolarCalendarApp/Models/LunarDate.swift)、[`EventStore.swift:570-573`](../Sources/LunisolarCalendarApp/Stores/EventStore.swift) | `Calendar.gregorian` 为 `static let`，初始化时捕获当时 `TimeZone.current`；全仓 19 处使用，未监听 `NSSystemTimeZoneDidChange` | 跨时区旅行后 App 内 `startOfDay`/日期缓存仍按旧时区，与 Widget（独立进程）不一致，直到重启 | 改用 `Calendar.autoupdatingCurrent`（或监听系统时区变化时重建实例并清缓存）；为"运行中切换时区"补测试 |
| P2-5 | [`RealCloudKitProvider.swift:459-466, 484-497, 537-544, 580-588`](../Sources/LunisolarCalendarApp/Sync/RealCloudKitProvider.swift) | 类标注 `@unchecked Sendable`，但在 CloudKit 的 per-record / recordMatched 回调里直接写本地 `[CKRecord.ID: Result]`、`[CKRecord]`、`[SyncRecord]`；Apple 不保证这些回调串行执行 | 高并发/大批量时可能发生数据竞争（崩溃或结果丢失），且 Swift 6 编译器无法检查 | 用串行 `DispatchQueue` 或 `NSLock` 保护收集器；更彻底的做法是把收集逻辑抽成 actor；补并发压力测试（Mock 回调可并发触发） |
| P2-6 | [`RealCloudKitProvider.swift:325-355`](../Sources/LunisolarCalendarApp/Sync/RealCloudKitProvider.swift)、[`AppLifecycleCoordinator.swift:84-99`](../Sources/LunisolarCalendarApp/App/AppLifecycleCoordinator.swift)、`Info.plist` | `setupSubscription` / `enableSubscription` 无调用方；无 `UIBackgroundModes: remote-notification`、无 `registerForRemoteNotifications`；回到前台也不同步 | 即便在付费账号构建中启用 iCloud，跨设备变更也只能靠重启 App 或手动同步；"zone 级变更推送"注释与现实不符 | 要么完整接线（APNs 注册 + `didReceiveRemoteNotification` + 前台 `syncBidirectional`），要么删除订阅代码并把同步触发改为每次 `.active` 增量拉取；文档同步更新 |
| P2-7 | [`EventSyncCoordinator.swift:255-268`](../Sources/LunisolarCalendarApp/Sync/EventSyncCoordinator.swift) | `pullAndMerge` 设置 `.inProgress(.pull)` 后，`provider.pull` 抛错路径没有 `defer` 复位（push 有 B3 的 defer） | 独立调用时状态永久卡在"拉取中"，按钮禁用；当前仅被 `syncBidirectional` 包住，属潜伏缺陷 | 增加 `defer { if case .inProgress = status { status = .failed(...) } }`，并用单测覆盖 pull 抛错 |
| P2-8 | [`README.md`](../README.md) 功能表、[`LunisolarCalendar.entitlements:5-19`](../LunisolarHostApp/LunisolarCalendar.entitlements) | 功能表仍列"iCloud 同步 · 真实 CloudKit"，而交付配置已移除 iCloud capability；仅靠脚注解释 | 用户/审核预期不一致；开关与文案在免费构建中不可用 | 在功能表标注"需付费账号构建"；免费构建隐藏同步开关或显示"当前构建不支持"；发布文档明确两条构建产物差异 |
| P2-9 | [`HolidayProvider.swift:19, 80-96`](../Sources/LunisolarCalendarApp/Support/HolidayProvider.swift)、[`DataExpiryTests.swift:16-19, 66-70`](../Tests/LunisolarCalendarTests/DataExpiryTests.swift) | 法定节假日/调休数据止于 2026-10-10，可信边界 2027-01-01；`DataExpiryTests` 从 **2026-12-02** 起硬失败 | 2026-12-02 后 CI 变红；若此时发版且未补数据，2027 元旦的放假/调休会整体显示为普通日 | 按 `DATA_UPDATE_RUNBOOK` 在国务院公布后补 2027；发版前确认 0.6 门为绿；考虑把到期日期做成版本化常量，避免手改多处 |
| P2-10 | [`AppLifecycleCoordinator.swift:136-143`](../Sources/LunisolarCalendarApp/App/AppLifecycleCoordinator.swift) | `provider.isAvailable == false`（含 `temporarilyUnavailable`）时直接把 `Lunisolar.sync.enabled` 写为 `false` | 网络/账号临时异常会永久关掉用户的同步偏好，之后不再自动恢复 | 区分 `noAccount` / `restricted` / `temporarilyUnavailable`：只有真正不可恢复时关闭；临时不可用保留开关并延后重试 |

### P3（15 项）

| ID | 位置 | 问题 | 建议 |
|---|---|---|---|
| P3-1 | [`EventStore.swift:686-694`](../Sources/LunisolarCalendarApp/Stores/EventStore.swift) | `merge()` 先 `saveNow()` 再 `dirtyEventIDs.insert`，导入后立即强退会丢失持久化脏标记，事件只留在本地 | 把 dirty 标记插入移到 `saveNow()` 之前（或 `merge` 末尾显式 `saveDirtyFlags()`） |
| P3-2 | [`EventStore.swift:559-565`](../Sources/LunisolarCalendarApp/Stores/EventStore.swift) | `removePushedFlags` 只改内存；`versionMap` 另行持久化。成功推送后强退会在下次启动重复推送并抬高版本 | `removePushedFlags` 内落盘（`saveDirtyFlags()`），或同步完成后显式 `flushPendingSave()` |
| P3-3 | [`DataPortability.swift:510-515`](../Sources/LunisolarCalendarApp/Support/DataPortability.swift) | CSV 只处理逗号/引号/换行，不防 `=`/`+`/`-`/`@` 开头的公式注入 | 对以危险字符开头的单元格前置 `'` 或统一加引号；补导出安全用例 |
| P3-4 | [`EventStore.swift:71-79`](../Sources/LunisolarCalendarApp/Stores/EventStore.swift)、[`SettingsDataSections.swift:186-187`](../Sources/LunisolarCalendarApp/Views/SettingsDataSections.swift) | 无文件大小/事件条数上限；`shiftIndices` 每次插入 O(N)，大导入 O(K·N)，且在 MainActor 同步解析 | 导入前限制大小（如 10 MB）与条数（如 5,000）；批量合并改为一次性重建索引；解析移到后台 |
| P3-5 | [`NotificationManager.swift:323`](../Sources/LunisolarCalendarApp/Support/NotificationManager.swift) | 通知 `userInfo` 带 `eventID`，但工程无 `UNUserNotificationCenterDelegate` | 接入 delegate，点击提醒经 `DeepLinkRouter` 定位事件；补 UI 测试 |
| P3-6 | [`README.md:10`](../README.md)、[`README.md:143`](../README.md)、[`README.md:233`](../README.md)、[`docs/README.md:55-57`](README.md)、[`RELEASE_CHECKLIST.md:12`](RELEASE_CHECKLIST.md) | 两处 `docs/docs/` 链接失效；"四通道"与"五通道"混用；测试数 436/463 与实测 472 不一致 | 统一为脚本实际五通道；用脚本自动生成测试数；修复链接 |
| P3-7 | [`README.md:138`](../README.md)、[`AppLifecycleCoordinator.swift:2`](../Sources/LunisolarCalendarApp/App/AppLifecycleCoordinator.swift) | 文档称"Linux 仅验证模型层"，但 App target 无条件 `import SwiftUI`；实测 Linux `swift build` 在 SwiftUI 处失败 | 要么拆出真正无 UI 的测试 target，要么把文案改为"仅 macOS 宿主可跑" |
| P3-8 | [`QingheLiveActivity.swift:298`](../Sources/LunisolarCalendarApp/Widgets/QingheLiveActivity.swift) | `.start` 分支使用 `target!`；依赖生命周期决策永不在 target 为 nil 时返回 `.start` | 改成 `guard let target else { return .failure(...) }`，避免契约演进时崩溃 |
| P3-9 | [`AppLifecycleCoordinator.swift:95-99`](../Sources/LunisolarCalendarApp/App/AppLifecycleCoordinator.swift) | `.inactive` 也复位"本前台已重排"，瞬时失活会多一次全量 `cancelAll + 重排` | 仅在 `.background` 复位；`.inactive` 只 flush |
| P3-10 | [`EventStore.swift`](../Sources/LunisolarCalendarApp/Stores/EventStore.swift)（示例数据插入） | 首次启动自动写入示例事件，用户会先看到非本人数据 | 确认产品有意为之；若保留，提供一次性清除/引导标识 |
| P3-11 | [`WeatherService.swift:312`](../Sources/LunisolarCalendarApp/Support/WeatherService.swift) | App Group ID 在此硬编码，`EventStore` 则注入式；改 group 时易漏 | 统一从 `AppEnvironment`/`WidgetSnapshotStore` 注入 |
| P3-12 | [`DataPortability.swift:83-89`](../Sources/LunisolarCalendarApp/Support/DataPortability.swift) | 不校验 `JSONBackupWrapper.version`；两种格式都失败时返回 `[]`，无法区分"空备份"与"格式错误" | 校验 version 并返回 `Result`/错误原因，UI 明确提示 |
| P3-13 | [`AICommandParser.swift`](../Sources/LunisolarCalendarApp/Services/AICommandParser.swift) + 测试 | 英文 `3pm` 等无"点/时"锚点的时间不参与解析，会落回默认 9:00 | 补 `(?<=\d)(am|pm)` 归一为"3 点下午"；若保持现状，在用户文档中写清支持范围 |
| P3-14 | [`LunisolarCalendarUITests.swift`](../LunisolarCalendarUITests/LunisolarCalendarUITests.swift) | 25 条流程集中在 1,729 行单文件，定位失败时阅读成本高 | 按域拆分为多个 `XCTestCase` 文件；保持 `private enum ID` 镜像测试 |
| P3-15 | [`Package.swift`](../Package.swift)（`LunarCore` target） | `LunarCore` 只 `exclude` 了 `PrivacyInfo.xcprivacy`，未排除 `Resources/`；实测 `swift build --target LunarCore` 输出 2 条 `Found unhandled resource` 警告（`huangli_db.json`、`lunar_calendar.json`） | 在 `LunarCore` 的 `exclude` 中加入 `"Resources"`；与"0 警告"口径对齐 |

---

## 6. 值得肯定的设计（建议保留）

1. **存储损坏的多级兜底**：主文件 → `.backup` → 逐条打捞 → 坏记录隔离，避免"一条坏 JSON 毁掉全部日程"。
2. **同步水位线的"只进已处理记录"不变量**：显式拒绝 `remote.max()`，并把反例写进测试，属于少见的细致。
3. **日期口径显式化**：`en_US_POSIX` + 固定 calendar/timezone 的 formatter 统一入口，避免佛历/和历系统下的整年偏移。
4. **ICal 全天事件排他 DTEND + LAST-MODIFIED 冲突**：跨 Google/Apple/Outlook 的兼容性处理到位。
5. **数据到期的"可行动告警"**：30 天硬失败、120 天软告警，且测试自更新，避免静默降级。
6. **本地化/无障碍工程化**：四种语言词条对齐、`InfoPlist.strings`、字号红线 CI、动态字号 UI 用例。
7. **破坏性 AI 指令必须确认**：查询/创建可直执行，删除/改期必须 `destructiveTarget` 二次确认，路径清晰。

---

## 7. 改进建议（按优先级，不设工期）

**第一优先（发布前必须）**

1. 修复 `run_tests.sh` 的 iOS 通道断行，并让 CI 至少跑一次 `SKIP_UI=1` 的脚本冒烟。
2. 修正 `syncNow()` 的错误判定，确保失败时 UI 显示失败而不是"同步完成"。
3. 在发布前核对隐私清单/App Store 隐私标签与天气坐标外发；坐标降精度并补文档。
4. 补 2027 节假日数据（`DataExpiryTests` 2026-12-02 起会硬失败）。

**第二优先（一个发布周期内）**

5. 给提醒加 64 条配额策略，并为"多事件 + workday"补回归测试。
6. 处理 `Calendar.gregorian` 的运行时区变化（`autoupdatingCurrent` 或监听重建）。
7. CloudKit：要么接线订阅/前台同步，要么删除死代码；无论哪种，都修正 README 功能表与免费构建提示。
8. `pullAndMerge` 补 `defer` 状态复位；`merge` / `removePushedFlags` 的脏标记落盘顺序修正。

**第三优先（持续质量）**

9. CloudKit 回调收集器改为串行保护；为 Mock Provider 增加并发触发用例。
10. 导入增加大小/条数上限并把解析移出主线程；CSV 增加公式注入防护。
11. 统一文档数字与链接；把测试数/通道数改为脚本生成，杜绝漂移。
12. 拆分 1,729 行 UI 测试文件；补通知点击深链与前台展示。

---

## 8. 复核附录

**本次实际执行的命令（可复现）：**

```bash
# 1) 平台编译（预期失败，验证 README 的 Linux 声明）
swift build

# 2) SPM 结构与核心 target（LunarCore 可独立编译，但输出 2 条 unhandled resource 警告）
swift package describe
swift build --target LunarCore

# 3) 脚本语法 + 断行语义
for f in Tools/*.sh; do bash -n "$f"; done
X=""; f(){ echo "called with $# args"; }; f a \ $X
--sdk foo   # 复现：--sdk 被当作独立命令，exit 127

# 4) 本地化 key 对齐（Python 脚本，输出：334 key，四语言缺失均 0）
# 5) 危险 API/静态红线（输出：try! 0、as! 0、http:// 0、TODO 0、强制解包 8）
# 6) 字号红线（与 CI 同款 grep）
```

**精读文件（按风险排序）：**

`EventStore.swift`、`EventSyncCoordinator.swift`、`RealCloudKitProvider.swift`、`SyncConflictResolver.swift`、`AppLifecycleCoordinator.swift`、`NotificationManager.swift`、`WeatherService.swift`、`DataPortability.swift`、`AICommandParser.swift`、`AICommandValidator.swift`、`AIAssistantService.swift`、`AIAssistantModel.swift`、`CalendarEvent.swift`、`LunarDate.swift`、`HolidayProvider.swift`、`HuangliDBProvider.swift`、`QingheLiveActivity.swift`、`LunisolarWidgetProvider.swift`、`QingheActivityCoordinator.swift`、`SettingsSyncSections.swift`、`SettingsDataSections.swift`、`Package.swift`、`run_tests.sh`、`ci.yml`、`RELEASE_CHECKLIST.md`、`BUG_AUDIT_2026-10-19.md`、`RETROSPECTIVE_2026-10-04.md`、`SyncDivergenceConvergenceTests.swift`、`DataExpiryTests.swift`。

**结构性扫描覆盖：**

106 个源文件的清单、规模、命名与关键符号扫描（全部文件）；其中 30 余个核心/高风险文件逐行精读（见上表）。另覆盖 `#if canImport` 条件编译、force unwrap / `try!` / `as!` / `@unchecked Sendable` / 网络端点 / 本地化调用 / 测试分布；63 个测试文件的用例数与断言类型；Xcode 工程的部署目标、Swift 版本、entitlements、Info.plist 权限文案。

---

## 9. 结论

这是一个**工程质量显著高于常见个人项目**的 iOS 日历应用：核心算法、存储韧性、同步不变量、日期口径、数据到期与本地化都有系统化设计，测试密度与文档深度也罕见。

但它目前卡在"最后一公里"：

- **验证链路没有自证**：本地全量脚本存在硬故障，CI 不覆盖它，文档却宣称全绿；
- **失败反馈不诚实**：同步错误被吞掉后 UI 报成功；
- **少数平台限制未兜底**：64 条通知上限、运行时区变化、定位外发隐私口径；
- **文档与提交物轻微漂移**：链接、数字、通道数、iCloud 可用性。

建议先完成"第一优先"4 项（脚本、同步错误、隐私口径、2027 数据），再进行发布；其余 P2/P3 可在一个发布周期内逐步收口。修复后，该项目具备进入正式发布与长期维护的质量基线。

---

*报告生成：2026-11-03 · 基于仓库快照静态审查 · 未运行 iOS 单测/UI 测试与真实 CloudKit 联调*
