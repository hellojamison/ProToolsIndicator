// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ProToolsIndicator",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ProToolsIndicator", targets: ["ProToolsIndicator"]),
        .executable(name: "pt-indicator", targets: ["PTIndicatorCLI"]),
    ],
    targets: [
        .target(name: "IndicatorCore"),
        .executableTarget(name: "ProToolsIndicator", dependencies: ["IndicatorCore"]),
        .executableTarget(name: "PTIndicatorCLI", dependencies: ["IndicatorCore"]),
        .testTarget(name: "IndicatorCoreTests", dependencies: ["IndicatorCore"]),
    ]
)
