import Foundation
import Observation

@MainActor
@Observable
public final class EventSyncCoordinator: @unchecked Sendable {

    public private(set) var status: SyncStatus = .idle
    public private(set) var lastResult: SyncResult?

    public var isEnabled: Bool = true {
        didSet {
            if !isEnabled { status = .idle }
        }
    }

    public unowned let eventStore: EventStore
    public let provider: any ICloudSyncProvider

    private let defaults: UserDefaults
    private let lastSyncKeyLo = "Lunisolar.sync.lastSyncMs.lo"
    private let lastSyncKeyHi = "Lunisolar.sync.lastSyncMs.hi"
    private let versionTrackingKey = "Lunisolar.sync.versionMap"

    private var versionMap: [String: Int64] = [:]

    public private(set) var lastSyncMs: Int64 {
        get {
            let loVal = defaults.integer(forKey: lastSyncKeyLo)
            let hiVal = defaults.integer(forKey: lastSyncKeyHi)
            let lo = UInt32(truncatingIfNeeded: loVal)
            let hi = UInt32(truncatingIfNeeded: hiVal)
            return Int64(bitPattern: (UInt64(hi) << 32) | UInt64(lo))
        }
        set {
            let bits = UInt64(bitPattern: newValue)
            let lo = UInt32(truncatingIfNeeded: bits)
            let hi = UInt32(truncatingIfNeeded: bits >> 32)
            defaults.set(Int(bitPattern: UInt(truncatingIfNeeded: lo)), forKey: lastSyncKeyLo)
            defaults.set(Int(bitPattern: UInt(truncatingIfNeeded: hi)), forKey: lastSyncKeyHi)
        }
    }

    public init(
        eventStore: EventStore,
        provider: any ICloudSyncProvider,
        defaults: UserDefaults = .standard
    ) {
        self.eventStore = eventStore
        self.provider = provider
        self.defaults = defaults
        self.loadVersionMap()
        if self.versionMap.isEmpty,
           let raw = defaults.dictionary(forKey: versionTrackingKey) as? [String: Int] {
            self.versionMap = raw.mapValues { Int64($0) }
        }
    }

    @discardableResult
    public func push(event: CalendarEvent, isDeleted: Bool = false) async throws -> SyncResult {
        try await push(events: [event], deletedIDs: isDeleted ? [event.id.uuidString] : [])
    }

    @discardableResult
    public func push(events: [CalendarEvent], deletedIDs: Set<String> = []) async throws -> SyncResult {
        let start = Date()
        status = .inProgress(.push)

        let available = await provider.isAvailable
        guard isEnabled else {
            let r = SyncResult(direction: .push, pushed: 0, pulled: 0, conflictsResolved: 0,
                               errors: [], startedAt: start, finishedAt: Date())
            status = .succeeded(r)
            lastResult = r
            return r
        }
        guard available else {
            let err = SyncError.notAvailable
            status = .failed(err)
            throw err
        }

        var records: [SyncRecord] = []
        var proposedVersions: [String: Int64] = [:]
        for ev in events {
            let nextVer = (versionMap[ev.id.uuidString] ?? 0) + 1
            let rec = try SyncRecord.eventRecord(
                for: ev,
                version: nextVer,
                originDevice: provider.currentDeviceID
            )
            records.append(rec)
            proposedVersions[ev.id.uuidString] = nextVer
        }

        for delID in deletedIDs {
            guard !records.contains(where: { $0.id == delID }) else { continue }
            let nextVer = (versionMap[delID] ?? 0) + 1
            let existing = eventStore.events.first(where: { $0.id.uuidString == delID })
            let ms: Int64 = {
                if let d = existing?.updatedAt { return Int64(d.timeIntervalSince1970 * 1000) }
                return Int64(Date().timeIntervalSince1970 * 1000)
            }()
            let tomb = SyncRecord(
                id: delID, kind: .event,
                version: nextVer, originDevice: provider.currentDeviceID,
                updatedAtMs: ms, isDeleted: true, payloadJSON: "{}"
            )
            records.append(tomb)
            proposedVersions[delID] = nextVer
        }

        let (written, perRecordErrors) = try await provider.push(records: records)

        for (id, v) in proposedVersions {
            if perRecordErrors[id] != nil { continue }
            versionMap[id] = v
        }
        persistVersionMap()

        var errors: [SyncError] = []
        for (_, e) in perRecordErrors { errors.append(e) }

        let successUpdatedMs = records.compactMap { r -> Int64? in
            if perRecordErrors[r.id] != nil { return nil }
            return r.updatedAtMs
        }
        if let maxMs = successUpdatedMs.max(), maxMs > lastSyncMs {
            lastSyncMs = maxMs
        }

        let end = Date()
        let r = SyncResult(direction: .push, pushed: written, pulled: 0,
                           conflictsResolved: 0, errors: errors,
                           startedAt: start, finishedAt: end)
        if errors.isEmpty {
            status = .succeeded(r)
        } else if let first = errors.first {
            status = .failed(first)
        }
        lastResult = r
        return r
    }

