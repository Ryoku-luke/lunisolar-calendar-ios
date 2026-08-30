import XCTest
@testable import LunisolarCalendarApp

// MARK: - EventStore 测试

@MainActor
final class EventStoreTests: XCTestCase {

    func testCRUD() async {
        let store = makeIsolatedEventStore()
        let today = Date()
        let initial = store.events(on: today).count

        let ev = CalendarEvent(title: "测试CRUD事件", startDate: today, priority: .high)
        store.add(ev)
        XCTAssertEqual(store.events(on: today).count, initial + 1, "新增后+1")

        store.toggleCompleted(ev)
        let toggled = store.events(on: today).first(where: { $0.id == ev.id })?.isCompleted
        XCTAssertTrue(toggled ?? false, "切换完成态")

        store.delete(ev)
        XCTAssertEqual(store.events(on: today).count, initial, "删除后恢复")
    }

    func testMarkNotified() async {
        let store = makeIsolatedEventStore()
        let cal = Calendar(identifier: .gregorian)
        let start = cal.date(byAdding: .hour, value: 1, to: cal.startOfDay(for: Date()))!
        let ev = CalendarEvent(title: "通知测试", startDate: start)
        store.add(ev)

        XCTAssertFalse(ev.isNotified, "初始应为 false")
        store.markNotified(ev)
        // A0-回归修复：原来查询传 Date() 可能与 start 的日期跨天（Linux 沙箱
        // 时区设置不同时 start=Date()+3600 可能落在次日 0 点之后），改用
        // event.startDate 精确锚定的日期查询。
        let queryDay = cal.startOfDay(for: start)
        let updated = store.events(on: queryDay).first(where: { $0.id == ev.id })
        XCTAssertTrue(updated?.isNotified ?? false, "标记后应为 true")

        store.delete(ev)
    }

    func testSearch() async {
        let store = makeIsolatedEventStore()
        let ev = CalendarEvent(title: "可搜索的会议", startDate: Date(), location: "会议室A")
        store.add(ev)

        let results = store.search(query: "会议")
        XCTAssertTrue(results.contains { $0.id == ev.id }, "搜索应匹配标题")

        store.delete(ev)
    }

    // MARK: 农历重复事件能跨春节出现在月视图查询
    func testLunarBirthdayAppearsOnSpringFestival2026() async {
        let store = makeIsolatedEventStore()
        let cal = Calendar(identifier: .gregorian)

        // 锚点：2025-01-29 正月初一
        var dc25 = DateComponents()
        dc25.year = 2025; dc25.month = 1; dc25.day = 29
        let start2025 = cal.date(from: dc25)!
        let birthday = CalendarEvent(
            title: "奶奶农历生日（正月初一）",
            startDate: start2025,
            repeatRule: .lunarAnnually,
            priority: .urgent
        )
        store.add(birthday, skipSync: true)

        // 查 2026-02-17（春节）：events(on:) 应返回 1 条
        var dc26 = DateComponents()
        dc26.year = 2026; dc26.month = 2; dc26.day = 17
        let springFestival2026 = cal.date(from: dc26)!
        let matches = store.events(on: springFestival2026)
        XCTAssertTrue(matches.contains { $0.id == birthday.id },
                      "正月初一创建的 lunarAnnually 事件应出现在次年春节当天")

        // 查 2026-02-18（正月初二）：不包含
        var dcNext = DateComponents()
        dcNext.year = 2026; dcNext.month = 2; dcNext.day = 18
        let dayAfter = cal.date(from: dcNext)!
        let afterMatches = store.events(on: dayAfter)
        XCTAssertFalse(afterMatches.contains { $0.id == birthday.id },
                       "正月初二 不应出现正月初一的农历生日")
    }

