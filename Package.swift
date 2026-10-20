// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "cccv",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "CCCVCore"),
        .executableTarget(name: "cccv", dependencies: ["CCCVCore"]),
        .testTarget(name: "CCCVCoreTests", dependencies: ["CCCVCore"]),
    ]
)
