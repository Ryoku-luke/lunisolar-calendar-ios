# 清和日历（LunisolarCalendar）第二轮深度审查报告

- 审查对象：`/workspace` 快照（HEAD `chore: 导入当前工程快照`，2026-10-22，单提交浅克隆）
- 审查日期：2026-11-03
- 审查性质：**增量审查**。第一轮报告 [CODE_REVIEW_REPORT_2026-11-03.md](CODE_REVIEW_REPORT_2026-11-03.md) 已确认的 P1/P2/P3 **不重复计入**；本报告只列新增问题，并对第一轮结论做复核。
- 第二轮新增精读：`Views/` 全部页面与组件、`Widgets/` 组件与时间线、`Models/` 重复规则与存储、`Services/` 活动协调、系统日历/联系人导入、`DataPortability` ICS 全链路、Xcode scheme、测试用例质量、资源 JSON 结构校验。
- 结论概览：**未发现新增 P0/P1**；新增 **8 个 P2**、**18 个 P3**。第一轮 1 个 P1 与 10 个 P2 **全部仍存在，未见修复痕迹**。综合评分由第一轮 8.0 下调至 **7.8 / 10**。

> 说明：本环境无 iOS/macOS SDK，未运行 XCTest/UI 测试，未联调真实 CloudKit；结论基于逐行静态阅读、`swift package describe`、`swift build --target LunarCore`、Python 资源校验与脚本语义复现。

---

## 0. 结论摘要

**第二轮最值得优先处理的新问题：**

1. **系统日历重复事件导入会被"压扁成一次"**。EventKit 展开出的每个 occurrence 共用同一个 `eventIdentifier`，导入层又只用该标识生成确定性 UUID，合并时同 id 反复覆盖，最终只保留最后一次 occurrence。
2. **系统日历全天事件导入会多显示一天**。EventKit 的全天 `endDate` 是排他语义（次日 00:00），导入映射未像 ICS 路径那样减 1 秒。
3. **重复规则的边界语义不一致**。`.yearly` 的 2/29 在平年消失、`.monthly` 的 31 号在小月消失、`.workday` 只认周一至周五而不认法定节假日；而倒数日模块对 2/29 已有回退处理，说明这是遗漏而非设计。
4. **未来才开始的重复提醒会提前响**。`UNCalendarNotificationTrigger` 只带 hour/minute/weekday，不带 `startDate`，从调度当刻就开始按规则触发。
5. **记事编辑会产生 `endDate == startDate` 的非法事件**，导出再导入会被 `merge()` 直接判为 invalid 丢弃。

**第一轮结论复核：** P1-1（`run_tests.sh` 续行断行）与 P2-1 至 P2-10 均仍存在；本轮抽查的 P3-1、P3-2、P3-5、P3-6、P3-10、P3-15 也未修复。

| 维度 | 第一轮 | 第二轮 | 变化依据 |
|---|---:|---:|---|
| 架构与分层 | 8.5 | 8.5 | 分层仍清晰；导入/模型层边界出现重复实现 |
| 数据与算法正确性 | 8.5 | 7.8 | 重复规则边界、系统导入映射、记事往返存在确定性缺陷 |
| 可靠性与异常路径 | 7.5 | 7.2 | 新增快照缓存、倒数日恢复、调度竞态等缺口 |
| 安全与隐私 | 7.0 | 7.0 | 未见新增风险；第一轮隐私口径问题仍待处理 |
| 测试 | 8.5 | 8.2 | 用例数量高，但缺少本次发现的边界；且有"测试镜像生产逻辑" |
| 文档 | 8.5 | 8.3 | 新增 Widget 注释与实现矛盾；第一轮漂移仍在 |
| 工程化与 CI | 7.5 | 7.5 | 本轮未见工具链改动；第一轮 P1 仍存在 |
| **综合** | **8.0** | **7.8** | 新增 8 个 P2 集中在数据正确性与用户可感知边界 |

---

## 1. 审查范围与方法

**第二轮新增覆盖：**

