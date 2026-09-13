import Foundation

extension Bundle {
    /// 返回包含应用资源（huangli_db.json / lunar_calendar.json）的 bundle。
    ///
    /// 历史：原本 SPM `LunisolarCalendarApp` target 声明了 `.copy("Resources")`，
    /// 由 `Bundle.module` 访问。但 Xcode 16 / iOS 26 模拟器构建时，生成的
    /// `LunisolarCalendar_LunisolarCalendarApp.bundle` 被 codesign 拒绝
    /// （"bundle format unrecognized, invalid, or unsuitable"），构建失败。
    ///
    /// 修复：资源不再走 SPM library bundle，而是直接加入 Xcode App / Widget target 的
    /// Copy Bundle Resources；测试资源加在 SPM test target 上。
    ///
    /// 查找策略：
    ///   1. Bundle.main（App / Widget 运行时上下文，资源在主 bundle）
    ///   2. Apple 平台：遍历 Bundle.allBundles / allFrameworks（SPM 测试时资源可能在 test bundle）
    ///   3. Apple 平台：扫描 main 与所有已加载 bundle 所在目录及其父级下的 *.bundle。
    ///      `swift test` 时 SPM 把测试资源产物（如 LunisolarCalendar_LunisolarCalendarTests.bundle）
    ///      放在 LunisolarCalendarPackageTests.xctest 的同级（debug/）目录，该 bundle 不会被
    ///      自动注册进 allBundles，必须显式按路径加载。
    ///   4. Linux：Bundle.allBundles 会 SIGSEGV，改从可执行文件目录扫描 *.resources 目录
    static var resources: Bundle {
        if let hit = bundleContainingResource(in: [.main]) {
            return hit
        }

        #if canImport(Darwin)
        // Apple 平台：Bundle.allBundles 安全可用
        if let hit = bundleContainingResource(in: Bundle.allBundles + Bundle.allFrameworks) {
            return hit
        }

        // swift test：SPM 资源 bundle 与 .xctest 同目录，按路径显式发现并加载。
        if let spmBundle = discoverSPMResourceBundle() {
            return spmBundle
        }
        #else
        // Linux：Bundle.allBundles 在 swift-corelibs-foundation 上会触发 SIGSEGV，
        // 改为扫描可执行文件所在目录下的 *.resources 目录（SPM 测试资源的存放位置）。
        if let exePath = Bundle.main.executablePath {
            let exeDir = URL(fileURLWithPath: exePath).deletingLastPathComponent()
            if let contents = try? FileManager.default.contentsOfDirectory(
                at: exeDir, includingPropertiesForKeys: nil
            ) {
                for url in contents where url.pathExtension == "resources" {
                    if FileManager.default.fileExists(
                        atPath: url.appendingPathComponent("huangli_db.json").path
                    ) {
                        return Bundle(url: url) ?? .main
                    }
                }
            }
        }
        #endif

        // 兜底：找不到也返回 main，调用方自行处理 nil
        return .main
    }

    /// 在给定 bundle 集合中查找直接包含 huangli_db.json 的那个。
    private static func bundleContainingResource(in bundles: [Bundle]) -> Bundle? {
        for bundle in bundles
        where bundle.url(forResource: "huangli_db", withExtension: "json") != nil {
            return bundle
        }
        return nil
    }

    #if canImport(Darwin)
    /// 从 main 与所有已加载 bundle 的所在目录开始，向上回溯若干层，
    /// 寻找直接包含 huangli_db.json 的 *.bundle（SPM 测试资源产物）。
    private static func discoverSPMResourceBundle() -> Bundle? {
        var searchRoots: [URL] = [Bundle.main.bundleURL]
        for b in Bundle.allBundles + Bundle.allFrameworks {
            searchRoots.append(b.bundleURL)
        }

        var examined = Set<URL>()
        for root in searchRoots {
            var dir = root
            // 最多向上回溯 5 层：覆盖 .xctest/Contents/MacOS → debug/ 等结构
            for _ in 0..<5 {
                if examined.contains(dir) { break }
                examined.insert(dir)

                if let contents = try? FileManager.default.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: [.isDirectoryKey]
                ) {
                    for url in contents where url.pathExtension == "bundle" {
                        if let candidate = Bundle(url: url),
                           candidate.url(forResource: "huangli_db", withExtension: "json") != nil {
                            return candidate
                        }
                    }
                }

                let parent = dir.deletingLastPathComponent()
                if parent == dir { break }
                dir = parent
            }
        }
        return nil
    }
    #endif
}