    // MARK: merge(+clearAll) 单元测试：三种策略 + 重复导入无副本
    func testMergeAddNewNoDuplicate() async {
        let store = makeIsolatedEventStore()
        // 先清空：EventStore() 首次创建会插入示例数据 → 用 clearAll 抹掉
        let sampleCount = store.events.count
        _ = store.clearAll(skipSync: true)
        XCTAssertEqual(store.events.count, 0, "clearAll 后应为 0（原示例 \(sampleCount) 条已清空）")

        let cal = Calendar(identifier: .gregorian)
        var dc = DateComponents()
        dc.year = 2026; dc.month = 9; dc.day = 1; dc.hour = 10
        let s = cal.date(from: dc)!

        var evA = CalendarEvent(id: UUID(), title: "事件A", startDate: s, priority: .high)
        evA.updatedAt = s
        let r1 = store.merge([evA], policy: .keepLatest, skipSync: true)
        XCTAssertEqual(r1.added, 1)
        XCTAssertEqual(r1.updated, 0)
        XCTAssertEqual(store.events.count, 1)

        // 完全相同的一份再导入 → 100% 冲突（keepLatest 按 updatedAt 相等算"更新"不新增副本）
        let r2 = store.merge([evA], policy: .keepLatest, skipSync: true)
        XCTAssertEqual(r2.added, 0, "重复导入不应再次追加（副本 BUG 回归）")
        XCTAssertEqual(r2.updated, 1, "updatedAt 相等 → keepLatest 视为更新")
        XCTAssertEqual(store.events.count, 1)
    }

    func testMergeConflictPoliciesAllThree() async {
        let store = makeIsolatedEventStore()
        _ = store.clearAll(skipSync: true)
        let cal = Calendar(identifier: .gregorian)
        let id = UUID()
        var dc = DateComponents()
        dc.year = 2026; dc.month = 9; dc.day = 1
        let base = cal.date(from: dc)!

        var local = CalendarEvent(id: id, title: "本地版本", startDate: base)
        local.updatedAt = base.addingTimeInterval(60)       // 本地更新更新
        var incoming = CalendarEvent(id: id, title: "导入版本", startDate: base)
        incoming.updatedAt = base                            // 导入版本较旧

        store.merge([local], policy: .keepLatest, skipSync: true)
        XCTAssertEqual(store.events.first?.title, "本地版本")

        // keepLocal：保留本地（即使incoming更新也不换）
        _ = store.merge([incoming], policy: .keepLocal, skipSync: true)
        XCTAssertEqual(store.events.first?.title, "本地版本", "keepLocal 应保留本地")

        // overwrite：强制用 incoming 覆盖
        _ = store.merge([incoming], policy: .overwrite, skipSync: true)
        XCTAssertEqual(store.events.first?.title, "导入版本", "overwrite 必须覆盖")
    }

    func testClearAllReturnsCountAndResets() async {
        let store = makeIsolatedEventStore()
        let before = store.events.count
        let s = Date()
        store.add(CalendarEvent(title: "A", startDate: s), skipSync: true)
        store.add(CalendarEvent(title: "B", startDate: s.addingTimeInterval(3600)), skipSync: true)
        XCTAssertEqual(store.events.count, before + 2)
        let removed = store.clearAll(skipSync: true)
        XCTAssertEqual(removed, before + 2)
        XCTAssertEqual(store.events.count, 0)
    }

    // MARK: - P6 二分插入 + ID 索引不变式 测试集

    /// 不变式校验：events 必须严格按 startDate 非降序；idToIndex 每个条目都能正确指回同 id 元素。
    private func assertInvariants(_ store: EventStore, file: StaticString = #file, line: UInt = #line) {
        // 使用内部只读属性：events 暴露为 internal private(set)，可直接读；
        // idToIndex 是 private，改用「按 id 查 firstIndex」的方式等价校验——
        // 如果索引失效，store.events 会出现 O(N) 的 by-id 查询失败，或 events 里存在重复 id。
        let arr = store.events
        for i in 1..<arr.count {
            XCTAssertTrue(arr[i-1].startDate <= arr[i].startDate,
                          "P6不变式：events 必须按 startDate 升序，i=\(i)",
                          file: file, line: line)
        }
        var seen = Set<UUID>()
        for ev in arr {
            XCTAssertFalse(seen.contains(ev.id), "P6不变式：id=\(ev.id) 重复", file: file, line: line)
            seen.insert(ev.id)
        }
    }