| 区域 | 文件/对象 | 检查方式 |
|---|---|---|
| 日历视图 | `CalendarMonthView`、`YearOverviewView`、`DayDetailView`、`SelectedDayCardView`、`CalendarComponents`、`EventRow` | 逐行阅读，重点看重复事件、深链、嵌套交互 |
| 编辑链路 | `EventEditView`、`AIAssistantModel` | 逐行阅读，核对新建/编辑两条保存路径 |
| 模型与存储 | `CalendarEvent`、`CountdownEvent`/`CountdownStore`、`EventStore` | 逐行阅读，构造边界用例推演 |
| 系统导入 | `CalendarImportProvider`、`SystemImportBridge`、`ContactsImportProvider` | 逐行阅读，对照 EventKit 语义 |
| 导入导出 | `DataPortability` 的 ICS 解析/导出、CSV、JSON | 逐行阅读，按 RFC 5545 核对 |
| 通知 | `NotificationManager` 的构建/重排/保留路径 | 逐行阅读，核对 `UNCalendarNotificationTrigger` 语义 |
| Widget/灵动岛 | `LunisolarWidgetProvider`、`LunisolarWidgetViews`、`WidgetSnapshotStore`、`CountdownActivity*`、`TimeCapsuleCoordinator` | 逐行阅读，核对快照窗口与活动仲裁 |
| 生命周期/深链 | `AppLifecycleCoordinator`、`DeepLinkRouter`、`NavigationCoordinator` | 逐行阅读，核对启动顺序 |
| 工程/测试 | `.xcscheme`、`CalendarEventTests`、资源 JSON | 解析/统计/Python 校验 |

**复核命令：**

```bash
swift package describe
swift build --target LunarCore          # 复现 2 条 unhandled resource 警告
bash -n Tools/run_tests.sh              # 语法通过，但第 141-142 行语义仍错
python3 - <<'PY'                        # 资源结构校验（详见附录）
PY
```

---

## 2. 第一轮结论复核

### 2.1 P1 / P2 复核表

| 第一轮 ID | 结论 | 本轮复核 | 证据 |
|---|---|---|---|
| P1-1 | `run_tests.sh` 续行断行，iOS 通道实际 exit 127 | **仍存在** | [run_tests.sh:141-142](../Tools/run_tests.sh)：`\ $SWIFT_EXTRA_ARGS` 后换行，`--sdk` 仍是独立命令 |
| P2-1 | 同步错误被收集后正常返回，`syncNow()` 永远报成功 | **仍存在** | [EventSyncCoordinator.swift:350-428](../Sources/LunisolarCalendarApp/Sync/EventSyncCoordinator.swift)、[AppLifecycleCoordinator.swift:238-250](../Sources/LunisolarCalendarApp/App/AppLifecycleCoordinator.swift) |
| P2-2 | 通知无 64 条配额，`.workday` 单事件 5 条 | **仍存在** | [NotificationManager.swift:282-302, 386-399](../Sources/LunisolarCalendarApp/Support/NotificationManager.swift) |
| P2-3 | 坐标 4 位小数外发，隐私清单未声明位置 | **仍存在** | `WeatherService`、`PrivacyInfo.xcprivacy` 未见改动 |
| P2-4 | `Calendar.gregorian` 缓存启动时区 | **仍存在** | `Calendar.gregorian` 仍为 `static let` |
| P2-5 | `RealCloudKitProvider` 的 `@unchecked Sendable` 与回调内写字典 | **仍存在** | 文件未改动 |
| P2-6 | CloudKit 订阅死代码、无后台模式、前台不同步 | **仍存在** | `Info.plist` 无 `remote-notification`；订阅方法仍无调用方 |
| P2-7 | `pullAndMerge` 抛错无 `defer` 复位 | **仍存在** | 状态复位仍只在成功路径 |
| P2-8 | README 宣称 iCloud 同步，交付已移除 capability | **仍存在** | 功能表与 entitlements 仍不一致 |
| P2-9 | 节假日数据止于 2026，2027 缺口 | **仍存在** | `HolidayProvider` 与 `DataExpiryTests` 未更新 |
| P2-10 | 临时不可用永久关闭同步偏好 | **仍存在** | `AppLifecycleCoordinator.swift:139-142` 仍直接写 `false` |

### 2.2 P3 抽查

| 第一轮 ID | 复核结果 | 证据 |
|---|---|---|
| P3-1 | **仍存在**：`merge()` 仍先 `saveNow()` 再插 dirty 标记 | [EventStore.swift:688-693](../Sources/LunisolarCalendarApp/Stores/EventStore.swift) |
| P3-2 | **仍存在**：`removePushedFlags` 仍不落盘 | 与第一轮一致 |
| P3-5 | **仍存在**：工程仍无 `UNUserNotificationCenterDelegate` | 全仓 grep 无 delegate 实现 |
| P3-6 | **仍存在**：README 仍混用"四通道/五通道"，测试数仍漂移 | 与第一轮一致 |
| P3-10 | **仍存在**：首次启动仍写入 4 条示例数据 | [EventStore.swift:754-758, 1045+](../Sources/LunisolarCalendarApp/Stores/EventStore.swift) |
| P3-15 | **仍存在**：`LunarCore` 仍输出 2 条 unhandled resource 警告 | `swift build --target LunarCore` 复现 |

