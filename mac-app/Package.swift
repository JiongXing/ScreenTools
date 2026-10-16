// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ScreenTools",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ScreenTools",
            path: "Sources/ScreenTools",
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        .testTarget(name: "ScreenToolsTests", dependencies: ["ScreenTools"], path: "Tests/ScreenToolsTests"),
    ]
)
