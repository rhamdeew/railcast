// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Railcast",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "RailcastCore"),
        .executableTarget(name: "Railcast", dependencies: ["RailcastCore"]),
        .testTarget(name: "RailcastCoreTests", dependencies: ["RailcastCore"]),
    ]
)