**复核结论：** 该快照没有任何针对第一轮问题的修改痕迹。第一轮报告中的"发布前必须"4 项仍然全部成立。

---

## 3. 新增 P2（8 项）

> 分级标准同第一轮：P0 = 数据丢失/安全漏洞/启动崩溃；P1 = 阻塞发布验证或核心功能不可用；P2 = 特定场景下功能错误或用户可感知；P3 = 可维护性/低概率边界/文档问题。

### D-01 系统日历重复事件导入坍缩为最后一次 occurrence

- **位置**：[CalendarImportProvider.swift:59-100](../Sources/LunisolarCalendarApp/Support/CalendarImportProvider.swift)、[SystemImportBridge.swift:100-121](../Sources/LunisolarCalendarApp/Support/SystemImportBridge.swift)
- **现象**：`EKEventStore.events(matching:)` 会展开重复事件，每个 occurrence 的 `eventIdentifier` 都指向同一个主事件。导入映射把 `sourceID` 写成 `"ek:\(ek.eventIdentifier ?? ek.calendarItemIdentifier)"`，而 `deterministicUUID` 只由 `sourceID` 生成。因此同一条重复日程的所有 occurrence 得到**同一个 UUID**；`EventStore.merge` 进入"同 id 更新"分支，后一个 occurrence 覆盖前一个，最终库里只剩最后一次 occurrence。
- **影响**：用户从系统日历导入"每周例会"后，App 里只有某一次实例；重复规则、提醒、跨周展示全部丢失。导入条数统计还会显示"新增 N 条"，与最终可见条数不一致。
- **建议**：展开实例的 `sourceID` 必须包含 occurrence 起始时间（如 `ek:<identifier>:<ISO8601 start>`）；或只导入主事件并保留 RRULE（需要 `SystemImportEvent` 承载 recurrence 细节）。补一条"系统日历重复事件导入"的单测。
- **置信度**：高（EventKit 语义 + 代码路径可直接推演）。

### D-02 系统日历全天事件导入多显示一天

- **位置**：[CalendarImportProvider.swift:86-99](../Sources/LunisolarCalendarApp/Support/CalendarImportProvider.swift)、[SystemImportBridge.swift:100-113](../Sources/LunisolarCalendarApp/Support/SystemImportBridge.swift)
- **现象**：EventKit 全天事件的 `endDate` 是排他语义（次日 00:00）。导入时 `SystemImportEvent.endDate` 原样接收 `ek.endDate`，`toCalendarEvent` 也没有归一化。对比之下，ICS 导入路径明确做了 `endDate = exclusiveEnd - 1 秒`（[DataPortability.swift:331-341](../Sources/LunisolarCalendarApp/Support/DataPortability.swift)）。
- **影响**：单日全天事件导入后变成"跨两天"；`occurs(on:)` 的 `.never` 分支会在次日也返回 true，月历多一个圆点、Widget 多一天待办。
- **建议**：在 `SystemImportMapper.toCalendarEvent` 中对 `isAllDay` 且 `endDate` 为次日 00:00 的 DTO 统一减 1 秒，或直接在 `CalendarImportProvider.map` 内归一化；补系统全天事件导入用例。
- **置信度**：高。

### D-03 重复规则边界语义不一致（2/29、每月 31、工作日）

- **位置**：[CalendarEvent.swift:255-317](../Sources/LunisolarCalendarApp/Models/CalendarEvent.swift)、[CountdownEvent.swift:61-89](../Sources/LunisolarCalendarApp/Models/CountdownEvent.swift)
- **现象**：
  - `.yearly` 仅比较 `month/day`。起始日为 2/29 的事件，在平年 2/28 不命中、3/1 也不命中，整年消失。
  - `.monthly` 仅比较 `day == startDay`。起始日为 31 号的事件，在 30 天月份（以及 2 月）消失。
  - `.workday` 仅判断 `weekday 2...6`，不查询 `HolidayProvider`。法定节假日会照常提醒，调休上班日反而不提醒。
  - 对照：`CountdownEvent.nextAnniversary` 对 2/29 已显式回退到 2/28（[CountdownEvent.swift:61-89](../Sources/LunisolarCalendarApp/Models/CountdownEvent.swift)），说明同一产品内已有正确口径，`CalendarEvent` 属于遗漏。
