// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "wakeroad",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "wakeroad", targets: ["wakeroad"]),
        .executable(name: "WakeRoadApp", targets: ["WakeRoadApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .target(name: "WakeRoadCore"),
        .executableTarget(
            name: "wakeroad",
            dependencies: [
                "WakeRoadCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "WakeRoadApp",
            dependencies: ["WakeRoadCore"]
        ),
    ]
)
