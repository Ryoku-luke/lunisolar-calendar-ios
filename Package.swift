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
        .library(name: "LunisolarCalendarApp", targets: ["LunisolarCalendarApp"]),
        .executable(name: "gen_huangli_db", targets: ["gen_huangli_db"])
    ],
    targets: [
        // MARK: - LunarCore：纯农历/黄历算法，无 SwiftUI/UIKit 依赖
        // gen_huangli_db 只依赖这部分，避免链接 SwiftUI App 的 @main 入口
        .target(
            name: "LunarCore",
            path: "Sources/LunisolarCalendarApp",
            sources: [
                "Models/LunarDate.swift",
                "Models/Huangli.swift"
            ]
        ),

        // MARK: - LunisolarCalendarApp：App UI + 业务逻辑 + 核心算法
        // 排除 LunarCore 已包含的文件（避免重复编译）
        .target(
            name: "LunisolarCalendarApp",
            dependencies: ["LunarCore"],
            path: "Sources/LunisolarCalendarApp",
            exclude: [
                "Models/LunarDate.swift",
                "Models/Huangli.swift",
                "Info.plist"
            ],
            resources: [
                .copy("Resources")
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
            dependencies: ["LunisolarCalendarApp"],
            path: "Tests/LunisolarCalendarTests"
        )
    ]
)
