---
name: "qinghe-calendar-audit-and-fix"
description: "清和日历专项深挖：选模块做代码审计→挖漏洞(P1/P2/P3分级)→修复→补回归测试→构建+测试+推送。用户说『继续下一轮/修复和构建测试/深挖/专项X修复』或要审查任意模块时调用。"
---

# 清和日历专项深挖与修复

本 Skill 固化了 10+ 轮实战验证出的「专项审计 → 漏洞挖掘 → 修复 → 回归测试 → 构建/测试/GitHub 推送」一体化流程，适用于 **清和日历（LunisolarCalendarApp + LunarCore）** 这个纯 SwiftPM SPM 结构、双 Target 拆分、iOS+macOS 跨平台的 iOS 日历 App。

---

## 一、何时触发（启动 Skill 的信号）

只要用户出现以下任一意图，立即启用本 Skill：

- 「继续下一轮」
- 「继续执行修复和构建测试」
- 「继续执行专项 X 和专项 Y 的修复」
- 「梳理代码、检查 Bug、xcode 编译测试」
- 明确要对某个模块做专项审查（"检查 SettingsView 具体模块问题"、"挖 Notification 调度漏洞"等）

---

## 二、一轮标准工作流程（固定 4 步）

每次开始时用 `TodoWrite` 建一张任务板，状态 → 完成时用 `summary` 字段写本轮最终报告摘要。每轮**至少并行启动一次 baseline 构建+测试**作为参考基线。

### Step 1：搭台（TodoWrite + 并行 baseline）
- TodoWrite 选本 Skill 的「三、专项审计入口清单」中 2-4 个模块作为本轮目标。
- 立即后台并行：`swift build` + `swift test` 做 baseline 参考（用一个 RunCommand 串起来）。
- 主线程不要等 baseline 结束——立刻开始目标模块的 Grep/Read 代码审计。

### Step 2：审计+挖洞
- 用 `Grep -n output_mode=content` 抓关键词模式（见"四.高频漏洞模式库"）。
- 对热点文件用 Read 分 50-80 行区间阅读，重点盯：`init/deinit`、`save/load`、`guard/return`、`Task/Dispatch`、`Calendar.current`、`for-in` + 数组下标、`?? 0 / ?? "" / ?? []` 三类数字/串/空数组 fallback。
- 挖到漏洞后先判定严重度（按下面 P1/P2/P3 分）。
- **每次最多挖 2-4 个实锤就修**，不要攒成大 PR。

### Step 3：修复+回归测试
- 修复后立即本地 `swift build` + `swift test`（独立 RunCommand blocking），过了再推。
- 如果修复的是"逻辑判断型漏洞"（guard 条件、yearly offset、调度 eligibility），**必须在 `Tests/` 对应 Target 里补一条回归 test**。Linux 上跑不了的框架（UserNotifications/CloudKit/WidgetKit/UIKit）用"纯函数镜像等价测试"代替，把核心判断条件抽成 helper 在 CalendarEvent/LunarDate/Huangli 等纯模型侧写成测试断言。
- 新增测试计入下一轮 `Executed N tests` 的增量对比里。

