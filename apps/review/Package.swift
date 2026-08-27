// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "QaptrReview",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "QaptrReview", targets: ["QaptrReview"])
  ],
  targets: [
    .target(
      name: "QaptrReviewCore"
    ),
    .executableTarget(
      name: "QaptrReview",
      dependencies: ["QaptrReviewCore"],
      resources: [
        .process("Resources/QaptrAperture.svg"),
        .process("Resources/qaptr_logo.svg"),
        .process("Resources/60d3b965b4421c73b8944122e46cb4999a5e2c57.svg"),
        .process("Resources/b453e64d37d7cd6258c15c3274a67f60ee559133.svg"),
        .process("Resources/09a7c03f39a2c67f85de3cfcb3d31f65ade6f607.svg"),
        .copy("Resources/Satoshi-Variable.ttf"),
      ],
      swiftSettings: [
        .define("DEBUG", .when(configuration: .debug))
      ]
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
