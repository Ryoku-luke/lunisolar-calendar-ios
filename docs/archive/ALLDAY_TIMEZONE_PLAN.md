# 全天事件跨时区错位 · 改造方案（选项 ③）

> 状态：**步骤 3a 已落地**（见下方「落地记录」）；3b / 3c 未做。
> 结论先说：可以做到**不碰 EventStore / CloudKit 同步逻辑**，但要动 `CalendarEvent` 的
> 数据语义，并且有一小部分旧数据**永远修不回来**。

## 落地记录（2026-09-25 · 步骤 3a）

已实现：

- 新增 `Sources/LunisolarCalendarApp/Models/CalendarDayKey.swift`（年月日值类型 + 按指定时区物化）。
- `CalendarEvent`：编码时**派生**并写入 `startDay`/`endDay`（仅全天事件）；解码时按本设备时区
  把分量物化回 `startDate`/`endDate`——**只在「瞬时所在的本机日 ≠ 分量所指的日」时才改写**。
  本机日已经对时一个字节都不动，避免顺手把「带时刻的全天事件」（编辑器允许保留原时刻）
  归一成 00:00 而挪动提醒触发时刻。旧数据（无分量）整块跳过，行为与改动前完全一致。
- `Package.swift`：LunarCore 的 `exclude` 补上 `Models/CalendarDayKey.swift`
  （约定见该文件注释：`Models/` 下新增文件默认不属于 LunarCore，不排除会有 unhandled 警告）。
- 新增 `Tests/LunisolarCalendarTests/AllDayTimeZoneTests.swift`（11 条时区矩阵断言）。
- 非全天事件、通知、Widget、时间胶囊、EventStore、同步层：**一行未改**。

与本文原方案的**三处有意偏离**（都是实现时判断后收窄的，不是遗漏）：

0. **改写条件收窄为「本机日确实漂了」**。原方案是无条件重投影。原因见 §9 的第二条勾选：
   提醒触发时刻由 `startDate` 决定，无差别归一会改变用户既有事件的提醒时间——
   而需要修的只是「显示成另一天」，不是「时间不够整」。
1. **分量不落成模型字段**。原方案写的是「给 `CalendarEvent` 加 `startDay`/`endDay` 存储属性」，
   实现改为**只存在于编码产物**（`CodingKeys` 里有、模型里没有对应属性）。
   原因：`startDate`/`endDate` 是 `var`，而编辑页是**绕过 init 直接改**的
   （`Views/EventEditView.swift` 的 `save()` 里 `copy.startDate = startDate`），
   存储属性迟早会与日期不同步。不存就不存在同步问题，编码时现算即可。
2. **伪 UID 种子 / ICS 分量改造暂缓**，理由见下方 §7 的「暂缓说明」。本步只保证
   「显示的那一天」正确，不改导入去重口径。

仍未做：3b（运行时改时区的重投影钩子）、3c（同步判等忽略瞬时差异，涉及红线区域）。

## 1. 问题是什么

全天事件在跨时区或跨设备时会整体错位一天：

- 设备 A（UTC+8）建「9 月 6 日 全天」→ 同步到设备 B（UTC−5）→ B 上显示成 **9 月 5 日**。
- 单机也一样：旅行改了系统时区，原来的全天事件会落到前一天。
- 跨天边界上更明显：`9/6 00:00+08:00` 这个瞬时等于 `2026-09-05T16:00Z`，
  在 UTC−5 渲染出来就是 9/5 11:00。

根因不是时区算错，而是**建模错了**：全天事件被存成一个**绝对瞬时**，而不是「9 月 6 日」这一天。

## 2. 现状事实（逐行读代码得到，不是印象）

| 事实 | 位置 |
|---|---|
| 模型把日期存成瞬时：`startDate` / `endDate` / `isAllDay` | `Sources/LunisolarCalendarApp/Models/CalendarEvent.swift:86-91` |
| 全天约定：`startDate` = 本地 00:00，`endDate` = `startDate + 86399`（当日 23:59:59） | `Models/CalendarEvent.swift:180-186` |
| 同步 payload = **整个 CalendarEvent 的 ISO8601 JSON**（Date 以绝对瞬时上线） | `Sync/ICloudSyncProvider.swift:96-133`、`146-158` |
| ICS 导出全天已按 `.current` 取 Y/M/D | `Support/DataPortability.swift:127-131` |
| ICS 的 `DTEND` 是排他的 → 导出 +1 天、导入 −1 秒 | `Support/DataPortability.swift:137-147`、`315-325` |
| 导入事件没有 UID 时，伪 UID 的种子用 **UTC** 渲染瞬时 | `Support/DataPortability.swift:579-583` |
| 通知 identifier 就是 `event.id.uuidString`（**不含时间**） | `Support/NotificationManager.swift:306` |
| `occurs(on:)` 用 `calendar.startOfDay(for:)`（**跟随本机时区**） | `Models/CalendarEvent.swift:203-210` |