### Step 4：提交+推送+报告
- `git add -A && git commit -m "前缀(模块): 标题

  - Px: 详细。文件路径+行号链路。原因 -> 修复 -> 影响。构建 X.XXs，N/N 全通过"
  前缀规范：`fix` / `feat` / `refactor` / `docs`。
- `git push`（当前 feature 分支：codex/ui-liquid-settings-edit）
- TodoWrite.summary 写本轮结果，格式："第 N 轮·X 专项·报告·修复 M 项 (A P1 / B P2 / C P3)· 新增回归 test K 条·构建 Xs + N/N 通过 + 提交 hash"。
- 最后对用户用中文出结构化报告：基线结果表、修复详情（每个含严重度/根因/修复/文件链接）、累计修复统计表、下一轮建议方向列表。

---

## 三、专项审计入口清单（13 个，每轮挑 2-4 个）

按"还没审过 → 出 Bug 概率高 → 优先级高"排序。**禁止连续两轮重复审同一模块除非用户点名**。

| # | 模块 | 关键路径 | 目标高频问题 |
|---|------|---------|------------|
| 1 | **NotificationManager** | scheduleForAllEvents / buildRequests / lunar / workday / nextSolarForLunar | eligibility guard 一刀切、offset 只应用 hour/min 不应用 date、workday 忽略 HolidayProvider、重复 never.isNotified 未重置 |
| 2 | **EventStore** | enqueuePush / flushDirtyAndDeleted / consumeDirtyEvents / clearDirtyFlags / saveDebounce / dirtyEventIDs+deletedEventIDs 交集 | 部分失败 dirty 全清/永不清、防抖 debounce 后台杀进程丢数据、Calendar.current |
| 3 | **EventSyncCoordinator** | syncBidirectional / mergeFromCloud / pullAndMerge / push / LWW versionMap | version 膨胀、conflict 静默吞、updatedAt=Date() 伪造、deletedIDs 永远不清空、per-record failedIDs 未追踪 |
| 4 | **Mock/RealCloudKitProvider** | push / fetchVersions / recordsSince / delete tombstone / saveBatch | LWW 冲突不返回 per-record error、CKError map 遗漏、tombstone TTL 永活 |
| 5 | **DataPortability / ICS** | parseICS / exportICS / parseRRULE / escape / unescape / BYDAY 工作日 vs 周末 | 折叠行、STATUS/PRIORITY 丢、转义顺序、BYDAY 子集判断错判 |
| 6 | **LunarDate** / **Huangli.swift** | lunarDateSafe / lunarDate / yearIndex / leapMonth / nextAnniversary / 200-element array 索引 | minYear…maxYear 越界 nil 保护、2/29 闰月周年非闰年 fallback、ganZhi 字段缺失 |
| 7 | **Widget 视图**（WidgetViews/Provider） | lunar nil → 0 数字 fallback / festival color / progress division 0 除 | 0月0 数字脏显示、snapshot 过期同今天判断、topTitles 空 fallback 行 |
| 8 | **CountdownEvent / CountdownStore / CountdownView** | save()/saveDebounce / flushPendingSave / DatePicker in range / anniversary resolve | 0.5s debounce 后台丢数据、Range 无限越界、周年 2/29 fallback |
| 9 | **DateJumpView** | Picker 范围 / jumpToDate / 快捷跳转 addingMonths/addingYears | 1900/2100 外 dismiss 应用假农历镜像、DateComponents(year:month:day) 构造失败静默 |
| 10 | **SettingsView** | notificationCard / notDetermined / notifStatusText disabled 条件 / Toast.id 自动隐藏过期 / performSystemImport 权限申请 | 权限死角 UX、Toast 新旧 id 不一致、import 冲突策略 default 选择、Toast 错误静默 |
| 11 | **HuangliDBProvider** | resolve(date:) / Cache.isInRange / root.days[key] / algorithm fallback generate | 离散库 JSON 未加载 + 算法 fallback 双重闭合查、农历越界 HuangliDay 返回 nil |
| 12 | **FestivalManager / HolidayProvider / SolarTermProvider** | festivals(on:) / holidayType / nextTerm / daysRemaining calculation | 2026 国庆重叠 merge、sortedEntries 缓存、HolidayProvider 范围外 nil 安全处理 |
| 13 | **AlternateIconManager / AppTheme / WidgetSnapshotStore** | Spring Festival window 判定 / Color festiveRed / resolveURL AppGroup→Documents→tmp | 两个农历源不一致、Touch target 44pt min / snapshot 6h 过期边界 |

额外两条"非模块专项"：**Accessibility**（所有交互元素加 accessibilityLabel）、**iPad 适配**（hSizeClass regular 模式限宽 isWide）。

---

## 四、高频漏洞模式库（实战 40+ 修复沉淀）

看到对应代码模式，**80% 概率是 Bug**，优先审计：

### P1（数据正确性/体验事故 — 必修）
| 模式 | 之前触发过的场景 |
|------|----------------|
| `guard xxx > Date() else return` 写在**含循环的事件**调度入口 | NM 生日/打卡提醒 startDate 过去后永久静默不响 |
| `DispatchWorkItem + DispatchQueue.main.asyncAfter` 在 `@MainActor` 类里访问成员 | EventStore/CountdownStore saveDebounce Swift 6 strict 违规 |
| push 局部 per-record 失败仍然 `dirtySet.removeAll()` | EventStore flushDirty iCloud 多设备数据发散 |
| `month/day 分量取 startDate 而非 effectiveStart` 的 yearly 重复规则 | "婚礼前 1 天提醒"当天才响 |
| `Calendar.current` 在 UNCalendar / DateComponents / 月视图里混用 | 非公历环境佛历/和历日期错乱 |

### P2（功能缺陷 / 性能）
| 模式 | 之前触发过的场景 |
|------|----------------|
| debounce `Task.sleep` 在用户立即 dismiss + 杀进程时未触发 → flush 缺失 | CountdownStore / EventStore 保存丢数据 |
| `upsert` 返回值混淆"接受与否"和"内容变没变"两个概念 | Mock LWW 冲突静默吞、written 语义错 |
| sync bidirectional `if allErrors.isEmpty { clearAllDirtyFlags }` | 成功的 2 条永远被重推直到全部成功，版本膨胀 |
| pullAndMerge 本地接受远端事件时 `updated.updatedAt = Date()` 伪 | round-trip LWW 比较本地伪 date > 真远端被误判赢 |
| ICS 导入只解析 UID/SUMMARY/DTSTART，跳过 `PRIORITY:1/5/9` 和 `STATUS:COMPLETED` | 导入后完成态提醒重新 rescheduleAllReminders 又响一遍 |

### P3（UX/视觉/边界）
| 模式 | 之前触发过的场景 |
|------|----------------|
| 可选值 fallback 用数字 `?? 0` / 空串 `?? ""` 显示在**装饰性大字号** UI 上 | Widget LunarCard 背景红色渐变上的『0月0』 |
| SwiftUI Picker / DatePicker 没有 `in:` 范围闭包且系统支持 1900/2100 外日期 | CountdownEditor/DateJumpView 越界假农历 |
| 权限 Status 只有 granted/denied 有 UI，没有 `notDetermined` 分支按钮 | SettingsView notificationCard UX 死角 |
| `.onChange` 仍然是旧 2 参数 API | iOS 18+ 已弃用，新 API 3 参数 `of:initial:_:` |

---

## 五、严重度分级标准（所有修复必须标注）

| 级别 | 定义 | 典型后果 |
|------|------|---------|
| **P1** | 数据损坏 / 用户体验事故（可复现）/ 并发崩溃 / Swift 6 strict 编译错 | 通知不响/不该响却响、iCloud 多设备不一致、删除事件数据丢失、数组越界闪退 |
| **P2** | 功能性缺陷（可替代路径存在）/ 性能 O(N²) 没缓存 / 测试基础设施错 | 部分失败导致版本膨胀、nextTerm 每次排序、Mock 无法覆盖冲突分支 |
| **P3** | UI 视觉 / UX 死角 / 边界条件极端 | 0月0 脏显示、notDetermined 权限按钮缺失、2/29 周年越界假数据 |

**修复顺序：P1 → P2 → P3。每轮必须至少有 1 个 P1/P2。**

---

## 六、Git 提交规范模板

```
fix(<模块>): <一句话概括 M 处修复>