- **影响**：生日/纪念日提醒缺年、月末任务缺月、工作日提醒在春节/国庆等假期误响。属于用户可直接感知的日期错误。
- **建议**：`.yearly` 对 2/29 在平年回退 2/28；`.monthly` 在目标月天数不足时回退到该月最后一天；`.workday` 接入 `HolidayProvider`（工作日 = 非周末且非法定节假日，或调休上班日）。补 2024-02-29、2025-02、每月 31 号、国庆/调休四组用例。
- **置信度**：高。

### D-04 未来才开始的重复提醒提前触发

- **位置**：[NotificationManager.swift:343-399](../Sources/LunisolarCalendarApp/Support/NotificationManager.swift)
- **现象**：`.daily/.weekly/.monthly/.yearly` 与 `.workday` 都使用 `UNCalendarNotificationTrigger(dateMatching:repeats:)`，匹配分量只含 hour/minute（及 weekday/day/month），**不包含起始日期**。系统会从调度当刻起按规则触发。一个 `startDate = 2027-01-01` 的每周提醒，会在本周就开始响。
- **影响**：用户提前数周/数月收到尚未开始的日程提醒；与日历里"该事件还没到"的展示矛盾，容易被当成 Bug。
- **建议**：对 `startDate` 在未来的重复事件，先只挂一条"首次发生时刻"的一次性通知，待首次发生后再由 `rescheduleAllReminders` 安装 repeating 版本；或在调度时跳过"下一次匹配时刻早于 startDate"的规则。补"未来开始的每周/每月提醒"用例。
- **置信度**：高（`UNCalendarNotificationTrigger` 不提供 startDate 约束）。

### D-05 记事编辑产生 `endDate == startDate` 的非法事件

- **位置**：[EventEditView.swift:293-305](../Sources/LunisolarCalendarApp/Views/EventEditView.swift)、[EventStore.swift:647-653](../Sources/LunisolarCalendarApp/Stores/EventStore.swift)
- **现象**：编辑分支中 `if type == .note { end = startDate }`，随后 `copy.endDate = end` 直接写回已有事件，**绕过** `CalendarEvent` 构造器"`end <= start` 自动 +3600"的兜底。新建分支走构造器所以合法，编辑分支会产生 `endDate == startDate` 的记事。
- **影响**：
  - `merge()` 的校验是 `ev.endDate <= ev.startDate` → invalid，导入该记事（ICS/JSON 备份经解析后）会被直接丢弃。
  - ICS 导出时 DTSTART/DTEND 相同，再导入仍会得到相等端点 → 往返丢数据。
  - `EventStore` 内部其他依赖 `end > start` 的逻辑（排序插入、跨天判断）处于未定义行为。
- **建议**：记事保存时把 `end` 设为 `max(start + 1 秒, end)`，或让 `merge` 对 `.note` 放宽为 `endDate >= startDate`；补"编辑记事 → 导出 → 导入"往返用例。
- **置信度**：高。

### D-06 "删除所有数据"的行为与文案不符

- **位置**：[SettingsView.swift:196-211](../Sources/LunisolarCalendarApp/Views/SettingsView.swift)、[EventService.swift:147-149](../Sources/LunisolarCalendarApp/Services/EventService.swift)、[EventStore.swift:700-721](../Sources/LunisolarCalendarApp/Stores/EventStore.swift)
- **现象**：危险区文案写"将永久删除所有日程、提醒和设置"，按钮也写"删除所有数据"；实际 `clearAllEvents()` → `EventStore.clearAll()` 只清 `events`（并取消通知、打墓碑）。`CountdownStore.events`、全部 `@AppStorage` 设置（外观、周起始日、通知偏好、同步开关等）都保留。
- **影响**：用户以为完成了"恢复出厂"，换机/转卖前仍残留倒数日与偏好；与 App Store 隐私承诺和用户预期不一致。
- **建议**：二选一——把文案改成"删除所有日程"；或真正清空倒数日并重置设置 key（需二次确认，且明确列出会重置的类别）。
- **置信度**：高。

### D-07 AI 归一化裸替换 `am/pm`，破坏英文标题并导致时刻回退

