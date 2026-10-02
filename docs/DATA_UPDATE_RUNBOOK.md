# 内置数据更新手册（到期悬崖）

本 App 有 **3 份内置数据**，它们的共同点是：**过期后静默降级**——不报错、不崩溃，
用户只会发现「功能不对了」（节气倒计时消失、放假安排全变成普通日）。
所以到期这件事必须由**我们**在到期前处理，而不是等用户报障。

---

## 1. 速查表

| 数据集 | 文件 / 位置 | 当前覆盖 | 到期日 | 到期表现 | 谁来更新 |
|---|---|---|---|---|---|
| 放假安排 | `Support/HolidayProvider.swift`（`holidayData` 字典） | 2025-01-01 ~ 2026-10-10 | **2027-01-01** | 所有日期返回 `.normal`：放假与调休全部消失 | 每年国务院通知发布后（约 11 月底）|
| 节气表 | `Support/SolarTermProvider.swift`（`entries` 数组） | 2024-01-06 ~ 2032-12-21 | **2032-12-22** | `nextTerm` 返回 nil → 节气倒计时整体消失 | 需要时按天文计算追加（见 §3）|
| 黄历离散库 | `Resources/huangli_db.json` | 2024-01-01 ~ 2028-12-31 | **2029-01-01** | 落到 `HuangliGenerator` 算法兜底——**同一算法，质量不变** | 性能/一致性需要时重新生成（见 §4）|

> 黄历那一行的「到期」与前两者**性质不同**：越界后拿到的是同一个生成算法的结果，
> 不是错误答案（审查报告 §4 已更正「经核验数据」的旧表述）。所以到期检查对它**只告警、不判失败**。

## 2. 到期检查（防线在这里）

```bash
swift test --filter DataExpiryTests        # 只跑到期检查
```

`Tests/LunisolarCalendarTests/DataExpiryTests.swift` 里两档阈值：

| 距可信边界 | 行为 | 为什么这么定 |
|---|---|---|
| < **30 天**（或已越过）| **测试失败**（仅 `correctness` 类数据集）| 放假安排每年约 11 月底公布，2027-01-01 往前 30 天是 2026-12-02——那时数据已经拿得到，失败是**可行动**的 |
| < **120 天** | 打印 `⚠️ 数据到期预警`，测试仍通过 | 留出准备时间；预警会出现在每次 `swift test` / CI 日志里 |
| 更远 | 什么都不打 | 避免长期噪音 |

「可信边界」怎么取的，写在 `DataExpiryTests.windows()` 的注释里。其中放假安排取的是
**下一个缺失年份的 1 月 1 日**（不是数据末日），因为数据末日之后的 11–12 月本就没有
法定节假日，`.normal` 是正确答案而不是降级；这条推导依赖「11–12 月无节假日条目」，
由 `testNovemberAndDecemberHaveNoHolidayEntries` **直接验证**（不是靠人记得）。

## 3. 放假安排：年度流程（最常做的一次）

数据来源：《国务院办公厅关于 XXXX 年部分节假日安排的通知》（国办发明电〔…〕… 号）。

1. 等通知发布（往年约 11 月底），拿到**放假**与**调休补班**两类日期；
2. 在 `HolidayProvider.swift` 的 `holidayData` 里按同样格式追加，
   并把文件顶部「── XXXX 年 ──」占位注释替换成实际年份；
   - `(true, "假期名")` = 放假；`(false, "假期名")` = 调休补班（周末上班）；
3. 同步更新 `HolidayProviderTests` 里的**覆盖断言**（`testDataCoverageExtendsThrough2026`
   这类写死了年份的用例，需要改成新边界）；
   - `test2027NewYearReflectsDataStage` 已经是**自更新**写法，不用动；
4. 补几条新年的锚点抽查（假期首/末一天 + 至少一个调休补班日），
   参照现有 `test2025Anchors` / 2026 的写法；
5. 数据文件顶部注释里的数据来源也要写上新的文号。

**注意**：`holidayData` 的 key 是 `yyyy-MM-dd` 且**按设备时区的日分量**匹配
（`HolidayProvider.info(for:)` 内部归一化到本地日）——补数据时不要写成 UTC 时刻。

## 4. 黄历离散库：重新生成

```bash
swift run gen_huangli_db Sources/LunisolarCalendarApp/Resources/huangli_db.json
```

- 生成器的**年份范围写死在** `Tools/gen_huangli_db/main.swift`（当前 2024-01-01 ~ 2028-12-31），
  要扩范围先改那里；
- 生成后记得同步：`HuangliDBProviderTests` 的覆盖/条数断言、
  `HuangliDBProvider.swift` 顶部注释里的体积数字（当前 436KB）、
  以及 `docs/HUANGLI_DATA_SOURCE.md` §1 的实测值；
- 换供应商数据源（而不是自己生成）的完整清单见 `docs/HUANGLI_DATA_SOURCE.md`。

## 5. 节气表

当前表由 **Swiss Ephemeris 天文计算**得到（太阳视黄经为 15° 整数倍时交节，精确到分钟），
格式见 `SolarTermProvider.swift` 顶部注释与 `entries` 数组。

要延长覆盖：按同样方法计算新年份的 24 条时刻并追加，保持 `index` 0–23 与
`SolarTermProvider.termNames` 的顺序一致，然后跑 `SolarTermGoldenTests` 校验。

**备选方案（待裁决 D4）**：改成运行时计算节气，可一次性消除这个 9 年窗口，
但改动大、且要把 golden 测试改成"与离线表一致"的对照测试。

---

## 6. 补完之后的检查清单

- [ ] `swift test --filter DataExpiryTests` 不再有该数据集的预警
- [ ] 相关 golden / 锚点测试已按新边界更新
- [ ] 文件顶部注释里的「覆盖范围 / 体积 / 数据来源文号」与实际一致
- [ ] `Tools/run_tests.sh` 五通道全绿