- P<P级> <具体位置>: <根因> → <修复做法>（<影响/效果>）。
- P<P级> ...
- ...
- 构建 0.XXs，<新增后总测试数>/<总测试数> 单元测试全部通过
```

例：
```
fix(Notify+Mock): Mock LWW 冲突显式化 + 通知调度 2 处实锤修复
- P2 MockCloudKitProvider.push: 旧 upsert 失败时 written-=1，coordinator 以为全成功…
- P1 NotificationManager.scheduleNotification: 旧守卫 event.startDate>Date 一刀切…
```

---

## 七、累计修复追踪（可选：用户要统计时输出）

每轮结束时维护一个累计结构：

```
| 严重度 | 数量 | 代表问题（新增）|
|--------|------|----------------|
| P1     | N    |  |
| P2     | N    |  |
| P3     | N    |  |
| 回归test | K  |  |
| 累计修复 | M  |  |
```

---

## 八、下一轮建议方向模板（结构化选项 3 个 + 用户自由选）

每次结束报告后，列出 3 个推荐方向：
1. **产品化**：README 编译发布 / Entitlement 清单 / App Store 配置说明
2. **深挖**：当前最高剩余风险模块 + 之前没审的某模块组合
3. **加固**：新增回归 test 覆盖某修复 / iPad 适配 / Accessibility 补完

让用户单选或自行指定。
