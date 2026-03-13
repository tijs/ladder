// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "ladder",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "LadderKit",
            path: "Sources/LadderKit"
        ),
        .executableTarget(
            name: "ladder",
            dependencies: ["LadderKit"],
            path: "Sources/CLI"
        ),
        .testTarget(
            name: "LadderKitTests",
            dependencies: ["LadderKit"],
            path: "Tests"
        ),
    ]
)
