// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "QaptrHelper",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "QaptrHelper", targets: ["QaptrHelper"]),
    ],
    targets: [
        .target(
            name: "QaptrHelperCore"
        ),
        .executableTarget(
            name: "QaptrHelper",
            dependencies: ["QaptrHelperCore"]
        ),
        .testTarget(
            name: "QaptrHelperTests",
            dependencies: ["QaptrHelperCore"]
        ),
    ]
)
