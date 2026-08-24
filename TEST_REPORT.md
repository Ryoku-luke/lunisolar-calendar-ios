# LunisolarCalendar iOS — 全量测试报告

> 运行时间: 2026-08-24 00:57:37  
> 测试框架: XCTest (Swift Testing Library 6.2.4)  
> 目标平台: x86_64-unknown-linux-gnu (Linux 环境模拟)  
> 构建状态: ✅ Build Complete (0.28s)

---

## 测试结果总览

| 指标 | 数值 |
|------|------|
| **执行套件数** | 9 |
| **执行用例总数** | 53 |
| **通过用例数** | **53** ✅ |
| **失败用例数** | 0 |
| **意外失败数** | 0 |
| **总耗时** | 0.50 秒 |

---

## 套件级详情

### 1. LunarDateTests — 农历转换核心 (4 tests · 0 failures)

验证公历 ↔ 农历双向转换的正确性，覆盖 1900–2100 全部有效区间，采用 17 个系统 `Calendar(identifier: .chinese)` 真值对照。

| # | 用例 | 耗时 | 验证内容 |
|---|------|------|----------|
| 1 | `testLunarConversionAccuracy` | 0.001s | 17 个真值点（基准正月初一 → 闰月 → 春节 → 今日）的 年/月/日/闰月标记 四元组精确匹配 |
| 2 | `testLeapMonthYears` | 0.0s | 2020闰四月 / 2023闰二月 / 2024无闰月 |
| 3 | `testBoundaryNilSafe` | 0.1s | 1899-12-31 → nil；2101-01-01 → nil；2026-08-19 → 非nil（边界越界防护） |
| 4 | `testReverseConversion` | 0.0s | 农历→公历反向转换：2024正月初一 → 2024-02-10 |

### 2. HuangliTests — 黄历算法 (3 tests · 0 failures)

验证传统黄历宜忌、冲煞、吉神的算法生成稳定性。

| # | 用例 | 耗时 | 验证内容 |
|---|------|------|----------|
| 1 | `testYiJiStability` | 0.0s | 同一日期连续两次 generate → 宜忌结果完全一致 |
| 2 | `testChongSha20241001` | 0.0s | 2024-10-01 戊戌日 → 冲龙（地支+生肖验证） |
| 3 | `testAuspiciousIsBool` | 0.0s | 吉日标记 isAuspicious 不崩溃 |

### 3. HuangliDBProviderTests — 黄历离散数据库 (6 tests · 0 failures)

验证离散黄历数据库（2024-2028 预置 + 2029 算法 fallback）的命中精度与一致性。

| # | 用例 | 耗时 | 验证内容 |
|---|------|------|----------|
| 1 | `testDiscreteDBHit20240101` | 0.0s | 2024-01-01 命中离散库，宜忌/冲煞/五行/神位字段齐全 |
| 2 | `testDiscreteDBHit20260819Today` | 0.0s | 今日 2026-08-19 七月初七，离散库与算法生成结果 7 项字段逐一相等 |
| 3 | `testDiscreteDBBoundaryTail` | 0.0s | 2028-12-31 仍命中离散库；2029-01-01 自动切回算法 fallback |
| 4 | `testOutOfRangeReturnsNil` | 0.0s | 1899/2101 越界日期 source=algorithm |
| 5 | `testDBConsistentWithAlgorithmForRange` | 0.005s | 2024-2028 区间随机 30 天抽样，DB 记录与算法生成在 yi/ji/chong/sha/wuxing/shenwei/auspicious 7 字段逐字相等 |
| 6 | `testCoverageDescriptionNotEmpty` | 0.0s | coverageDescription 声明覆盖 2024-2028 |

### 4. CalendarEventTests — 事件模型 (11 tests · 0 failures)

验证事件 CRUD、重复规则（含农历每年）、优先级、导入导出格式。