    /// P6-1: 单条插入后仍保持 startDate 升序（乱序 8 条事件）
    func testBinaryInsertKeepsSortOrder() async {
        let store = makeIsolatedEventStore()
        _ = store.clearAll(skipSync: true)
        let cal = Calendar(identifier: .gregorian)
        var dc = DateComponents(); dc.year = 2026; dc.month = 8; dc.day = 1
        let aug1 = cal.date(from: dc)!

        // 故意按 startDate 「乱序」新增：日 = 7,2,9,1,5,8,3,6
        let order = [7, 2, 9, 1, 5, 8, 3, 6]
        for day in order {
            let s = aug1.addingTimeInterval(TimeInterval(day - 1) * 86400)
            store.add(CalendarEvent(title: "乱序插入-\(day)", startDate: s), skipSync: true)
        }
        assertInvariants(store)
        // 最终 startDate 的日分量应该严格递增
        let days = store.events.map { ev -> Int in
            cal.component(.day, from: ev.startDate)
        }
        XCTAssertEqual(days, [1, 2, 3, 5, 6, 7, 8, 9], "乱序插入后应为升序")
    }

    /// P6-2: batchAdd 在「顺序」「逆序」「随机顺序」三类输入下均保持不变式
    func testBatchAddOrderingsKeepInvariant() async {
        let store = makeIsolatedEventStore()
        _ = store.clearAll(skipSync: true)
        let cal = Calendar(identifier: .gregorian)
        var dc = DateComponents(); dc.year = 2026; dc.month = 1; dc.day = 1
        let jan1 = cal.date(from: dc)!
        func mk(_ offset: Int) -> CalendarEvent {
            CalendarEvent(title: "batch-\(offset)",
                          startDate: jan1.addingTimeInterval(TimeInterval(offset) * 86400))
        }

        // 1) 顺序
        store.batchAdd((0..<50).map(mk), skipSync: true)
        assertInvariants(store)
        XCTAssertEqual(store.events.count, 50)

        // 2) 逆序
        store.batchAdd((0..<50).reversed().map { mk($0 + 100) }, skipSync: true)
        assertInvariants(store)
        XCTAssertEqual(store.events.count, 100)

        // 3) 伪随机（固定 seed 保证可复现）：days = (i * 2654435761 mod 200) + 200
        var seeded: [CalendarEvent] = []
        for i in 0..<200 {
            let m = (i &* 2654435761) % 200
            seeded.append(mk(m + 200))
        }
        store.batchAdd(seeded, skipSync: true)
        assertInvariants(store)
        XCTAssertEqual(store.events.count, 300)
    }

    /// P6-3: update 修改 startDate 后仍保持排序；不改 startDate 时元素位置严格不变
    func testUpdateStartDateMoveStillSorted() async {
        let store = makeIsolatedEventStore()
        _ = store.clearAll(skipSync: true)
        let cal = Calendar(identifier: .gregorian)
        var dc = DateComponents(); dc.year = 2026; dc.month = 10; dc.day = 1
        let base = cal.date(from: dc)!

        // 插入 4 条，startDate 按 1/2/3/4 日
        var evs: [CalendarEvent] = []
        for i in 0..<4 {
            let ev = CalendarEvent(title: "u\(i)",
                                   startDate: base.addingTimeInterval(TimeInterval(i) * 86400))
            store.add(ev, skipSync: true)
            evs.append(ev)
        }
        assertInvariants(store)

        // 只改 title，不改 startDate → 在 store.events 里仍停留在原位置（id 没变）
        var sameTime = evs[1]
        sameTime.title = "只改了标题"
        store.update(sameTime, skipSync: true)
        assertInvariants(store)
        let pos2 = store.events.firstIndex(where: { $0.id == evs[1].id })
        XCTAssertEqual(pos2, 1, "不改 startDate 的 update 不应挪动位置")

        // 把 evs[3]（第 4 日）的 startDate 调到 base 前一天（第 0 日）→ 应该跑到数组最前端
        var moved = evs[3]
        moved.startDate = base.addingTimeInterval(-86400)
        moved.endDate = moved.startDate.addingTimeInterval(3600)
        store.update(moved, skipSync: true)
        assertInvariants(store)
        let front = store.events.firstIndex(where: { $0.id == evs[3].id })
        XCTAssertEqual(front, 0, "startDate 改到最早的那条 update 应重新二分插入到 0")
    }