- **位置**：[AICommandParser.swift:522-540](../Sources/LunisolarCalendarApp/Services/AICommandParser.swift)、[AICommandParser.swift:467-487](../Sources/LunisolarCalendarApp/Services/AICommandParser.swift)
- **现象**：`normalize` 使用 `.replacingOccurrences(of: "am", with: "上午")` 与 `"pm"` → `"下午"`，无大小写/词边界约束：
  - `"team meeting"` → `"te上午 meeting"`；`"example"` → `"ex上午ple"`。
  - `"3pm 开会"` → `"3下午 开会"`，而 `parseClock` 依赖"点/时/冒号"等锚点，`3下午` 无法识别时刻 → 回落默认 09:00，标题仍残留 `3下午`。
  - 大写的 `AM/PM` 反而不会被替换，行为不一致。
- **影响**：英文/混合输入标题被静默改写，提醒时间错误；用户很难从预览中看出原因。
- **建议**：改为带词边界的正则（如 `(?i)(?<=\d)\s?(am|pm)\b`），只替换紧邻数字的时段词，并在解析后从标题剔除该时间 token；补 `"3pm meeting"`、`"team meeting"` 用例。
- **置信度**：高（代码逐字符可复现）。

### D-08 ICS 的 RECURRENCE-ID / EXDATE / RRULE 细节丢失

- **位置**：[DataPortability.swift:346-347, 381-387, 520-538, 581-608](../Sources/LunisolarCalendarApp/Support/DataPortability.swift)
- **现象**：
  - 解析器不识别 `RECURRENCE-ID` 与 `EXDATE`；重复系列中的"单次改期/单次取消"会被当成普通 VEVENT。
  - `pseudoUUIDForImport` 在有 UID 时只用 `uid` 作为种子，主事件与例外事件的 UUID 相同 → 后者覆盖前者（与 `merge` 的同 id 更新叠加）。
  - `parseRRULE` 只取 `FREQ`，忽略 `INTERVAL`、`COUNT`、`UNTIL`、`BYDAY`（仅"恰好 MO-FR"识别为工作日）。
- **影响**：导入 Google/Apple/Outlook 的重复日历时，"每两周"会变成"每周"、"共 10 次"变成无限重复、改期的单次实例丢失。属于可感知的日历数据错误。
- **建议**：至少解析 `RECURRENCE-ID`/`EXDATE` 并让身份种子包含 `RECURRENCE-ID`；`RRULE` 保留原始字符串或扩展 `RepeatRule` 支持 interval/count/until；不支持时在导入结果中明确提示"已简化规则"。
- **置信度**：高。

---

## 4. 新增 P3（18 项）

