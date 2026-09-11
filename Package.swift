// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "LunisolarCalendar",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "LunarCore", targets: ["LunarCore"]),
        // 宿主 App / Widget Extension 通过 Xcode 以 dynamic framework 方式链接，
        // 避免 library 内的 @main 与宿主 App @main 静态链接时 duplicate symbol。
        .library(name: "LunisolarCalendarApp", type: .dynamic, targets: ["LunisolarCalendarApp"]),
        .executable(name: "gen_huangli_db", targets: ["gen_huangli_db"])
    ],
    targets: [
        // MARK: - LunarCore：纯农历/黄历算法，无 SwiftUI/UIKit 依赖
        // gen_huangli_db 只依赖这部分，避免链接 SwiftUI App 的 @main 入口
        .target(
            name: "LunarCore",
            path: "Sources/LunisolarCalendarApp",
            exclude: ["Resources"],
            sources: [
                "Models/LunarDate.swift",
                "Models/Huangli.swift"
            ]
        ),

        // MARK: - LunisolarCalendarApp：App UI + 业务逻辑 + 核心算法
        // 排除 LunarCore 已包含的文件（避免重复编译）
        //
        // ⚠️  注意：此 target 不声明 resources。
        //   原本用 .copy("Resources") 生成 SPM 资源 bundle (LunisolarCalendar_LunisolarCalendarApp.bundle)，
        //   但在 Xcode 16 / iOS 26 模拟器构建时，codesign 对该 bundle 报
        //   "bundle format unrecognized, invalid, or unsuitable"，导致整个构建失败。
        //   修复：JSON 资源直接加入 Xcode App / Widget target 的 Copy Bundle Resources，
        //   运行时通过 Bundle.resources（搜索 main + allBundles）加载，不再生成 SPM bundle。
        .target(
            name: "LunisolarCalendarApp",
            dependencies: ["LunarCore"],
            path: "Sources/LunisolarCalendarApp",
            exclude: [
                "Models/LunarDate.swift",
                "Models/Huangli.swift",
                "Info.plist",
                "Resources"
            ]
        ),

        // MARK: - 黄历离散库生成工具（CLI）
        // 只依赖 LunarCore，不链接完整 LunisolarCalendarApp，避免 @main 冲突
        .executableTarget(
            name: "gen_huangli_db",
            dependencies: ["LunarCore"],
            path: "Tools/gen_huangli_db"
        ),

        // MARK: - 测试
        .testTarget(
            name: "LunisolarCalendarTests",
            dependencies: ["LunisolarCalendarApp", "LunarCore"],
            path: "Tests/LunisolarCalendarTests",
            resources: [
                // 测试需要 huangli_db.json / lunar_calendar.json 来验证离散库命中。
                // 逐个 .process 单个文件（而非目录），让文件落在资源 bundle 根目录，
                // 避免被包在 Resources/ 子目录里导致 url(forResource:) 找不到。
                .process("../../Sources/LunisolarCalendarApp/Resources/huangli_db.json"),
                .process("../../Sources/LunisolarCalendarApp/Resources/lunar_calendar.json")
            ]
        )
    ]
)