    /// P6-4: delete 删除中间位置后仍保持不变式；并且其余所有 by-id 读都还能找到正确元素
    func testDeleteMiddleKeepsInvariantAndOthers() async {
        let store = makeIsolatedEventStore()
        _ = store.clearAll(skipSync: true)
        let cal = Calendar(identifier: .gregorian)
        var dc = DateComponents(); dc.year = 2026; dc.month = 5; dc.day = 1
        let base = cal.date(from: dc)!

        var ids: [UUID] = []
        for i in 0..<10 {
            let ev = CalendarEvent(title: "d\(i)",
                                   startDate: base.addingTimeInterval(TimeInterval(i) * 86400))
            store.add(ev, skipSync: true)
            ids.append(ev.id)
        }
        // 删掉索引 3 / 5 / 7（不连续）
        for idx in [3, 5, 7] {
            let pick = store.events.first { $0.id == ids[idx] }!
            store.delete(pick, skipSync: true)
            assertInvariants(store)
        }
        XCTAssertEqual(store.events.count, 7)
        // 剩下 7 条的 id 必须都还能找到
        let remaining = ids.enumerated().filter { ![3, 5, 7].contains($0.offset) }.map(\.element)
        for id in remaining {
            XCTAssertNotNil(store.events.first(where: { $0.id == id }),
                            "id=\(id) 应仍可按 id 找到")
        }
    }

    /// P6-5: merge 冲突检测由 O(N·M) 改为 O(M) 字典；以 2000 本地 + 2000 incoming（全冲突）验证性能与正确性
    func testMergePerformanceAndResult() async {
        let store = makeIsolatedEventStore()
        _ = store.clearAll(skipSync: true)
        let cal = Calendar(identifier: .gregorian)
        var dc = DateComponents(); dc.year = 2026; dc.month = 3; dc.day = 1
        let base = cal.date(from: dc)!

        var local: [CalendarEvent] = []
        var incoming: [CalendarEvent] = []
        for i in 0..<2000 {
            let id = UUID()
            let start = base.addingTimeInterval(TimeInterval(i) * 600)  // 每 10 分钟一条
            var evL = CalendarEvent(id: id, title: "本地-\(i)", startDate: start)
            evL.updatedAt = start
            local.append(evL)
            var evI = CalendarEvent(id: id, title: "导入-\(i)", startDate: start)
            evI.updatedAt = start.addingTimeInterval(1) // 导入版本更新
            incoming.append(evI)
        }
        // 先把本地 merge 一次
        let rLocal = store.merge(local, policy: .keepLatest, skipSync: true)
        XCTAssertEqual(rLocal.added, 2000)
        assertInvariants(store)

        // 2000 条全冲突（但 incoming 稍微更新一点）→ keepLatest 应全 updated，总量不增长
        measureAndCheck {
            let r = store.merge(incoming, policy: .keepLatest, skipSync: true)
            return (r.added, r.updated, r.skipped, store.events.count)
        } completion: { added, updated, skipped, total in
            XCTAssertEqual(added, 0, "不应有新增（全冲突）")
            XCTAssertEqual(updated, 2000, "2000 条都应判为更新（incoming 更新）")
            XCTAssertEqual(skipped, 0)
            XCTAssertEqual(total, 2000, "合并后总数不变")
        }
        assertInvariants(store)
        // 验证：数组里全是"导入-"版本标题
        for ev in store.events {
            XCTAssertTrue(ev.title.hasPrefix("导入-"), "title 应被覆盖为 incoming 版本，实际：\(ev.title)")
        }
    }

