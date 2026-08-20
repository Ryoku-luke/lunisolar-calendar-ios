// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "LunisolarCalendar",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "LunisolarCalendarApp", targets: ["LunisolarCalendarApp"]),
        .executable(name: "gen_huangli_db", targets: ["gen_huangli_db"])
    ],
    targets: [
        .target(
            name: "LunisolarCalendarApp",
            path: "Sources/LunisolarCalendarApp",
            resources: [
                .copy("Resources")
            ]
        ),
        .executableTarget(
            name: "gen_huangli_db",
            dependencies: ["LunisolarCalendarApp"],
            path: "Tools/gen_huangli_db"
        ),
        .testTarget(
            name: "LunisolarCalendarTests",
            dependencies: ["LunisolarCalendarApp"],
            path: "Tests/LunisolarCalendarTests"
        )
    ]
)
