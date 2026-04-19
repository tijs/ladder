// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "ladder",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "LadderKit", targets: ["LadderKit"]),
    ],
    targets: [
        .target(
            name: "LadderKit",
            path: "Sources/LadderKit"
        ),
        .testTarget(
            name: "LadderKitTests",
            dependencies: ["LadderKit"],
            path: "Tests"
        ),
    ]
)
