# 全天事件跨时区错位 · 改造方案（选项 ③）

> 状态：**方案，未动代码**。这份文档只有一个目的：让你判断值不值得做、以及做的话边界在哪。
> 结论先说：可以做到**不碰 EventStore / CloudKit 同步逻辑**，但要动 `CalendarEvent` 的
> 数据语义，并且有一小部分旧数据**永远修不回来**。

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

```
init(from decoder:) 里：
  isAllDay == true 时——
    · startDay 存在（新数据）→ startDate = startDay.startOfDay(in: .current)
                                endDate   = (endDay ?? startDay).endOfDay(in: .current)
    · startDay 为 nil（旧数据）→ startDay = CalendarDayKey(startDate, in: .current)   // 尽力反推
                                其余同上
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
| **新增** `Models/CalendarDayKey.swift` | 值类型与投影工具 | 小 |
| `Support/DataPortability.swift` | ① 导出 ICS 直接用 day 分量取 `yyyyMMdd`，不再依赖 `.current`；② 导入时把 `VALUE=DATE` 解析成 day 分量；③ **伪 UID 种子改用 day 分量**（见 §7） | 中 |
| `Models/CalendarEvent.swift` `occurs(on:)` | 不改（已走本地 `startOfDay`） | — |
| `Support/NotificationManager.swift` | 不改（identifier 不含时间） | — |
| `Widgets/*`、`Stores/EventStore.swift` 快照 | 不改（读 `startDate`） | — |
| `Services/QingheActivityCoordinator.swift` | 不改（`effectiveEnd` 已走 `startOfDay + 24h`） | — |
| `Sync/*` | **不改**（payload 是整对象 JSON） | — |
| `Tests/` | 新增时区矩阵测试（见 §9） | 中 |

## 6. CloudKit / 兼容性

- **不需要改同步层**：`SyncRecord.eventRecord` 走 `JSONEncoder` 编整个事件，新字段自动进 payload。
- **新客户端读旧 payload**：`startDay == nil` → 按读取时的 `.current` 反推，从此稳定。
- **旧客户端读新 payload**：未知字段被忽略 → 仍按 `startDate` 瞬时渲染 → **仍会错位，但不会崩**。
  发版节奏上建议：等旧版本用户比例可接受后再依赖新语义。
- **payload 体积**：每条事件增加约 40 字节，可忽略。
- `isNotified` 仍按既有逻辑在编码前强制 `false`，不受影响。

## 7. 必须一起改的地方（否则会引入新 bug）

1. **伪 UID 种子（重要）**：现在无 UID 的导入事件用 `formatter("yyyyMMddHHmmss", timeZone: utcTimeZone)`
   渲染 `startDate`。改成分量存储后，`startDate` 会随设备时区变化 →
   **同一份 .ics 在不同时区重导入会算出不同 UUID → 去重失效、产生副本**。
   修法：全天事件的分量（`yyyyMMdd`）参与种子，不要用 UTC 瞬时。
2. **ICS 导出/导入**：改为直接用 day 分量，彻底摆脱「靠 `.current` 恰好正确」的状态。
3. **运行时改时区**：解码重投影只覆盖「加载」路径。App 常驻前台、用户此刻改了时区时，
   内存里的事件不会自动重算。可选补丁：监听
   `UIApplication.significantTimeChangeNotification` / `NSCalendarDayChangedNotification`
   或回前台时让 `EventStore` 重跑一次归一化。**建议放第二步**（§10 的 3b）。

## 8. 风险与边界

- **旧数据的先天损失**：旧全天事件没有记录「创建时的时区」，只能按「读取时的 `.current`」
  反推。若这条事件是别处时区创建/导入的，反推结果可能**已经**差一天——这部分**永远修不回来**。
  必须在用户可见的「已知限制」里写明，不能假装修好了。
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

单测（可在本机 `swift test` 跑，Linux/macOS 均可）：

- ☐ 同一 payload 分别在 `Asia/Shanghai` 与 `America/New_York` 下解码 →
  `startDay` 相同、且 `startDate` 在各自时区都是当地 00:00。
- ☐ 旧 payload（无 `startDay`）解码后 `startDay` 反推正确、`isAllDay` 语义不变。
- ☐ 非全天事件在任意时区解码，`startDate` 逐位不变（I3 回归保护）。
- ☐ 伪 UID：同一份全天 .ics 在两个时区下导入，UUID 一致。
- ☐ ICS 往返：全天单日事件导出再导入，仍是单日（不变成两天）。
- ☐ `occurs(on:)`：全天事件在任意时区下命中的公历日与 `startDay` 一致。

真机（需要你）：

- ☐ 设备 A 建「明天 全天」→ 设备 B（改成另一个时区）拉取 → 两机显示同一天。
- ☐ 单机：建设备时区改到 UTC−5 再重启 App → 全天事件仍落在同一天。
- ☐ 通知、Widget 快照、灵动岛候选在改时区后仍正确。

## 10. 建议的拆步（每步都能独立验证、独立回滚）

- **3a（核心，建议先做）**：`CalendarDayKey` + 模型字段 + 解码重投影 + 构造侧写入 +
  伪 UID 与 ICS 改用分量 + 时区矩阵单测。做完这一步，跨设备错位就修掉了。
- **3b（可选）**：改时区时的运行时重投影钩子。
- **3c（独立立项）**：同步判等/合并对全天事件忽略瞬时差异——涉及红线区域，单独评估。

**3a 的工作量估计**：新增 1 个文件、改 2 个文件（`CalendarEvent.swift`、`DataPortability.swift`）、
新增约 6 条单测。属于「一天内可完成、可验证」的规模，但**动数据语义**，需要你明确批准后再动手。
