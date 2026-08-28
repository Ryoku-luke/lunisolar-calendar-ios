import Foundation

// MARK: - 跨平台统一日志（Q6: print → Logger）
//
// Apple 平台使用 os.Logger（自动进 Console，可按 subsystem 过滤、带级别），
// Linux / 非 Apple 平台回退 NSLog + stderr（保证 SPM 单元测试 / Linux CI 也能看到）。
//
// 使用方式：
//   Logger.app.info("载入成功，共 \(count) 条")
//   Logger.app.error("写入失败：\(error)")
//   Logger.app.debug("当前状态 \(state, privacy: .public)")

#if canImport(os)
import os.log

public enum AppLogger {
    /// 主 App 统一日志通道；subsystem 用 Bundle ID 兜底为默认。
    public static let app: Logger = {
        let subsystem = Bundle.main.bundleIdentifier ?? "com.lunisolar.calendar.app"
        return Logger(subsystem: subsystem, category: "App")
    }()

    /// 同步 / iCloud 子通道（Console 里可单独过滤）
    public static let sync: Logger = {
        let subsystem = Bundle.main.bundleIdentifier ?? "com.lunisolar.calendar.app"
        return Logger(subsystem: subsystem, category: "Sync")
    }()
}

#else

/// Linux 回退：把日志按严重等级写到 stderr（调试工具可读），不依赖 os.log。
public enum AppLogger {
    /// 用串行队列隔离 stderr / FileHandle 访问，避开 Swift 6 对 C stdio 全局变量的并发限制。
    private nonisolated(unsafe) static let queue = DispatchQueue(label: "com.lunisolar.logger")

    public struct LoggerShim: Sendable {
        public let category: String

        fileprivate func log(level: String, _ message: String) {
            // 在 queue.async 之前把 category/level/message 全取为 Sendable 的局部变量，避免跨 actor 捕获 self
            let cat = category
            AppLogger.queue.async { @Sendable in
                let ts = ISO8601DateFormatter().string(from: Date())
                let line = "[\(ts)] [\(cat)] [\(level)] \(message)\n"
                if let data = line.data(using: .utf8) {
                    try? FileHandle.standardError.write(contentsOf: data)
                }
            }
        }

        public func info(_ message: @autoclosure () -> String)  { log(level: "INFO",  message()) }
        public func debug(_ message: @autoclosure () -> String) { log(level: "DEBUG", message()) }
        public func warning(_ message: @autoclosure () -> String) { log(level: "WARN", message()) }
        public func error(_ message: @autoclosure () -> String) { log(level: "ERROR", message()) }
        public func notice(_ message: @autoclosure () -> String) { log(level: "NOTICE", message()) }
        public func critical(_ message: @autoclosure () -> String) { log(level: "CRIT", message()) }
        public func fault(_ message: @autoclosure () -> String) { log(level: "FAULT", message()) }
    }

    public static let app  = LoggerShim(category: "App")
    public static let sync = LoggerShim(category: "Sync")
}
#endif
