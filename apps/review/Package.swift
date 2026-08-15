// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "QaptrReview",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "QaptrReview", targets: ["QaptrReview"]),
    ],
    targets: [
        .target(
            name: "QaptrReviewCore"
        ),
        .executableTarget(
            name: "QaptrReview",
            dependencies: ["QaptrReviewCore"]
        ),
        .testTarget(
            name: "QaptrReviewCoreTests",
            dependencies: ["QaptrReviewCore"]
        ),
        .testTarget(
            name: "QaptrReviewTests",
            dependencies: ["QaptrReview"]
        ),
    ]
)