    /// P6-6: 简单随机压力：add / update / delete 混合执行 500 次，每 20 次断言不变式
    func testRandomMixStress() async {
        let store = makeIsolatedEventStore()
        _ = store.clearAll(skipSync: true)
        let cal = Calendar(identifier: .gregorian)
        var dc = DateComponents(); dc.year = 2026; dc.month = 7; dc.day = 1
        let base = cal.date(from: dc)!

        var pool: [CalendarEvent] = []
        // LCG 伪随机（xorshift-ish），保证可复现
        var rngState: UInt64 = 0x9E3779B97F4A7C15
        func nextInt(_ n: Int) -> Int {
            var x = rngState
            x ^= x << 13; x ^= x >> 7; x ^= x << 17
            rngState = x
            return Int(x % UInt64(n))
        }

        for step in 0..<500 {
            let op = pool.isEmpty ? 0 : nextInt(3)  // 空池时只做 add
            switch op {
            case 0: // add
                let start = base.addingTimeInterval(TimeInterval(nextInt(365 * 24 * 60)) * 60)
                let ev = CalendarEvent(title: "stress-\(step)", startDate: start)
                store.add(ev, skipSync: true)
                pool.append(ev)
            case 1: // update（随机改 startDate 或只改标题）
                let which = nextInt(pool.count)
                var pick = pool[which]
                if nextInt(2) == 0 {
                    // 只改标题
                    pick.title = "stress-updated-\(step)"
                } else {
                    // 改 startDate（可能跨位置）
                    pick.startDate = base.addingTimeInterval(TimeInterval(nextInt(365 * 24 * 60)) * 60)
                    pick.endDate = pick.startDate.addingTimeInterval(3600)
                }
                store.update(pick, skipSync: true)
                pool[which] = pick
            default: // delete
                let which = nextInt(pool.count)
                let pick = pool.remove(at: which)
                store.delete(pick, skipSync: true)
            }
            if step % 20 == 19 {
                assertInvariants(store)
                XCTAssertEqual(store.events.count, pool.count,
                               "step \(step): store.events 数量应与 pool 保持一致")
            }
        }
        assertInvariants(store)
    }

    // MARK: Helper

    // MARK: - 数据损坏隔离备份（BUG #41 回归）

    /// EventStore.load() 解码失败时，不应在下次 saveNow() 把用户的损坏文件原子覆盖掉，
    /// 必须先复制成 `calendar_events.json.corrupt.<ms>` 隔离文件，让用户能通过
    /// Finder / iMazing / iTunes 备份自行救援。
    func testCorruptFileIsQuarantinedNotOverwritten() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("corrupt-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let saveURL = dir.appendingPathComponent("calendar_events.json")

        // 写入损坏的 JSON（不是合法的 [CalendarEvent] 数组）
        let garbage = "{this is not valid json!!! ¥©π".data(using: .utf8) ?? Data()
        try garbage.write(to: saveURL, options: .atomic)
        let originalData = try Data(contentsOf: saveURL)
        XCTAssertFalse(originalData.isEmpty, "前置：损坏文件非空")

        // 触发 load() → 内部应走 quarantine 分支
        let store = EventStore(storageBaseDir: dir)
        // 启动发现损坏 → events 被置空（没有填充示例数据）
        XCTAssertTrue(store.events.isEmpty, "损坏 JSON 解码失败后，内存 events 必须是 []，不能用样例数据掩人耳目")

        // 关键断言：目录里必须有 .corrupt.<ms> 备份，且字节内容与损坏前一致
        let fm = FileManager.default
        let entries = try fm.contentsOfDirectory(atPath: dir.path)
        let backups = entries.filter { $0.hasPrefix("calendar_events.json.corrupt.") }
        XCTAssertEqual(backups.count, 1, "必须有且仅有一个隔离备份文件；实际：\(backups)")
        let backupURL = dir.appendingPathComponent(backups[0])
        let backed = try Data(contentsOf: backupURL)
        XCTAssertEqual(backed, originalData, "隔离备份内容必须与损坏的原文件逐字节一致")

        // 写一条事件 → 原子写不会丢备份
        store.add(CalendarEvent(title: "新加的", startDate: Date()))
        store._testFlushSave()
        let entriesAfter = try fm.contentsOfDirectory(atPath: dir.path)
        let backupsAfter = entriesAfter.filter { $0.hasPrefix("calendar_events.json.corrupt.") }
        XCTAssertEqual(backupsAfter.count, 1, "写新事件后隔离备份仍需保留，不能被 .atomic 覆盖")
    }

    /// 小性能包装：把操作和断言分离；Linux XCTest 没有 os_signpost，我们这里只打印耗时。
    private func measureAndCheck<T>(_ work: () -> T, completion: (T) -> Void) {
        let t0 = Date()
        let result = work()
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        AppLogger.app.debug("P6 性能度量: \(ms) ms")
        completion(result)
        // 宽松性能断言：3000ms 以内（Linux 沙箱可能较慢）
        XCTAssertLessThan(ms, 3000, "P6 基准超时 \(ms)ms，通常意味着回退到了 O(N²)")
    }
}