两条对方案影响最大的：

1. **payload 是整对象 JSON** → 给模型加字段就能自动上线，同步层一行不用改。
2. **通知 identifier 不含时间、`occurs` 走本地 `startOfDay`** → 只要保证「`startDate` 永远是本设备上那一天的 00:00」，下游全部自动正确。

## 3. 目标不变量

- **I1**：全天事件的持久化真相是**年月日**，不是瞬时。
- **I2**：每台设备按自己的时区，把年月日**投影**成 `startDate`/`endDate` 再交给下游。
- **I3**：非全天事件完全不受影响（一行行为都不变）。

做到这三条，方案的关键技巧是：**在解码时重投影**。`CalendarEvent.init(from:)` 里根据
年月日分量重新算出本时区下的 `startDate`/`endDate`。于是月历、年视图、`occurs`、通知重排、
Widget 快照、时间胶囊候选——**全部读的还是 `startDate`，一行都不用改**。

## 4. 具体设计

### 4.1 新增值类型

```swift
/// 「年月日」——与时区无关的日期真相
public struct CalendarDayKey: Codable, Hashable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(_ date: Date, in calendar: Calendar = QingheCalendarContext.userCalendar)
    public func startOfDay(in calendar: Calendar = ...) -> Date?
    public func endOfDay(in calendar: Calendar = ...) -> Date?   // 23:59:59
}
```

### 4.2 模型加两个可选字段

```swift
public var startDay: CalendarDayKey?   // 全天事件必非 nil
public var endDay: CalendarDayKey?     // nil = 与 startDay 同一天
```

- `CodingKeys` 追加两项；`encode(to:)` / `init(from:)` 各加两行。
- **新字段是 optional**：旧 payload 里没有 → 解码为 nil，不报错。

### 4.3 解码时重投影（方案的核心）

> 下面是**原设计**。实现时收窄了两处，实际落地见 `init(from:)` 里的注释与 §9 勾选项：
> ① 只在「本机日 ≠ 分量所指的日」时才改写（不做无条件归一，以免挪动提醒时刻）；
> ② 旧数据不去反推，整块跳过。保留原设计是为了让你看到取舍过程。

```
init(from decoder:) 里：
  isAllDay == true 时——
    · startDay 存在（新数据）且「本机日 ≠ 分量所指的日」
        → startDate = startDay.startOfDay(in: .current)
          endDate   = (endDay ?? startDay).endOfDay(in: .current)
    · startDay 存在但本机日已经一致 → 不动（原设计是无条件改写）
    · startDay 为 nil（旧数据）→ 【实际实现】不动，保持瞬时原样（原设计是反推）
  isAllDay == false → 一切照旧，不碰 startDate/endDate
```

效果：同一条 payload 在 UTC+8 解出「9/6」，在 UTC−5 也解出「9/6」。

### 4.4 构造侧

`CalendarEvent.init(...)` 里当 `isAllDay == true` 时同时写入 `startDay` / `endDay`，
并把 `startDate`/`endDate` 归一到当日 00:00 / 23:59:59（现有 `+86399` 兜底保留）。
编辑页（`Views/EventEditView.swift:93-100,308`）已经是「全天就只显示日期」，无需改逻辑。

## 5. 逐文件改动清单

| 文件 | 改动 | 规模 |
|---|---|---|
| `Models/CalendarEvent.swift` | 新增 `startDay`/`endDay` 字段 + `CodingKeys` + 编解码重投影 + `init` 写分量 | 中 |
| **新增** `Models/CalendarDayKey.swift` | 值类型与投影工具（已实现） | 小 |
| `Support/DataPortability.swift` | 原计划 3 项（ICS 导出/导入改用分量、伪 UID 种子改用分量）**本步未做，见 §7 暂缓说明** | 中 |
| `Models/CalendarEvent.swift` `occurs(on:)` | 不改（已走本地 `startOfDay`） | — |
| `Support/NotificationManager.swift` | 不改（identifier 不含时间） | — |
| `Widgets/*`、`Stores/EventStore.swift` 快照 | 不改（读 `startDate`） | — |
| `Services/QingheActivityCoordinator.swift` | 不改（`effectiveEnd` 已走 `startOfDay + 24h`） | — |
| `Sync/*` | **不改**（payload 是整对象 JSON） | — |
| `Tests/` | 新增时区矩阵测试（已实现，10 条） | 中 |

