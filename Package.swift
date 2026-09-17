// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DontMiss",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "DontMiss", targets: ["DontMiss"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(name: "DontMissCore"),
        .target(name: "DontMissAuth"),
        .executableTarget(
            name: "DontMiss",
            dependencies: ["DontMissCore", "DontMissAuth", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "DontMissCoreTests", dependencies: ["DontMissCore"]),
        .testTarget(name: "DontMissAuthTests", dependencies: ["DontMissAuth"])
    ]
)
