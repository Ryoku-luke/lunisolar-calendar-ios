import Foundation

// MARK: - 本地存储的格式版本与目录级迁移

/// 磁盘存储的格式版本 + 目录级迁移。
///
/// **为什么需要它**：磁盘上的 `calendar_events.json` / `countdowns.json` 是**裸数组**，
/// 自身不带任何版本信息。此前唯一的保护是「记得别改格式」——而这在真机上意味着：
/// - 改了字段语义或枚举 rawValue → 旧数据解不出 → 走「逐条隔离」，用户看到的是「数据丢了」；
/// - 反向（旧版 App 读到新版数据）更糟：旧代码不认识新结构，却会照常原子写覆盖回去，
///   把新版本的字段**静默抹掉**（用户回退一次 App 就可能丢数据）。
///
/// **约定（新增格式变更时照做）**：
/// 1. **版本只增不减**。每次改磁盘结构（文件布局 / 字段语义 / 枚举 rawValue）都要
///    `StorageFormat.current += 1`，并在 `StorageMigrator.registered` 里补一条
///    `StorageMigration(from: 旧版本) { dir in … }`；
/// 2. 版本标记写在**独立小文件** `storage_format.json`，不动数据文件本身的形状——
///    旧版 App 仍能照常读裸数组，只是不认识这个标记；
/// 3. 目录里**没有**标记 = v1（本机制落地前的历史格式），这是唯一被允许的"缺省"；
///    标记**存在但读不懂** → 视为不确定，调用方必须只读（见 `MigrationError.markerUnreadable`）；
/// 4. 标记只在**迁移成功后**写入。单纯读取（哪怕读的是更新版本的数据）绝不写盘。
public enum StorageFormat {
    /// 本 App 认识的存储格式版本。
    public static let current = 1

    static let markerFileName = "storage_format.json"

    /// 版本标记文件的内容
    ///
    /// `updatedAt` 刻意用 **Unix 秒（Double）**而不是 `Date`：`Date` 的编解码依赖
    /// 两侧 `dateEncodingStrategy` 一致，一旦不一致（例如写侧 ISO8601、读侧默认数字），
    /// 标记就会「读不懂」→ 被误判成版本不确定 → 整个存储意外切成只读。
    /// 本文件刚落地时正是踩了这个坑（写 ISO8601、读默认策略，单测当场抓到）。
    struct Marker: Codable, Equatable {
        var version: Int
        var updatedAt: Double
    }

    /// 迁移结果
    public enum MigrationOutcome: Equatable {
        /// 已是指定版本（含全新空目录，以及无标记的历史目录）
        case upToDate(version: Int)
        /// 从旧版本推进到了目标版本；`applied` 是按顺序执行过的迁移名
        case migrated(from: Int, to: Int, applied: [String])
        /// 磁盘上的版本比本 App 支持的更新（例：用户回退到了旧版 App）。
        /// 调用方**必须只读**，绝不能覆盖——这是本机制要防的主要事故。
        case newerThanSupported(stored: Int, supported: Int)
    }

    enum MigrationError: Error, Equatable {
        /// 缺一环迁移。绝不能跳过：跳过就是带着旧结构继续跑，比报错更危险。
        case missingMigration(from: Int)
        /// 标记文件在，但读不懂 → 版本不确定。宁可只读，也不猜。
        case markerUnreadable
    }
}

/// 一次目录级迁移：把目录从 `from` 推进到 `from + 1`。
///
/// 只碰磁盘、不改内存；抛错即视为迁移失败，调用方按只读处理（不覆盖数据）。
/// `run` 标记 `@Sendable` 是为了让注册表能安全地做全局常量。
struct StorageMigration: Sendable {
    let from: Int
    let name: String
    let run: @Sendable (URL) throws -> Void
}

/// 目录级迁移执行器。
enum StorageMigrator {

    /// 迁移注册表。
    ///
    /// **当前为空是正常的**：`current = 1`，还没有真正需要迁移的格式变更。
    /// 机制先于需求落地，是为了下一次改格式时「有地方可写、有测试可依」，
    /// 而不是事后补一个一次性脚本。
    ///
    /// 加迁移的模板（同时把 `StorageFormat.current` +1）：
    /// ```swift
    /// StorageMigration(from: 1, name: "v1→v2：xxx 字段改名 yyy") { dir in
    ///     // 只改磁盘：读旧文件 → 写新结构（写坏就抛错，调用方会切成只读）
    /// }
    /// ```
    static let registered: [StorageMigration] = []

    /// 磁盘上的版本。目录没有标记 → 1（历史格式）；有标记但读不懂 → 抛错。
    static func storedVersion(in directory: URL) throws -> Int {
        let url = directory.appendingPathComponent(StorageFormat.markerFileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return 1 }
        guard let data = try? Data(contentsOf: url),
              let marker = try? JSONDecoder().decode(StorageFormat.Marker.self, from: data) else {
            throw StorageFormat.MigrationError.markerUnreadable
        }
        return marker.version
    }

    /// 把目录从磁盘版本推进到 `target`。
    ///
    /// - 只在**真的执行了迁移**之后写标记（读盘不写盘）；
    /// - 版本比目标新 → `.newerThanSupported`，不写任何东西。
    @discardableResult
    static func migrate(directory: URL,
                        to target: Int = StorageFormat.current,
                        migrations: [StorageMigration] = StorageMigrator.registered) throws -> StorageFormat.MigrationOutcome {
        let stored = try storedVersion(in: directory)

        if stored > target {
            return .newerThanSupported(stored: stored, supported: target)
        }
        guard stored < target else { return .upToDate(version: stored) }

        var applied: [String] = []
        for version in stored..<target {
            guard let migration = migrations.first(where: { $0.from == version }) else {
                throw StorageFormat.MigrationError.missingMigration(from: version)
            }
            try migration.run(directory)
            applied.append(migration.name)
        }
        try writeMarker(version: target, in: directory)
        return .migrated(from: stored, to: target, applied: applied)
    }

    /// 写版本标记（原子写）
    static func writeMarker(version: Int, in directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(StorageFormat.Marker(version: version,
                                                           updatedAt: Date().timeIntervalSince1970))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(StorageFormat.markerFileName),
                       options: .atomic)
    }
}
