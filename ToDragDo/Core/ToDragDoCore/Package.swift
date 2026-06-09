// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ToDragDoCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "ToDragDoCore", targets: ["ToDragDoCore"]),
        .library(name: "ToDragDoSync", targets: ["ToDragDoSync"]),
        .library(name: "ToDragDoContentTypes", targets: ["ToDragDoContentTypes"])
    ],
    targets: [
        .target(
            name: "ToDragDoCore",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .target(
            name: "ToDragDoSync",
            dependencies: ["ToDragDoCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .target(
            name: "ToDragDoContentTypes",
            dependencies: ["ToDragDoCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .testTarget(
            name: "ToDragDoCoreTests",
            dependencies: ["ToDragDoCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
