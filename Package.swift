// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DontMiss",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "DontMiss", targets: ["DontMiss"])],
    targets: [
        .target(name: "DontMissCore"),
        .target(name: "DontMissAuth"),
        .executableTarget(name: "DontMiss", dependencies: ["DontMissCore", "DontMissAuth"]),
        .testTarget(name: "DontMissCoreTests", dependencies: ["DontMissCore"]),
        .testTarget(name: "DontMissAuthTests", dependencies: ["DontMissAuth"])
    ]
)