## 6. CloudKit / 兼容性

- **不需要改同步层**：`SyncRecord.eventRecord` 走 `JSONEncoder` 编整个事件，新字段自动进 payload。
- **新客户端读旧 payload**：`startDay == nil` → **不反推、不改写**，保持解码出的瞬时原样。
  实现时定为「不反推」：创建时的时区没有被记录下来，反推只是把读取设备的时区当成真相，
  并不能提高正确性，却会让同一份旧数据在不同设备上解读不一致。行为因此与改动前完全一致。
- **新客户端读新 payload**：只有当「瞬时所在的本机日」与分量不一致时才改写，一致时一个字节都不动
  （见 §9 第二条）。因此同一设备上的重复解码是幂等的，不会随解码次数漂移。
- **旧 payload 被重新编码时会自动补上分量**：`encode(to:)` 总是从当时的
  `startDate`/`endDate` 现算分量，所以任何一次 push/保存都会给旧事件盖上分量。
  代价：若这条旧事件本来就是别处时区创建的，盖上的会是**当前设备理解的那一天**，
  于是错误被固化下来。这是无法避免的（原时区不可复原），已在 §8 列明。

- **旧客户端读新 payload**：未知字段被忽略 → 仍按 `startDate` 瞬时渲染 → **仍会错位，但不会崩**。
  发版节奏上建议：等旧版本用户比例可接受后再依赖新语义。
- **payload 体积**：每条事件增加约 40 字节，可忽略。
- `isNotified` 仍按既有逻辑在编码前强制 `false`，不受影响。

## 7. 必须一起改的地方（否则会引入新 bug）

> **暂缓说明（2026-09-25 实现时决定）**：下面第 1、2 条本步**未做**。核对后判定它们
> 应当独立成一步，因为直接改会**换来另一个方向的一次性重复**：
> 把伪 UID 种子从「UTC 渲染瞬时」换成「本地年月日」后，已经导入过的**无 UID 全天事件**
> 种子值会变，升级后再导入同一份 .ics 即产生副本。
> （我们自己的导出带 `UID:`，走的是 `uid:` 分支，不受影响；受影响的是无 UID 的第三方 .ics。）
> 正确做法是让导入端同时认「新种子」与「旧种子」两个别名，而 `importICS` 目前拿不到
> 既有事件库（`public static func importICS(_ content: String) -> [CalendarEvent]`），
> 属接口改动。因此单独立项，不塞进 3a。
> **本步造成的新暴露面**：设备改时区后重导入同一份无 UID 全天 .ics，可能产生副本
> （改动前不会）。这是已知的、范围很窄的代价，记录在此以免日后被当成新 bug。

1. **伪 UID 种子（重要，本步未做）**：现在无 UID 的导入事件用 `formatter("yyyyMMddHHmmss", timeZone: utcTimeZone)`
   渲染 `startDate`。改成分量存储后，`startDate` 会随设备时区变化 →
   **同一份 .ics 在不同时区重导入会算出不同 UUID → 去重失效、产生副本**。
   修法：全天事件的分量（`yyyyMMdd`）参与种子，不要用 UTC 瞬时；并同时认旧种子别名。
2. **ICS 导出/导入（本步未做）**：改为直接用 day 分量，彻底摆脱「靠 `.current` 恰好正确」的状态。
   现状是可用的：导出按 `.current` 取 Y/M/D，导入按 `.current` 解成当地 00:00，与新不变量自洽。
3. **运行时改时区**：解码重投影只覆盖「加载」路径。App 常驻前台、用户此刻改了时区时，
   内存里的事件不会自动重算。可选补丁：监听
   `UIApplication.significantTimeChangeNotification` / `NSCalendarDayChangedNotification`
   或回前台时让 `EventStore` 重跑一次归一化。**建议放第二步**（§10 的 3b，本步未做）。

## 8. 风险与边界

- **旧数据的先天损失**：旧全天事件没有记录「创建时的时区」。实现选择**不反推**（见 §6），
  所以旧数据在新版本里的显示与改动前一致：若它当初是别处时区创建的，它会继续差一天——
  这部分**永远修不回来**。而且一旦这台设备把它重新编码（编辑一次或同步 push 一次），
  分量会被盖上「当前设备理解的那一天」，错误就此固化。必须在用户可见的
  「已知限制」里写明，不能假装修好了。
