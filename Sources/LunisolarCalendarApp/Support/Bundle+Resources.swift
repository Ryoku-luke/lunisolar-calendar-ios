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
    ///   2. Apple 平台：遍历 Bundle.allBundles（SPM 测试时资源在 test bundle）
    ///   3. Linux：Bundle.allBundles 会 SIGSEGV，改从可执行文件目录扫描 *.resources 目录
    static var resources: Bundle {
        if Bundle.main.url(forResource: "huangli_db", withExtension: "json") != nil {
            return .main
        }

        #if canImport(Darwin)
        // Apple 平台：Bundle.allBundles 安全可用
        for bundle in Bundle.allBundles {
            if bundle.url(forResource: "huangli_db", withExtension: "json") != nil {
                return bundle
            }
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
}
