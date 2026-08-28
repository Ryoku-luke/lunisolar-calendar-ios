import XCTest
@testable import LunisolarCalendarApp

// MARK: - 跨用例共享辅助

@MainActor
func makeIsolatedEventStore(file: StaticString = #file, line: UInt = #line) -> EventStore {
    let baseDir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("lunisolar-test-\(UUID().uuidString)", isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
    } catch {
        XCTFail("创建测试隔离目录失败：\(error)", file: file, line: line)
    }
    return EventStore(storageBaseDir: baseDir)
}
