// swift-tools-version: 5.9
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