    @discardableResult
    public func pullAndMerge() async throws -> SyncResult {
        let start = Date()
        status = .inProgress(.pull)

        let available = await provider.isAvailable
        guard isEnabled else {
            let r = SyncResult(direction: .pull, pushed: 0, pulled: 0, conflictsResolved: 0,
                               errors: [], startedAt: start, finishedAt: Date())
            status = .succeeded(r); lastResult = r; return r
        }
        guard available else {
            let err = SyncError.notAvailable; status = .failed(err); throw err
        }

        let remote = try await provider.pull(sinceMs: lastSyncMs)
        var merged = 0, conflicts = 0, errors: [SyncError] = []

        for remoteRec in remote {
            let remoteEvent: CalendarEvent?
            if remoteRec.isDeleted {
                remoteEvent = nil
            } else {
                do {
                    remoteEvent = try remoteRec.decodedEvent()
                } catch {
                    errors.append(.invalidPayload("\(remoteRec.id) 解码失败"))
                    continue
                }
            }

            let localVersion = versionMap[remoteRec.id] ?? 0
            if remoteRec.version > localVersion {
                let localExisting = eventStore.events.first(where: { $0.id.uuidString == remoteRec.id })
                let isConflict: Bool = (localExisting != nil) && (localVersion > 0)
                if isConflict { conflicts += 1 }

                if remoteRec.isDeleted {
                    if let l = localExisting {
                        eventStore.delete(l, skipSync: true)
                    }
                } else if let ev = remoteEvent {
                    if localExisting != nil {
                        var updated = ev
                        updated.updatedAt = Date()
                        eventStore.update(updated, skipSync: true)
                    } else {
                        var inserted = ev
                        inserted.updatedAt = Date()
                        eventStore.add(inserted, skipSync: true)
                    }
                }
                versionMap[remoteRec.id] = remoteRec.version
                merged += 1
            }
        }
        persistVersionMap()

        if let max = remote.map(\.updatedAtMs).max(), max > lastSyncMs { lastSyncMs = max }

        let end = Date()
        let r = SyncResult(direction: .pull, pushed: 0, pulled: merged,
                           conflictsResolved: conflicts, errors: errors,
                           startedAt: start, finishedAt: end)
        if errors.isEmpty { status = .succeeded(r) } else if let f = errors.first { status = .failed(f) }
        lastResult = r
        return r
    }

    @discardableResult
    public func syncBidirectional() async throws -> SyncResult {
        guard !isSyncing else {
            if let last = lastResult {
                return last
            }
            throw SyncError.notAvailable
        }
        isSyncing = true
        defer { isSyncing = false }

        let start = Date()
        status = .inProgress(.both)

        var pushed = 0, pulled = 0, conflicts = 0, allErrors: [SyncError] = []

        let (dirtyEvents, deletedIDs) = eventStore.consumeDirtyEvents()
        if !dirtyEvents.isEmpty || !deletedIDs.isEmpty {
            do {
                let r1 = try await push(events: dirtyEvents, deletedIDs: deletedIDs)
                pushed += r1.pushed; allErrors.append(contentsOf: r1.errors)
                if allErrors.isEmpty {
                    eventStore.clearDirtyFlags()
                }
            } catch {
                allErrors.append(mapError(error))
            }
        }

        do {
            let r2 = try await pullAndMerge()
            pulled += r2.pulled; conflicts += r2.conflictsResolved
            allErrors.append(contentsOf: r2.errors)
        } catch {
            allErrors.append(mapError(error))
        }

        do {
            let ttlMs: Int64 = 30 * 86400 * 1000
            let cutoffMs = Int64(Date().timeIntervalSince1970 * 1000) - ttlMs
            _ = try await provider.purgeExpiredTombstones(olderThanMs: cutoffMs)
        } catch {
            allErrors.append(mapError(error))
        }

        let end = Date()
        let r = SyncResult(direction: .both, pushed: pushed, pulled: pulled,
                           conflictsResolved: conflicts, errors: allErrors,
                           startedAt: start, finishedAt: end)
        if allErrors.isEmpty { status = .succeeded(r) } else if let f = allErrors.first { status = .failed(f) }
        lastResult = r
        return r
    }

    private var isSyncing = false
    public static let tombstoneTTLMs: Int64 = 30 * 86400 * 1000

    @discardableResult
    public func enableSubscription(_ enable: Bool) async -> Bool {
        await provider.setupSubscription(enabled: enable)
    }

    private func persistVersionMap() {
        do {
            let data = try JSONEncoder().encode(versionMap)
            defaults.set(data, forKey: versionTrackingKey)
        } catch {
            print("[EventSyncCoordinator] persistVersionMap 编码失败: \(error)")
        }
    }

    private func loadVersionMap() {
        guard let data = defaults.data(forKey: versionTrackingKey) else { return }
        do {
            versionMap = try JSONDecoder().decode([String: Int64].self, from: data)
        } catch {
            if let raw = defaults.dictionary(forKey: versionTrackingKey) as? [String: Int] {
                versionMap = raw.mapValues { Int64($0) }
            }
            print("[EventSyncCoordinator] loadVersionMap 失败: \(error)，\(versionMap.isEmpty ? "已清空" : "已回退旧格式")")
        }
    }

    private func mapError(_ e: Error) -> SyncError {
        e as? SyncError ?? .unknown(String(describing: e))
    }

    public func resetSyncMetadata() {
        versionMap.removeAll()
        lastSyncMs = 0
        defaults.removeObject(forKey: versionTrackingKey)
        defaults.removeObject(forKey: lastSyncKeyLo)
        defaults.removeObject(forKey: lastSyncKeyHi)
    }
}
