// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ToDragDoCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "ToDragDoCore", targets: ["ToDragDoCore"])
    ],
    targets: [
        .target(
            name: "ToDragDoCore",
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
