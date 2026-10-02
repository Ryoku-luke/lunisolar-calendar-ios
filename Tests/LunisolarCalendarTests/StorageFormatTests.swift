import XCTest
@testable import LunisolarCalendarApp

// MARK: - 存储格式版本与迁移
//
// 这一层此前完全不存在：磁盘上的 `calendar_events.json` / `countdowns.json` 是裸数组，
// 没有任何版本信息，唯一的保护是「记得别改格式」。本组测试钉住四件事：
//   ① 读盘不写盘（全新目录 / 历史目录都不得因此产生文件）；
//   ② 迁移按注册表逐级执行，且只在成功后落版本标记；
//   ③ 缺环、标记读不懂、以及磁盘版本更新 → 一律**拒绝写**，绝不猜、绝不降级覆盖；
//   ④ EventStore 在「版本更新」的目录上真的一个字节都不写。
//
// ③④ 是本机制存在的理由：用户回退到旧版 App 时，旧代码会照常原子写覆盖新结构。

private func appendLog(_ text: String, to url: URL) throws {
    let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    try (existing + text + "\n").write(to: url, atomically: true, encoding: .utf8)
}

final class StorageFormatTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("storage-format-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let dir { try? FileManager.default.removeItem(at: dir) }
    }

    /// 目录内容快照（文件名 → 内容），用于断言「一个字节都没变」
    private func snapshot() -> [String: Data] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        var out: [String: Data] = [:]
        for name in names.sorted() {
            out[name] = (try? Data(contentsOf: dir.appendingPathComponent(name))) ?? Data()
        }
        return out
    }

    private var markerURL: URL { dir.appendingPathComponent("storage_format.json") }

    // MARK: - ① 读盘不写盘

    func testFreshDirectoryIsUpToDateAndWritesNothing() throws {
        let outcome = try StorageMigrator.migrate(directory: dir)
        XCTAssertEqual(outcome, .upToDate(version: 1))
        XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path),
                       "读取一个全新目录不该产生任何文件（含版本标记）")
        XCTAssertTrue(snapshot().isEmpty, "全新目录应保持为空，实际：\(snapshot().keys.sorted())")
    }

    func testLegacyDirectoryWithoutMarkerCountsAsVersion1() throws {
        // 历史格式：只有裸数组，没有版本标记
        let legacy = try JSONEncoder().encode([CalendarEvent(title: "历史事件", startDate: Date())])
        try legacy.write(to: dir.appendingPathComponent("calendar_events.json"))
        let before = snapshot()

        XCTAssertEqual(try StorageMigrator.storedVersion(in: dir), 1,
                       "没有标记 = v1（本机制落地前的格式）")
        XCTAssertEqual(try StorageMigrator.migrate(directory: dir), .upToDate(version: 1))
        XCTAssertEqual(snapshot(), before, "已经是最新版本时不该写任何东西（包括补写标记）")
    }

    // MARK: - ② 迁移逐级执行 + 只在成功后落标记

    func testMigrationChainRunsInOrderAndStampsTargetVersion() throws {
        let logURL = dir.appendingPathComponent("migration_log.txt")
        let migrations = [
            StorageMigration(from: 1, name: "v1→v2") { d in
                try appendLog("m1", to: d.appendingPathComponent("migration_log.txt"))
            },
            StorageMigration(from: 2, name: "v2→v3") { d in
                try appendLog("m2", to: d.appendingPathComponent("migration_log.txt"))
            },
        ]

        let outcome = try StorageMigrator.migrate(directory: dir, to: 3, migrations: migrations)
        XCTAssertEqual(outcome, .migrated(from: 1, to: 3, applied: ["v1→v2", "v2→v3"]))
        XCTAssertEqual(try String(contentsOf: logURL, encoding: .utf8), "m1\nm2\n",
                       "迁移必须按版本顺序执行")
        XCTAssertEqual(try StorageMigrator.storedVersion(in: dir), 3, "迁移成功后应落目标版本标记")
    }

    func testMigrationRefusesToSkipAMissingStepAndDoesNotStamp() throws {
        let migrations = [
            StorageMigration(from: 1, name: "v1→v2") { d in
                try appendLog("m1", to: d.appendingPathComponent("migration_log.txt"))
            },
        ]
        XCTAssertThrowsError(try StorageMigrator.migrate(directory: dir, to: 3, migrations: migrations)) { error in
            XCTAssertEqual(error as? StorageFormat.MigrationError, .missingMigration(from: 2),
                           "缺 v2→v3 这一环时必须报错，而不是跳过去带着旧结构继续跑")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path),
                       "迁移没走完就落标记 = 下次启动会以为已经迁移过")
    }

    func testFailingMigrationDoesNotStampVersion() throws {
        let migrations = [
            StorageMigration(from: 1, name: "v1→v2（会失败）") { _ in
                throw StorageFormat.MigrationError.markerUnreadable
            },
        ]
        XCTAssertThrowsError(try StorageMigrator.migrate(directory: dir, to: 2, migrations: migrations))
        XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path),
                       "迁移抛错时不得落标记（否则下次启动会跳过它）")
        XCTAssertEqual(try StorageMigrator.storedVersion(in: dir), 1, "版本应仍停在迁移前")
    }

    // MARK: - ③ 不确定 / 更新 → 拒绝写（本机制的核心）

    func testNewerVersionIsReportedAndLeftAlone() throws {
        try StorageMigrator.writeMarker(version: StorageFormat.current + 1, in: dir)
        let before = snapshot()

        let outcome = try StorageMigrator.migrate(directory: dir)
        XCTAssertEqual(outcome, .newerThanSupported(stored: StorageFormat.current + 1,
                                                    supported: StorageFormat.current))
        XCTAssertEqual(snapshot(), before, "被告知有更新版本时，一个字节都不该动")
    }

    /// 标记存在但读不懂：版本**不确定**。
    /// 若实现把它当作 v1，就会拿一套假设去迁移/覆盖一份可能更新的数据——所以必须拒绝。
    func testUnreadableMarkerIsRefusedRatherThanAssumedV1() throws {
        try Data("这不是 JSON".utf8).write(to: markerURL)
        let before = snapshot()

        XCTAssertThrowsError(try StorageMigrator.storedVersion(in: dir)) { error in
            XCTAssertEqual(error as? StorageFormat.MigrationError, .markerUnreadable)
        }
        XCTAssertThrowsError(try StorageMigrator.migrate(directory: dir))
        XCTAssertEqual(snapshot(), before, "版本读不懂时不得改写目录")
    }

    // MARK: - ④ EventStore：在「版本更新」的目录上绝不写盘

    @MainActor
    func testStoreOnNewerFormatDirectoryLoadsButNeverWritesAnything() throws {
        // 造一个「未来的」目录：标记版本比本 App 新，数据是当前结构（旧 App 还能读出来）
        let events = [
            CalendarEvent(title: "未来版本事件A", startDate: Date()),
            CalendarEvent(title: "未来版本事件B", startDate: Date().addingTimeInterval(3600)),
        ]
        try JSONEncoder().encode(events).write(to: dir.appendingPathComponent("calendar_events.json"))
        try StorageMigrator.writeMarker(version: StorageFormat.current + 1, in: dir)
        let before = snapshot()

        let store = EventStore(storageBaseDir: dir)
        XCTAssertTrue(store.storageIsReadOnly, "磁盘格式更新时必须切成只读")
        XCTAssertEqual(store.events.count, events.count, "只读不等于不读：用户仍应看到自己的数据")

        // 改内存 + 强制落盘（saveNow 绕过防抖）→ 目录必须纹丝不动
        store.add(CalendarEvent(title: "只读期间新增", startDate: Date()))
        store._testFlushSave()
        XCTAssertEqual(snapshot(), before,
                       "只读实例不得写任何文件（事件 / dirty 标记 / 隔离文件都不行）")
    }

    @MainActor
    func testNormalStoreIsWritableAndNotReadOnly() throws {
        let store = EventStore(storageBaseDir: dir)
        XCTAssertFalse(store.storageIsReadOnly, "普通目录不该被误判为只读")

        let event = CalendarEvent(title: "正常写入", startDate: Date())
        store.add(event)
        store._testFlushSave()

        let reloaded = EventStore(storageBaseDir: dir)
        XCTAssertTrue(reloaded.events.contains { $0.id == event.id }, "正常目录必须照常落盘")
        XCTAssertFalse(reloaded.storageIsReadOnly)
    }
}