| ID | 位置 | 问题 | 建议 |
|---|---|---|---|
| D-09 | [SettingsView.swift:186](../Sources/LunisolarCalendarApp/Views/SettingsView.swift)、[SettingsAppearanceSections.swift:24](../Sources/LunisolarCalendarApp/Views/SettingsAppearanceSections.swift)、[SettingsSyncSections.swift:131](../Sources/LunisolarCalendarApp/Views/SettingsSyncSections.swift)、[SettingsDataSections.swift:123](../Sources/LunisolarCalendarApp/Views/SettingsDataSections.swift) | 4 处 `QingheSectionHeader(subtitle:)` 传裸中文字符串，未走 `NSLocalizedString`；`Text(String)` 按字面量渲染，英/日/繁中下仍显示简体中文 | 把 subtitle 改为 `LocalizedStringKey` 或包 `NSLocalizedString`；补四语言截图/文案检查 |
| D-10 | [LunisolarWidgetViews.swift:516, 603](../Sources/LunisolarCalendarApp/Widgets/LunisolarWidgetViews.swift) | 次要节日用 `Text("\(f2.emoji) \(f2.name)")`，而主节日用 `localizedName`；`name` 是中文原值 → 非中文系统小组件显示中文节日名 | 统一改用 `f2.localizedName`，与主节日保持一致 |
| D-11 | [YearOverviewView.swift:295-307](../Sources/LunisolarCalendarApp/Views/YearOverviewView.swift) | 年视图 `eventDays` 只按 `startDate` 的年份与起始日统计；重复事件不会在其他月份/日期出圆点，跨年事件也不会出现在下一年 | 用 `occurs(on:)` 逐日或逐月求值（可复用月历的缓存策略），至少有事件年份时按规则展开 |
| D-12 | [CalendarMonthView.swift:238-247](../Sources/LunisolarCalendarApp/Views/CalendarMonthView.swift) | 深链/通知打开重复事件时 `selectedDate = ev.startDate`，会跳到原始锚点月份（可能是多年前），而不是当前/下一次 occurrence | 计算"不早于今天的下一次 occurrence"再定位；保留对一次性事件的现有行为 |
| D-13 | [DeepLinkRouter.swift:80-87](../Sources/LunisolarCalendarApp/App/DeepLinkRouter.swift) | `parseISODate` 的 `DateFormatter` 未固定 `locale = en_US_POSIX` 与 `timeZone`；非公历系统或非默认时区下可能解析失败/日期偏移 | 固定 POSIX + 明确时区（与全仓 formatter 口径一致）；补佛历/和历模拟用例 |
| D-14 | [CountdownActivityController.swift:59-67](../Sources/LunisolarCalendarApp/Services/CountdownActivityController.swift)、[CountdownActivity.swift:214-220](../Sources/LunisolarCalendarApp/Widgets/CountdownActivity.swift) | 取消倒数日灵动岛后立即 `TimeCapsuleCoordinator.shared.refresh()`，但 `end(id:)` 内部是 `Task { await activity.end(...) }` 异步结束；refresh 时旧活动仍在 `Activity.activities` 中，仲裁判定"被占用"→ 时间胶囊不接管 | `end` 改为 async 并在结束后再 refresh；或 refresh 前等待活动列表移除 |
| D-15 | [AppLifecycleCoordinator.swift:53-81](../Sources/LunisolarCalendarApp/App/AppLifecycleCoordinator.swift) | `onLaunch` 顺序是"重排通知 → 快照 → CloudKit 装配"；启动自动同步拉回的远端事件不会触发重排，要等下一次 `.active`（且启动时 `.active` 可能已被 `didRescheduleThisForeground` 去重） | 在 `setupCloudSyncIfNeeded` 完成且有拉取结果后，显式 `rescheduleAllReminders` 一次；或用 revision 变化驱动 |
| D-16 | [SettingsDataSections.swift:81-84](../Sources/LunisolarCalendarApp/Views/SettingsDataSections.swift) | `.fileExporter` 完成回调写成 `{ _ in }`，导出失败（磁盘满、目标不可写）被完全吞掉，用户无任何提示 | 回调区分 success/failure，失败弹 toast；与导入路径的错误反馈对齐 |
| D-17 | [EventStore.swift:894-909, 993-1010](../Sources/LunisolarCalendarApp/Stores/EventStore.swift) | `saveNow()` 在 MainActor 上同步 `JSONEncoder` 编码全部事件，并立即 `writeWidgetSnapshotIfNeeded()`；后者对 8 天逐日 `events.filter { occurs(...) }` + 农历转换，复杂度约 O(8N)，事件多时每次防抖保存都卡主线程 | 快照改为增量/后台计算并节流（如数据变更 300ms 后异步生成）；大库下只重算受影响的天 |
| D-18 | [WidgetSnapshotStore.swift:138-142, 15-32](../Sources/LunisolarCalendarApp/Support/WidgetSnapshotStore.swift) | 快照写入 App Group `Library/Caches`（系统可清理），且 `WidgetSharedSnapshot` 无 schema/version 字段；解码失败统一返回 nil，旧格式与"无数据"无法区分 | 移到 `Application Support` 或至少接受 Caches 被清理并降级为"未知"；加 `schemaVersion` 并在读取时校验 |
| D-19 | [CountdownEvent.swift:174-187](../Sources/LunisolarCalendarApp/Models/CountdownEvent.swift) | `CountdownStore.load()` 损坏时只把坏文件复制为 `.corrupt.<ms>` 然后 `events = []`；没有 EventStore 那样的 `.backup` 恢复，也没有格式版本标记 | 与 EventStore 对齐：写前保留 `.backup`，损坏时先读 backup；增加 `StorageFormat` 版本 |
| D-20 | [CalendarEventTests.swift:500-506](../Tests/LunisolarCalendarTests/CalendarEventTests.swift) | 测试内复制了一份 `notificationIsEligibleForScheduling`，注释承认"NM 守卫变更时这里也要同步"；生产逻辑一改，测试仍可能全绿。另缺少 2/29、每月 31、记事往返、系统全天导入用例 | 把判定抽成生产层的纯函数并直接测试；补齐本报告 D-01/D-02/D-03/D-05 的回归用例 |
| D-21 | [`LunisolarCalendar.xcscheme:35-44`](../LunisolarCalendar.xcodeproj/xcshareddata/xcschemes/LunisolarCalendar.xcscheme) | TestAction 的 `TestableReference` 只含 `LunisolarCalendarUITests.xctest`；472 个单元测试不在 Cmd-U 范围，开发者日常"测试通过"可能只跑了 UI 用例 | 把单元测试 target 加入 scheme；CI 与本地使用同一 scheme |
| D-22 | [NotificationManager.swift:282-302](../Sources/LunisolarCalendarApp/Support/NotificationManager.swift) 与 [122-183](../Sources/LunisolarCalendarApp/Support/NotificationManager.swift) | `rescheduleAllReminders` 先 `cancelAll()` 再逐事件 `await add`；单事件保存路径也会 `removePending` + `add`。两条路径并发时（保存后立刻回前台），可能互相取消刚加上的请求 | 调度串行化（actor/队列）或加代际标记；重排期间跳过单事件调度 |
| D-23 | [DataPortability.swift:110-194](../Sources/LunisolarCalendarApp/Support/DataPortability.swift) | ICS 导出用 `joined(separator: "\r\n")`，未按 RFC 5545 做 75 字节折行；长 `SUMMARY`/`DESCRIPTION`（尤其中文 UTF-8）会产出超长行，部分严格解析器会拒收 | 导出时按 octet 折行（续行前置单个空格）；导入侧同时支持折行还原 |
| D-24 | [AICommandValidator.swift:98-136](../Sources/LunisolarCalendarApp/Services/AICommandValidator.swift)、[AICommandParser.swift:467-487](../Sources/LunisolarCalendarApp/Services/AICommandParser.swift) | 解析出的 hour/minute 未做范围校验；`25:99` 之类会被 `Calendar` 自动进位成次日 02:39，校验只查年份与"是否过去"，用户拿到一个静默错位的日期 | 解析后校验 `0...23` / `0...59`（或 1...12 + 时段词），越界返回 `.badTime`；补用例 |
| D-25 | [DayDetailView.swift:292-295](../Sources/LunisolarCalendarApp/Views/DayDetailView.swift)、[SelectedDayCardView.swift:161-164](../Sources/LunisolarCalendarApp/Views/SelectedDayCardView.swift)、[EventRow.swift:7](../Sources/LunisolarCalendarApp/Views/EventRow.swift) | `EventRow` 内含完成按钮，却被直接放进 `NavigationLink` 的 label；`EventRow` 注释已说明"嵌套按钮会导致点击失效"（多选模式才隐藏），但日详情/选中日卡片未做同样处理 | 把行内完成按钮移出 `NavigationLink` label（用 `HStack { link; button }`），或改用 `Button` + 自定义导航 |
| D-26 | [LunisolarWidgetProvider.swift:68-73, 126-134](../Sources/LunisolarCalendarApp/Widgets/LunisolarWidgetProvider.swift) | 注释仍写"未来 7 天不读快照，全部 0"，但实现已改成 8 天逐日读取真实数据；文档注释与代码相反 | 更新注释；把"快照窗口/未知态"的契约写在类型注释里，避免下次又被误改 |

