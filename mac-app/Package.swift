// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PhoneShot",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "PhoneShot",
            path: "Sources/PhoneShot",
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        .testTarget(name: "PhoneShotTests", dependencies: ["PhoneShot"], path: "Tests/PhoneShotTests"),
    ]
)
