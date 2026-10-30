// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Overplay",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OverplayCore", targets: ["OverplayCore"]),
        .executable(name: "OverplayApp", targets: ["OverplayApp"])
    ],
    targets: [
        .target(
            name: "OverplayCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "OverplayApp",
            dependencies: ["OverplayCore"],
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Charts"),
                .linkedFramework("Combine"),
                .linkedFramework("Security"),
                .linkedFramework("UserNotifications")
            ]
        ),
        .testTarget(
            name: "OverplayCoreTests",
            dependencies: ["OverplayCore"]
        )
    ]
)
