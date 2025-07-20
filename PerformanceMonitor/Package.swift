// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "SwiftPerformanceAggregator",
    platforms: [
        .macOS(.v12),
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "SwiftPerformanceAggregator",
            targets: ["SwiftPerformanceAggregator"]),
        .executable(
            name: "spa-cli",
            targets: ["SPACommand"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.4.0"),
        .package(url: "https://github.com/vapor/vapor.git", from: "4.0.0"),
        .package(url: "https://github.com/apple/swift-metrics.git", from: "2.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.40.0")
    ],
    targets: [
        .target(
            name: "SwiftPerformanceAggregator",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Metrics", package: "swift-metrics"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
            ]),
        .executableTarget(
            name: "SPACommand",
            dependencies: [
                "SwiftPerformanceAggregator",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]),
        .testTarget(
            name: "SwiftPerformanceAggregatorTests",
            dependencies: ["SwiftPerformanceAggregator"])
    ]
)