---

## 5. 修复优先级建议

**发布前（延续第一轮 + 本轮新增的关键项）**

1. **P1-1**：修复 `Tools/run_tests.sh:141-142` 续行；CI 增加一次 `SKIP_UI=1` 脚本冒烟。
2. **D-01 / D-02**：修正系统日历重复事件与全天事件的导入映射，补两条导入回归测试。
3. **D-05**：修正记事编辑的 `endDate`，补"编辑 → 导出 → 导入"往返用例。
4. **D-03 / D-04**：修正重复规则边界与"未来开始"的提醒触发；这两项直接影响提醒可信度。
5. **P2-1 / P2-3 / P2-9**：同步失败反馈、隐私口径、2027 节假日数据仍按第一轮计划收口。

**一个发布周期内**

6. **D-06**：统一"删除所有数据"的文案与行为。
7. **D-07**：修正 `am/pm` 归一化，补英文输入用例。
8. **D-08**：至少处理 `RECURRENCE-ID`/`EXDATE`，并对 `RRULE` 简化给出提示。
9. **D-14 / D-15 / D-22**：活动仲裁、启动同步后的提醒重排、调度串行化。
10. **D-09 / D-10**：补齐 4 处 subtitle 与小组件次要节日的本地化。

**持续质量**

11. **D-17 / D-18**：快照计算移出主线程、增加 schema 版本。
12. **D-19 / D-20 / D-21**：倒数日备份对齐、去掉测试镜像、把单元测试加入 scheme。
13. **D-11 / D-12 / D-13 / D-16 / D-23 / D-24 / D-25 / D-26**：视图一致性、深链、导出反馈、ICS 折行、AI 校验、嵌套按钮、注释漂移。