- **跨设备瞬时不一致**：payload 里仍会写 `startDate` 瞬时，两台不同时区的设备对同一条全天事件
  的 `startDate` 不同。按 `updatedAt` 的「保留最新」合并可能产生无意义的互相覆盖
  （内容其实一样，只是瞬时不同）。彻底解法是让合并判据对全天事件忽略 `startDate` 的瞬时差异——
  那要动 `EventStore.merge` / 同步判等，**属于你划过红线的区域**，我认为应当单独立项评估，
  不塞进这次改造。
- **我无法在本机验证**：真机时区切换、CloudKit 跨设备一致性都测不了。这套方案的正确性只能
  在单测（时区矩阵）里证明「模型层不变量成立」，跨设备行为必须你实机验证。
- **不做的事**：不改农历核心、不改 EventStore 的存储与防抖、不改同步协议、不引入第二套日期类型
  （复用 `Date` + 分量，而不是换掉 `Date`）。

## 9. 验证计划

**已落地**：`Tests/LunisolarCalendarTests/AllDayTimeZoneTests.swift`（11 条，`swift test` 全绿）。
原计划里「伪 UID 一致」「ICS 往返」两项属于暂缓的第 1、2 条，未覆盖（见 §7 暂缓说明）；
ICS 往返的旧语义仍由原有的 `DataPortabilityTests.testICSAllDayDTENDEndDateExclusiveSemantics` 守着。

实际落地的断言（对应下文勾选项）：

- ☑ 同一份年月日在 `Asia/Shanghai` 与 `America/New_York` 下物化 → 都是当地 9/6 00:00，
  且两个瞬时相差 12 小时（证明「同一天、不同瞬时」）。
- ☑ **本机日已经对时，瞬时一个字节都不动**（`testPayloadWithMatchingLocalDayKeepsInstantsUntouched`）。
  这是刻意收窄爆炸半径的保证：编辑器允许把日程切成「全天」却保留原时刻（如 14:00），
  而 `startDate` 决定提醒触发时刻——无差别归一成 00:00 会悄悄挪动用户的提醒时间。
- ☑ 分量所指的日与本机日**不一致**时（`testPayloadWithWrongLocalDayIsCorrected`：分量 9/20、
  瞬时 9/5 16:00Z），解码必须纠正到 9/20。任何时区都不可能把 9/5 16:00Z 理解成 9/20，
  因此这条**在旧代码上必然失败，且与跑测试的机器处于哪个时区无关**——本套件里真正的回归断言。
- ☑ 分量所指的日解出来就是那天（`testAllDayPayloadDecodesToIntendedDay`，9/6 那条）。
- ☑ 旧 payload（无分量）解码后**瞬时逐位不变**（不是原计划写的「反推」）。
- ☑ 非全天事件即使 payload 里带了分量也不被改写（I3 保护）。
- ☑ 编码侧：全天事件带分量、非全天事件不带。
- ☑ 同一天编码再解码幂等（分量与 `startDate` 不漂移）。
- ☑ 多日全天事件不塌缩成单日；分量倒挂（结束早于开始）时退回单日且保持 `endDate > startDate`。
- ☐ 伪 UID 一致、ICS 往返 —— 属暂缓项。
- ☐ `occurs(on:)` 的时区一致性 —— 未单独写测试（它读 `startDate`，由上面「解出来就是那天」间接覆盖）。

真机（需要你）：

- ☐ 设备 A 建「明天 全天」→ 设备 B（改成另一个时区）拉取 → 两机显示同一天。
- ☐ 单机：建设备时区改到 UTC−5 再**重启** App → 全天事件仍落在同一天。
- ☐ 通知、Widget 快照、灵动岛候选在改时区后仍正确。

## 10. 建议的拆步（每步都能独立验证、独立回滚）

- **3a（核心）——已落地**：`CalendarDayKey` + 编码侧派生分量 + 解码重投影 + 时区矩阵单测。
  跨设备错位的显示问题已修掉。伪 UID 与 ICS 分量改造未做（见 §7）。
- **3b（可选）——未做**：改时区时的运行时重投影钩子。
- **3c（独立立项）——未做**：同步判等/合并对全天事件忽略瞬时差异，涉及红线区域。

实际工作量：新增 2 个文件（`CalendarDayKey.swift`、`AllDayTimeZoneTests.swift`），
改 2 个（`CalendarEvent.swift`、`Package.swift`），比原估的少动了 `DataPortability.swift`。

