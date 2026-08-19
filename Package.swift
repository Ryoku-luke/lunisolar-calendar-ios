// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "LunisolarCalendar",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "LunisolarCalendarApp", targets: ["LunisolarCalendarApp"])
    ],
    targets: [
        .target(
            name: "LunisolarCalendarApp",
            path: "Sources/LunisolarCalendarApp",
            resources: [
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "LunisolarCalendarTests",
            dependencies: ["LunisolarCalendarApp"],
            path: "Tests/LunisolarCalendarTests"
        )
    ]
)