---

## 6. 附录

### 6.1 本轮实际执行命令

```bash
# 结构
swift package describe

# 核心 target（仍输出 2 条 unhandled resource 警告）
swift build --target LunarCore

# 脚本语法（通过；语义问题另见 P1-1）
bash -n Tools/run_tests.sh

# 资源结构校验（Python）
# - huangli_db.json：2024-01-01..2028-12-31，1827 天连续，字段 y/j/c/g/s/w 非空
# - lunar_calendar.json：1900..2100，闰月值合法
# - NSLocalizedString：334 key，四语言缺失 0

# 关键路径 grep/Read
# - occurs(on:)、merge、buildNotificationRequests、ICS 解析/导出
# - SystemImportMapper、deterministicUUID、EventEditView.save
# - xcscheme TestAction、WidgetSnapshotStore 路径
```

### 6.2 精读文件（本轮新增）

`CalendarImportProvider.swift`、`SystemImportBridge.swift`、`ContactsImportProvider.swift`、`DataPortability.swift`、`CalendarEvent.swift`、`CountdownEvent.swift`、`EventStore.swift`、`NotificationManager.swift`、`AICommandParser.swift`、`AICommandValidator.swift`、`AIAssistantModel.swift`、`EventEditView.swift`、`CalendarMonthView.swift`、`YearOverviewView.swift`、`DayDetailView.swift`、`SelectedDayCardView.swift`、`CalendarComponents.swift`、`EventRow.swift`、`SettingsView.swift`、`SettingsAppearanceSections.swift`、`SettingsSyncSections.swift`、`SettingsDataSections.swift`、`LunisolarWidgetViews.swift`、`LunisolarWidgetProvider.swift`、`WidgetSnapshotStore.swift`、`CountdownActivity.swift`、`CountdownActivityController.swift`、`TimeCapsuleCoordinator.swift`、`AppLifecycleCoordinator.swift`、`DeepLinkRouter.swift`、`CalendarEventTests.swift`、`AIAssistantTests.swift`、`LunisolarCalendar.xcscheme`。

### 6.3 限制与待人工验证

1. 无 iOS SDK：所有结论均为静态推演；**未运行**单测/UI 测试/Widget 预览。
2. 未联调真实 CloudKit 与 EventKit；D-01/D-02 依据 Apple 公开语义与代码路径，但建议在真机导入一份重复日历/全天事件复核。
3. `DayCellView` 的 `Equatable` 未比较 `@AppStorage` 的 `showLunar/showSolarTerm/showHoliday`。由于 `@AppStorage` 自身可能触发视图失效，是否真的"设置切换后网格不刷新"需真机/UI 测试确认，故**未列为确定缺陷**，仅记录为待验证点。
4. 开发历史仍不可核验（单提交浅克隆），只能以代码现状复核第一轮结论。

---

## 7. 结论

第二轮审查把覆盖面从"核心算法与同步/存储"扩展到**视图、Widget、系统导入、重复规则与往返数据**。项目基础仍然扎实：分层、存储韧性、日期口径、本地化工程化都保持第一轮水平。

新增问题集中在"边界语义"而非架构：

- **导入层**把系统日历的重复与全天语义丢了（D-01/D-02/D-08）；
- **重复规则**在 2/29、月末、工作日、未来起始时刻四类边界上不一致（D-03/D-04）；
- **数据往返**因记事 `endDate == startDate` 而断裂（D-05）；
- **交互/本地化**还有一批可感知的小缺口（D-06、D-09、D-10、D-25）。

建议按第 5 节顺序处理：先修脚本与导入/重复规则（影响数据正确性与提醒可信度），再处理文案、本地化与性能。完成这些后，项目可从当前 **7.8 / 10** 回到第一轮的 8.0 以上，并具备稳定发布基线。

---

*报告生成：2026-11-03 · 第二轮增量审查 · 基于仓库快照静态分析 · 未运行 iOS 单测/UI 测试与真实 CloudKit/EventKit 联调*