| # | 用例 | 耗时 | 验证内容 |
|---|------|------|----------|
| 1 | `testEndDateAutoFix` | 0.0s | endDate < startDate 时自动修正 |
| 2 | `testAllDayEventDuration` | 0.0s | 全天事件 duration = 86399 秒（24h-1s） |
| 3 | `testLunarAnnuallyRepeat` | 0.0s | 农历八月十五中秋节 → 次年同农历日匹配 |
| 4 | `testLunarAnnuallySpringFestivalAcross3Years` | 0.001s | 春节正月初一跨 2025→2026→2027 三年 occurs 命中；正月初二 不命中 |
| 5 | `testLunarAnnuallyLeapMonthMatchesFlatMonth` | 0.001s | 闰月生日（闰二月廿九）在平月年同月同日命中 |
| 6 | `testRepeatRuleLabelAndAnchor` | 0.0s | label 含"农历八月十五每年"；anchor 含"农历每年八月十五"；公历规则 label 含"10月6日" |
| 7 | `testPriorityComparison` | 0.0s | urgent > high > normal > low 链序 |
| 8 | `testICSExportImport` | 0.004s | ICS 导出→导入字段无损 |
| 9 | `testCSVExport` | 0.101s | CSV 导出含表头和标题 |
| 10 | `testLunarAnnuallySameDayEarlyHourMustMatch` | 0.001s | **BUG #1 回归**: 20:00 起锚的 lunarAnnually 事件，当天 09:00 查询必须命中；daily/weekly/monthly/yearly 规则同样 |
| 11 | `testLunarAnnuallyOutOfBoundsAnchorIsNilSafe` | 0.001s | **BUG #2 回归**: 1899/2101 超范围锚点的 label/anchorDescription/occurs 均不崩溃，返回 fallback |

### 5. EventStoreTests — 事件存储 (7 tests · 0 failures)

验证 EventStore CRUD、搜索、农历事件跨视图查询、冲突合并。

| # | 用例 | 耗时 | 验证内容 |
|---|------|------|----------|
| 1 | `testCRUD` | 0.009s | add → toggleCompleted → delete 全链路 |
| 2 | `testMarkNotified` | 0.008s | isNotified 从 false → true 切换 |
| 3 | `testSearch` | 0.007s | 关键词搜索命中标题 |
| 4 | `testLunarBirthdayAppearsOnSpringFestival2026` | 0.003s | 正月初一 lunarAnnually 事件在 2026 春节出现、正月初二不出现 |
| 5 | `testMergeAddNewNoDuplicate` | 0.007s | **副本 BUG 回归**: 同一事件第二次 merge → added=0, updated=1 |
| 6 | `testMergeConflictPoliciesAllThree` | 0.01s | keepLatest / keepLocal / overwrite 三种冲突策略行为 |
| 7 | `testClearAllReturnsCountAndResets` | 0.008s | clearAll 返回清空数量 + 事件数归零 |

### 6. DataPortabilityTests — 数据导入导出 (3 tests · 0 failures)

验证 JSON/ICS 格式往返无损、伪 UUID 稳定性、合并统计。

| # | 用例 | 耗时 | 验证内容 |
|---|------|------|----------|
| 1 | `testJSONRoundTripPreservesLunarAndFlags` | 0.001s | JSON 往返：version/exportedAt/count 顶层字段；lunarAnnually/isNotified/updatedAt 无损恢复 |
| 2 | `testICSImportPseudoUUIDStableAndRRULEParsed` | 0.002s | 同一 ICS 两次导入 → 伪 UUID 完全一致；RRULE WEEKLY + BYDAY=MO..FR 正确解析为 .workday |
| 3 | `testMergeResultCounters` | 0.009s | merge 统计：added=1, updated=1；被覆盖事件字段（priority/title）正确更新 |

### 7. ICloudSyncTests — iCloud 同步 (6 tests · 0 failures)

验证基于 MockCloudKitProvider 的完整同步流程，覆盖推送、拉取、冲突解决、增量同步、离线→上线、墓碑传播。

| # | 用例 | 耗时 | 验证内容 |
|---|------|------|----------|
| 1 | `testPushLocalEventsToCloud` | 0.008s | 3 条本地事件 → push → 云端记录数=3 |
| 2 | `testPullCloudIntoLocalMerge` | 0.018s | 云端 2 条注入 → pullAndMerge → 本地 2 条 |
| 3 | `testConflictLastWriteWins` | 0.009s | 本地 v2 vs 云端 v3 → 云端胜出（last-write-wins） |
| 4 | `testIncrementalPull` | 0.106s | 分批推送 + sinceMs 增量拉取 → 仅返回 3 条新变更 |
| 5 | `testOfflineGoOnlineBidirectionalSync` | 0.013s | **离线 → 上线双向同步**: 离线新增 4 条 → syncBidirectional → 云端 4 条（含 skipSync 后 dirty 追踪验证） |
| 6 | `testTombstoneDeletePropagation` | 0.016s | 设备 A 删除 → 云端墓碑 → 设备 B pull 后本地也删除（跨设备墓碑传播） |

