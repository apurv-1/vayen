// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VayenCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "VayenCore", targets: ["VayenCore"]),
        .executable(name: "vayen-cli", targets: ["vayen-cli"]),
    ],
    targets: [
        .target(name: "VayenCore"),
        .executableTarget(
            name: "vayen-cli",
            dependencies: ["VayenCore"]
        ),
        .testTarget(
            name: "VayenCoreTests",
            dependencies: ["VayenCore"]
        ),
    ]
)
