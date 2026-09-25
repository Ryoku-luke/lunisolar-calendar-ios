import XCTest
import LunarCore
@testable import LunisolarCalendarApp

// MARK: - EventService 的依赖注入（测试隔离）
//
// `EventService(store: isolated)` 曾只隔离事件库，倒数日那条线**硬编码** `CountdownStore.shared`：
// 「UI → Service → Store」的收口在倒数日上是假的，而且隔离测试的写入会落到真实共享 store
// （污染真实 Documents 里的 countdowns.json）。

final class EventServiceIsolationTests: XCTestCase {

    @MainActor
    private func isolatedCountdownStore() -> CountdownStore {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lunisolar-countdown-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return CountdownStore(storageBaseDir: base)
    }

    @MainActor
    func testCountdownWritesGoToInjectedStoreInsteadOfSharedSingleton() {
        let isolated = isolatedCountdownStore()
        let service = EventService(store: makeIsolatedEventStore(), countdownStore: isolated)
        let sharedBefore = CountdownStore.shared.events.count

        service.deleteCountdown(id: UUID())
        service.flushPendingSave()

        XCTAssertTrue(service.countdownStore === isolated,
                      "服务必须持有注入的倒数日 store，而不是共享单例")
        XCTAssertFalse(service.countdownStore === CountdownStore.shared)
        XCTAssertEqual(CountdownStore.shared.events.count, sharedBefore,
                       "倒数日写入不得落到共享单例（否则测试会污染真实数据）")
    }

    /// 默认参数仍应指向 App 单例（生产路径不变）
    @MainActor
    func testDefaultInitStillUsesSharedStores() {
        let service = EventService()
        XCTAssertTrue(service.store === EventStore.shared)
    }
}