### 8. WidgetSnapshotTests — Widget 数据桥 (4 tests · 0 failures)

验证主 App ↔ Widget 跨进程 JSON 快照的读写、过期、自动写入。

| # | 用例 | 耗时 | 验证内容 |
|---|------|------|----------|
| 1 | `testWriteThenReadRoundTrip` | 0.002s | 写入 WidgetSharedSnapshot → 读取 → 7 项字段全保留 |
| 2 | `testReadIgnoresStaleSnapshot` | 0.001s | 昨天的旧快照 targetDay 不匹配 → read 返回 nil（防过期） |
| 3 | `testReadMissingReturnsNil` | 0.0s | 不存在的文件名 → 安全返回 nil，不崩溃 |
| 4 | `testEventStoreAutoWritesSnapshotTodayCounts` | 0.008s | EventStore.add 后自动写 widget_snapshot.json → 今日事件数=2/完成数=1/紧急晨会排第一 |

### 9. SystemImportTests — 系统导入桥 (9 tests · 0 failures)

验证 EventKit/Contacts 导入的 DTO → CalendarEvent 映射、确定性 UUID、Stub Provider、Aggregator 聚合。

| # | 用例 | 耗时 | 验证内容 |
|---|------|------|----------|
| 1 | `testMapperPreservesAllFields` | 0.0s | DTO → Event 10 项字段（type/start/end/location/notes/repeat/priority/notification）全保留 |
| 2 | `testDeterministicUUIDStableAcrossCalls` | 0.0s | 同一 sourceID → 同一 UUID（防重复导入） |
| 3 | `testDifferentSourceIDsDifferentUUIDs` | 0.0s | 不同 sourceID → 不同 UUID |
| 4 | `testStubProviderFetchEvents` | 0.0s | Stub 正常授权 → fetch 返回 2 条 |
| 5 | `testStubProviderUnauthorized` | 0.0s | 未授权 → 抛 SystemImportError.unauthorized |
| 6 | `testAggregatorCombinesAndCollectsFailures` | 0.0s | 多 Provider 聚合：成功 1 条 + 失败 1 条（不阻塞） |
| 7 | `testContactBirthdayDTOMapsToYearlyReminder` | 0.0s | 联系人生日 DTO → .reminder 类型 + .yearly 规则 + .high 优先级 |
| 8 | `testContactBirthdayLunarAnnuallyToggle` | 0.0s | 联系人生日 → .lunarAnnually 规则 |
| 9 | `testEndToEndImportNoDuplicatesOnReimport` | 0.008s | Stub → Aggregator → EventStore.merge：首次 2 条新增；第二次 0 新增（确定性 UUID + keepLatest = 副本 BUG 回归） |

---

## 代码覆盖的 BUG 回归点

| BUG ID | 测试用例 | 描述 |
|--------|----------|------|
| BUG #1 | `testLunarAnnuallySameDayEarlyHourMustMatch` | lunarAnnually 同一天早于锚点时刻的 occurs 判断 |
| BUG #2 | `testLunarAnnuallyOutOfBoundsAnchorIsNilSafe` | 超范围锚点 label/anchorDescription/occurs 容错 |
| 副本 BUG | `testMergeAddNewNoDuplicate` / `testEndToEndImportNoDuplicatesOnReimport` | 重复导入不应产生副本 |
| 离线同步 BUG | `testOfflineGoOnlineBidirectionalSync` | skipSync 后 dirty 追踪保证 syncBidirectional 检出 |
| 墓碑传播 BUG | `testTombstoneDeletePropagation` | 跨设备删除同步 |

---

## 测试环境说明

- **Linux 环境**: 部分 WidgetKit 相关视图使用 `#if canImport(WidgetKit)` 条件编译，在 Linux 下仅测试 SnapshotStore 读写逻辑，不编译 Widget View/Provider。
- **系统 Calendar 真值**: 17 个农历真值点通过 Apple `Calendar(identifier: .chinese)` 验证。
- **Mock 驱动**: 所有 iCloud 同步测试基于 `MockCloudKitProvider` + `MockCloudKitStore` 内存实现，模拟多设备并发场景。
- **Stub 驱动**: 系统导入测试基于 `StubSystemImportProvider`，无需真实 EventKit 授权。

---

## 结论

✅ **53/53 测试全通过，0 失败，0 意外失败。**  
✅ **0 编译警告。**  
✅ **关键 BUG 回归点全部覆盖。**  
✅ **代码可安全进入 iOS 真机/模拟器集成阶段。**
